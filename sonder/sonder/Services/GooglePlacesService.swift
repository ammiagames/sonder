//
//  GooglePlacesService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import UIKit
import CoreLocation
import GooglePlacesSwift
import os

// MARK: - DTO Models

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

// MARK: - Google Places Service (SDK + REST photos)

@Observable
@MainActor
final class GooglePlacesService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "GooglePlacesService")
    private let session: URLSession
    private var debounceTask: Task<Void, Never>?

    /// Optional closure that checks SwiftData cache for a photo reference before making a REST call.
    /// Injected at app launch to keep this service decoupled from SwiftData/PlacesCacheService.
    var cachedPhotoReferenceLookup: ((String) -> String?)?

    /// Session token for grouping autocomplete + place details into a single billing session.
    /// Created when autocomplete starts, consumed when getPlaceDetails is called.
    private var sessionToken: AutocompleteSessionToken?

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

    /// Call once at app launch before using any other methods.
    static func configure() {
        _ = PlacesClient.provideAPIKey(GooglePlacesConfig.apiKey)
    }

    // MARK: - Autocomplete (SDK)

    func autocomplete(query: String, location: CLLocationCoordinate2D? = nil) async -> [PlacePrediction] {
        debounceTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        // Debounce
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(GooglePlacesConfig.autocompleteDebounceMs))
        }

        await debounceTask?.value

        guard !Task.isCancelled else { return [] }

        isLoading = true
        error = nil
        defer { isLoading = false }

        // Create a session token if we don't have one (start of a new search session)
        if sessionToken == nil {
            sessionToken = AutocompleteSessionToken()
        }

        // Build filter
        let filter: AutocompleteFilter
        if let location {
            let center = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let bias = CircularCoordinateRegion(
                center: location,
                radius: Double(GooglePlacesConfig.nearbyRadiusMeters)
            )
            filter = AutocompleteFilter(origin: center, coordinateRegionBias: bias)
        } else {
            filter = AutocompleteFilter()
        }

        let request = AutocompleteRequest(
            query: query,
            sessionToken: sessionToken,
            filter: filter
        )

        switch await PlacesClient.shared.fetchAutocompleteSuggestions(with: request) {
        case .success(let suggestions):
            return suggestions.compactMap { suggestion -> PlacePrediction? in
                guard case .place(let placeSuggestion) = suggestion else { return nil }

                let distanceMeters: Int?
                if let distance = placeSuggestion.distance {
                    distanceMeters = Int(distance.converted(to: .meters).value)
                } else {
                    distanceMeters = nil
                }

                return PlacePrediction(
                    placeId: placeSuggestion.placeID,
                    mainText: String(placeSuggestion.attributedPrimaryText.characters),
                    secondaryText: placeSuggestion.attributedSecondaryText.map { String($0.characters) } ?? "",
                    distanceMeters: distanceMeters
                )
            }
        case .failure(let placesError):
            self.error = mapSDKError(placesError)
            return []
        }
    }

    // MARK: - Place Details (SDK + REST photo reference)

    func getPlaceDetails(placeId: String) async -> PlaceDetails? {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Consume the session token if one exists (closes the autocomplete billing session)
        let token = sessionToken
        sessionToken = nil

        let placeProperties: [PlaceProperty] = [
            .placeID,
            .displayName,
            .formattedAddress,
            .coordinate,
            .types,
            .photos,
            .rating,
            .numberOfUserRatings,
            .priceLevel,
            .editorialSummary,
        ]

        let request = FetchPlaceRequest(
            placeID: placeId,
            placeProperties: placeProperties,
            sessionToken: token
        )

        switch await PlacesClient.shared.fetchPlace(with: request) {
        case .success(let place):
            // Always attempt to fetch the photo reference via REST.
            // The SDK Photo struct doesn't expose the resource name needed for REST photo URLs,
            // and place.photos may be nil even when photos are available via REST.
            let photoReference = await fetchPhotoReference(placeId: placeId)
            return mapPlaceToDetails(place, photoReference: photoReference)

        case .failure(let placesError):
            self.error = mapSDKError(placesError)
            return nil
        }
    }

    // MARK: - Nearby Search (SDK)

    func nearbySearch(location: CLLocationCoordinate2D, radius: Int? = nil) async -> [NearbyPlace] {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let searchRadius = Double(radius ?? GooglePlacesConfig.nearbyRadiusMeters)
        let restriction = CircularCoordinateRegion(center: location, radius: searchRadius)

        let placeProperties: [PlaceProperty] = [
            .placeID,
            .displayName,
            .formattedAddress,
            .coordinate,
            .types,
            .photos,
        ]

        let includedTypes: Set<PlaceType> = [
            PlaceType(rawValue: "restaurant"),
            PlaceType(rawValue: "cafe"),
            PlaceType(rawValue: "bar"),
            PlaceType(rawValue: "tourist_attraction"),
            PlaceType(rawValue: "museum"),
            PlaceType(rawValue: "park"),
            PlaceType(rawValue: "store"),
        ]

        let request = SearchNearbyRequest(
            locationRestriction: restriction,
            placeProperties: placeProperties,
            includedTypes: includedTypes,
            maxResultCount: 20,
            rankPreference: .distance
        )

        switch await PlacesClient.shared.searchNearby(with: request) {
        case .success(let places):
            // For nearby results, fetch photo references in parallel
            return await withTaskGroup(of: NearbyPlace?.self, returning: [NearbyPlace].self) { group in
                for place in places {
                    group.addTask {
                        await self.mapPlaceToNearby(place)
                    }
                }
                var results: [NearbyPlace] = []
                for await result in group {
                    if let result { results.append(result) }
                }
                return results
            }
        case .failure(let placesError):
            self.error = mapSDKError(placesError)
            return []
        }
    }

    // MARK: - Photo URL (REST — kept for AsyncImage compatibility)

    /// Generates a URL to fetch a place photo via REST.
    /// Photos continue to use the REST endpoint so existing AsyncImage/DownsampledAsyncImage
    /// consumers work without changes.
    static func photoURL(for photoReference: String, maxWidth: Int = 400) -> URL? {
        var components = URLComponents(string: "\(GooglePlacesConfig.baseURL)/\(photoReference)/media")
        components?.queryItems = [
            URLQueryItem(name: "maxWidthPx", value: "\(maxWidth)"),
            URLQueryItem(name: "key", value: GooglePlacesConfig.apiKey),
        ]
        return components?.url
    }

    // MARK: - Photo (SDK direct)

    /// Loads the first photo for a place using the SDK.
    /// More reliable than the REST photo reference approach.
    func loadPlacePhoto(placeId: String, maxSize: CGSize = CGSize(width: 800, height: 600)) async -> UIImage? {
        let request = FetchPlaceRequest(
            placeID: placeId,
            placeProperties: [.photos]
        )

        guard case .success(let place) = await PlacesClient.shared.fetchPlace(with: request),
              let photo = place.photos?.first else {
            logger.debug("[Photos] No SDK photos for \(placeId)")
            return nil
        }

        let photoRequest = FetchPhotoRequest(photo: photo, maxSize: maxSize)
        switch await PlacesClient.shared.fetchPhoto(with: photoRequest) {
        case .success(let image):
            return image
        case .failure(let error):
            logger.error("[Photos] SDK fetchPhoto failed for \(placeId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private: REST Photo Reference Fetch

    /// Fetches only the photo resource name via REST API.
    /// The SDK's Photo struct doesn't expose the resource name needed for REST photo URLs,
    /// so we make a lightweight REST call with a narrow field mask to get it.
    private func fetchPhotoReference(placeId: String) async -> String? {
        // Check cache first to avoid a redundant REST call
        if let cached = cachedPhotoReferenceLookup?(placeId) {
            return cached
        }

        guard let url = URL(string: "\(GooglePlacesConfig.baseURL)/places/\(placeId)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(GooglePlacesConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("photos", forHTTPHeaderField: "X-Goog-FieldMask")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let photos = json["photos"] as? [[String: Any]],
                  let firstPhoto = photos.first,
                  let photoName = firstPhoto["name"] as? String else {
                let body = String(data: data.prefix(500), encoding: .utf8) ?? "nil"
                logger.debug("[Photos] No photo reference for \(placeId) (HTTP \(statusCode)): \(body)")
                return nil
            }
            return photoName
        } catch {
            logger.error("[Photos] fetchPhotoReference failed for \(placeId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private: SDK → DTO Mapping

    private func mapPlaceToDetails(_ place: GooglePlacesSwift.Place, photoReference: String?) -> PlaceDetails {
        // place.priceLevel is non-optional in the SDK; map it
        let priceLevel = mapPriceLevel(place.priceLevel)

        return PlaceDetails(
            placeId: place.placeID ?? "",
            name: place.displayName ?? "",
            formattedAddress: place.formattedAddress ?? "",
            latitude: place.location.latitude,
            longitude: place.location.longitude,
            types: place.types.map(\.rawValue),
            photoReference: photoReference,
            rating: place.rating.map(Double.init),
            userRatingCount: place.numberOfUserRatings,
            priceLevel: priceLevel,
            editorialSummary: place.editorialSummary
        )
    }

    private func mapPlaceToNearby(_ place: GooglePlacesSwift.Place) async -> NearbyPlace? {
        guard let placeId = place.placeID else { return nil }

        // Fetch photo reference via REST if the place has photos
        let photoReference: String?
        if let photos = place.photos, !photos.isEmpty {
            photoReference = await fetchPhotoReference(placeId: placeId)
        } else {
            photoReference = nil
        }

        return NearbyPlace(
            placeId: placeId,
            name: place.displayName ?? "",
            address: place.formattedAddress ?? "",
            latitude: place.location.latitude,
            longitude: place.location.longitude,
            types: place.types.map(\.rawValue),
            photoReference: photoReference
        )
    }

    private func mapPriceLevel(_ sdkLevel: GooglePlacesSwift.PriceLevel) -> PriceLevel? {
        switch sdkLevel {
        case .free: return .free
        case .inexpensive: return .inexpensive
        case .moderate: return .moderate
        case .expensive: return .expensive
        case .veryExpensive: return .veryExpensive
        @unknown default: return nil
        }
    }

    private func mapSDKError(_ placesError: GooglePlacesSwift.PlacesError) -> PlacesError {
        let description = placesError.localizedDescription
        if description.contains("network") || description.contains("offline") {
            return .offline
        }
        return .apiError(description)
    }
}
