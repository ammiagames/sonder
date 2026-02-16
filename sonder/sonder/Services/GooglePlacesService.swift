//
//  GooglePlacesService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import CoreLocation

// MARK: - DTO Models (New Places API)

/// Place from autocomplete suggestions
struct PlacePrediction: Identifiable {
    let placeId: String
    let mainText: String
    let secondaryText: String
    let distanceMeters: Int?

    var id: String { placeId }
    var description: String { "\(mainText), \(secondaryText)" }
}

/// Place details from the API
struct PlaceDetails: Hashable, Identifiable {
    var id: String { placeId }
    let placeId: String
    let name: String
    let formattedAddress: String
    let latitude: Double
    let longitude: Double
    let types: [String]
    let photoReference: String?
    let rating: Double?           // Google's star rating (1-5)
    let userRatingCount: Int?     // Number of reviews
    let priceLevel: PriceLevel?   // $ to $$$$
    let editorialSummary: String? // Google's description
}

/// Price level from Google Places
enum PriceLevel: String, Codable {
    case free = "PRICE_LEVEL_FREE"
    case inexpensive = "PRICE_LEVEL_INEXPENSIVE"
    case moderate = "PRICE_LEVEL_MODERATE"
    case expensive = "PRICE_LEVEL_EXPENSIVE"
    case veryExpensive = "PRICE_LEVEL_VERY_EXPENSIVE"

    var displayString: String {
        switch self {
        case .free: return "Free"
        case .inexpensive: return "$"
        case .moderate: return "$$"
        case .expensive: return "$$$"
        case .veryExpensive: return "$$$$"
        }
    }
}

/// Nearby place
struct NearbyPlace: Identifiable {
    let placeId: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let types: [String]
    let photoReference: String?

    var id: String { placeId }
}

// MARK: - Google Places Service (New API)

@Observable
@MainActor
final class GooglePlacesService {
    private let session: URLSession
    private var debounceTask: Task<Void, Never>?

    var isLoading = false
    var error: PlacesError?

    enum PlacesError: LocalizedError {
        case invalidAPIKey
        case networkError(Error)
        case invalidResponse
        case apiError(String)
        case offline

        var errorDescription: String? {
            switch self {
            case .invalidAPIKey:
                return "Invalid Google Places API key."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Google Places API."
            case .apiError(let message):
                return "API error: \(message)"
            case .offline:
                return "You're offline. Search requires an internet connection."
            }
        }
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Autocomplete

    func autocomplete(query: String, location: CLLocationCoordinate2D? = nil) async -> [PlacePrediction] {
        debounceTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        // Debounce
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(GooglePlacesConfig.autocompleteDebounceMs))
        }

        do {
            try await debounceTask?.value
        } catch {
            return []
        }

        guard !Task.isCancelled else { return [] }

        isLoading = true
        error = nil
        defer { isLoading = false }

        // Build request
        let url = URL(string: "\(GooglePlacesConfig.baseURL)/places:autocomplete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(GooglePlacesConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["input": query]

        if let location = location {
            body["locationBias"] = [
                "circle": [
                    "center": ["latitude": location.latitude, "longitude": location.longitude],
                    "radius": Double(GooglePlacesConfig.nearbyRadiusMeters)
                ]
            ]
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }

            // Check for error
            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                self.error = .apiError(message)
                return []
            }

            // Parse suggestions
            guard let suggestions = json["suggestions"] as? [[String: Any]] else {
                return []
            }

            return suggestions.compactMap { suggestion -> PlacePrediction? in
                guard let placePrediction = suggestion["placePrediction"] as? [String: Any],
                      let placeId = placePrediction["placeId"] as? String,
                      let structuredFormat = placePrediction["structuredFormat"] as? [String: Any],
                      let mainText = (structuredFormat["mainText"] as? [String: Any])?["text"] as? String else {
                    return nil
                }

                let secondaryText = (structuredFormat["secondaryText"] as? [String: Any])?["text"] as? String ?? ""
                let distanceMeters = placePrediction["distanceMeters"] as? Int

                return PlacePrediction(placeId: placeId, mainText: mainText, secondaryText: secondaryText, distanceMeters: distanceMeters)
            }
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            self.error = .offline
            return []
        } catch {
            self.error = .networkError(error)
            return []
        }
    }

    // MARK: - Place Details

    func getPlaceDetails(placeId: String) async -> PlaceDetails? {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let url = URL(string: "\(GooglePlacesConfig.baseURL)/places/\(placeId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(GooglePlacesConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("id,displayName,formattedAddress,location,types,photos,rating,userRatingCount,priceLevel,editorialSummary", forHTTPHeaderField: "X-Goog-FieldMask")

        do {
            let (data, _) = try await session.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.error = .invalidResponse
                return nil
            }

            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                self.error = .apiError(message)
                return nil
            }

            guard let location = json["location"] as? [String: Any],
                  let lat = location["latitude"] as? Double,
                  let lng = location["longitude"] as? Double else {
                self.error = .invalidResponse
                return nil
            }

            let displayName = (json["displayName"] as? [String: Any])?["text"] as? String ?? ""
            let formattedAddress = json["formattedAddress"] as? String ?? ""
            let types = json["types"] as? [String] ?? []

            // Extract first photo reference if available
            let photoReference: String?
            if let photos = json["photos"] as? [[String: Any]],
               let firstPhoto = photos.first,
               let photoName = firstPhoto["name"] as? String {
                photoReference = photoName
            } else {
                photoReference = nil
            }

            // Rating and reviews
            let rating = json["rating"] as? Double
            let userRatingCount = json["userRatingCount"] as? Int

            // Price level
            let priceLevel: PriceLevel?
            if let priceLevelString = json["priceLevel"] as? String {
                priceLevel = PriceLevel(rawValue: priceLevelString)
            } else {
                priceLevel = nil
            }

            // Editorial summary
            let editorialSummary = (json["editorialSummary"] as? [String: Any])?["text"] as? String

            return PlaceDetails(
                placeId: placeId,
                name: displayName,
                formattedAddress: formattedAddress,
                latitude: lat,
                longitude: lng,
                types: types,
                photoReference: photoReference,
                rating: rating,
                userRatingCount: userRatingCount,
                priceLevel: priceLevel,
                editorialSummary: editorialSummary
            )
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            self.error = .offline
            return nil
        } catch {
            self.error = .networkError(error)
            return nil
        }
    }

    // MARK: - Nearby Search

    func nearbySearch(location: CLLocationCoordinate2D, radius: Int? = nil) async -> [NearbyPlace] {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let searchRadius = radius ?? GooglePlacesConfig.nearbyRadiusMeters

        let url = URL(string: "\(GooglePlacesConfig.baseURL)/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(GooglePlacesConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.types,places.photos", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": location.latitude, "longitude": location.longitude],
                    "radius": Double(searchRadius)
                ]
            ],
            "includedTypes": ["restaurant", "cafe", "bar", "tourist_attraction", "museum", "park", "store"],
            "maxResultCount": 20
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return []
            }

            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                self.error = .apiError(message)
                return []
            }

            guard let places = json["places"] as? [[String: Any]] else {
                return []
            }

            return places.compactMap { place -> NearbyPlace? in
                guard let placeId = place["id"] as? String,
                      let location = place["location"] as? [String: Any],
                      let lat = location["latitude"] as? Double,
                      let lng = location["longitude"] as? Double else {
                    return nil
                }

                let name = (place["displayName"] as? [String: Any])?["text"] as? String ?? ""
                let address = place["formattedAddress"] as? String ?? ""
                let types = place["types"] as? [String] ?? []

                // Extract first photo reference
                let photoReference: String?
                if let photos = place["photos"] as? [[String: Any]],
                   let firstPhoto = photos.first,
                   let photoName = firstPhoto["name"] as? String {
                    photoReference = photoName
                } else {
                    photoReference = nil
                }

                return NearbyPlace(
                    placeId: placeId,
                    name: name,
                    address: address,
                    latitude: lat,
                    longitude: lng,
                    types: types,
                    photoReference: photoReference
                )
            }
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            self.error = .offline
            return []
        } catch {
            self.error = .networkError(error)
            return []
        }
    }

    // MARK: - Photo URL

    /// Generates a URL to fetch a place photo
    /// - Parameters:
    ///   - photoReference: The photo resource name from the API
    ///   - maxWidth: Maximum width in pixels (default 400 for thumbnails)
    /// - Returns: URL to fetch the photo
    static func photoURL(for photoReference: String, maxWidth: Int = 400) -> URL? {
        var components = URLComponents(string: "\(GooglePlacesConfig.baseURL)/\(photoReference)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: "\(maxWidth)"),
            URLQueryItem(name: "key", value: GooglePlacesConfig.apiKey)
        ]
        return components?.url
    }
}
