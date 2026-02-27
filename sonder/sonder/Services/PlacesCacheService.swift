//
//  PlacesCacheService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData
import CoreLocation
import UIKit
import os

/// Service for caching places and managing recent searches
@Observable
@MainActor
final class PlacesCacheService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "PlacesCacheService")
    private let modelContext: ModelContext

    /// Triggers view updates when recent searches change
    private(set) var recentSearchesVersion = 0

    // MARK: - In-Memory Nearby Cache

    private var cachedNearbyResults: [NearbyPlace] = []
    private var cachedNearbyLocation: CLLocationCoordinate2D?
    private var cachedNearbyTimestamp: Date?

    /// Max age for nearby cache (5 minutes)
    private static let nearbyCacheMaxAge: TimeInterval = 5 * 60
    /// Max distance drift before invalidating nearby cache (300 meters)
    private static let nearbyCacheMaxDistance: CLLocationDistance = 300

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Recent Searches

    /// Add a place to recent searches
    func addRecentSearch(placeId: String, name: String, address: String) {
        // Check if already exists and update timestamp
        let descriptor = FetchDescriptor<RecentSearch>(
            predicate: #Predicate { $0.placeId == placeId }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.searchedAt = Date()
        } else {
            let recentSearch = RecentSearch(placeId: placeId, name: name, address: address)
            modelContext.insert(recentSearch)
        }

        // Enforce max limit
        trimRecentSearches()

        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        recentSearchesVersion += 1
    }

    /// Get recent searches sorted by most recent
    func getRecentSearches() -> [RecentSearch] {
        let descriptor = FetchDescriptor<RecentSearch>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Clear a specific recent search
    func clearRecentSearch(placeId: String) {
        let descriptor = FetchDescriptor<RecentSearch>(
            predicate: #Predicate { $0.placeId == placeId }
        )

        if let search = try? modelContext.fetch(descriptor).first {
            removeCachedPhoto(for: search.placeId)
            modelContext.delete(search)
            do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
            recentSearchesVersion += 1
        }
    }

    /// Clear all recent searches
    func clearAllRecentSearches() {
        let descriptor = FetchDescriptor<RecentSearch>()

        if let searches = try? modelContext.fetch(descriptor) {
            for search in searches {
                removeCachedPhoto(for: search.placeId)
                modelContext.delete(search)
            }
            do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        }
    }

    /// Trim recent searches to max limit
    private func trimRecentSearches() {
        let descriptor = FetchDescriptor<RecentSearch>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )

        guard let searches = try? modelContext.fetch(descriptor) else { return }

        let maxSearches = GooglePlacesConfig.maxRecentSearches
        if searches.count > maxSearches {
            for search in searches.dropFirst(maxSearches) {
                removeCachedPhoto(for: search.placeId)
                modelContext.delete(search)
            }
        }
    }

    // MARK: - Photo File Cache

    /// Directory for cached place photos.
    private static let photoCacheDir: URL = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("place-photos", isDirectory: true)
        }
        let dir = caches.appendingPathComponent("place-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Saves a photo to the file cache for a given place ID.
    func cachePhoto(_ image: UIImage, for placeId: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let fileURL = Self.photoCacheDir.appendingPathComponent("\(placeId).jpg")
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Loads a cached photo from disk for a given place ID.
    func getCachedPhoto(for placeId: String) -> UIImage? {
        let fileURL = Self.photoCacheDir.appendingPathComponent("\(placeId).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// Removes a cached photo for a given place ID.
    private func removeCachedPhoto(for placeId: String) {
        let fileURL = Self.photoCacheDir.appendingPathComponent("\(placeId).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Nearby Cache

    /// Returns cached nearby results if they are less than 5 minutes old and the user
    /// hasn't moved more than 300 meters from where the results were fetched.
    func getCachedNearby(for location: CLLocationCoordinate2D) -> [NearbyPlace]? {
        guard let cachedLocation = cachedNearbyLocation,
              let cachedTimestamp = cachedNearbyTimestamp,
              !cachedNearbyResults.isEmpty else {
            return nil
        }

        // Check age
        guard Date().timeIntervalSince(cachedTimestamp) < Self.nearbyCacheMaxAge else {
            return nil
        }

        // Check distance
        let cached = CLLocation(latitude: cachedLocation.latitude, longitude: cachedLocation.longitude)
        let current = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard cached.distance(from: current) < Self.nearbyCacheMaxDistance else {
            return nil
        }

        return cachedNearbyResults
    }

    /// Stores nearby search results for the given location.
    func cacheNearbyResults(_ results: [NearbyPlace], location: CLLocationCoordinate2D) {
        cachedNearbyResults = results
        cachedNearbyLocation = location
        cachedNearbyTimestamp = Date()
    }

    // MARK: - Place Cache

    /// Cache a place from Google Places API response
    func cachePlace(from details: PlaceDetails) -> Place {
        // Check if place already exists
        let placeId = details.placeId
        let descriptor = FetchDescriptor<Place>(
            predicate: #Predicate { $0.id == placeId }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            // Update existing place
            existing.name = details.name
            existing.address = details.formattedAddress
            existing.latitude = details.latitude
            existing.longitude = details.longitude
            existing.types = details.types
            existing.photoReference = details.photoReference
            do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
            return existing
        }

        // Create new place
        let place = Place(
            id: details.placeId,
            name: details.name,
            address: details.formattedAddress,
            latitude: details.latitude,
            longitude: details.longitude,
            types: details.types,
            photoReference: details.photoReference
        )

        modelContext.insert(place)
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        return place
    }

    /// Cache a place from nearby search result
    func cachePlace(from nearby: NearbyPlace) -> Place {
        // Check if place already exists
        let placeId = nearby.placeId
        let descriptor = FetchDescriptor<Place>(
            predicate: #Predicate { $0.id == placeId }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            // Update photo if we have a new one
            if existing.photoReference == nil, let photoRef = nearby.photoReference {
                existing.photoReference = photoRef
                do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
            }
            return existing
        }

        // Create new place
        let place = Place(
            id: nearby.placeId,
            name: nearby.name,
            address: nearby.address,
            latitude: nearby.latitude,
            longitude: nearby.longitude,
            types: nearby.types,
            photoReference: nearby.photoReference
        )

        modelContext.insert(place)
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        return place
    }

    /// Backfill missing photo references for cached places.
    /// Fetches details from Google Places API for up to `limit` places that have nil photoReference.
    func backfillMissingPhotoReferences(using placesService: GooglePlacesService, limit: Int = 10) async {
        let descriptor = FetchDescriptor<Place>()
        guard let allPlaces = try? modelContext.fetch(descriptor) else { return }

        let missing = Array(allPlaces.filter { $0.photoReference == nil }.prefix(limit))
        guard !missing.isEmpty else { return }

        // Fetch place details sequentially — GooglePlacesService is @MainActor-isolated,
        // so concurrent child tasks cause EXC_BAD_ACCESS.
        for place in missing {
            let details = await placesService.getPlaceDetails(placeId: place.id)
            if let photoRef = details?.photoReference {
                place.photoReference = photoRef
            }
        }

        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
    }

    /// Get a cached place by ID
    func getPlace(by id: String) -> Place? {
        let descriptor = FetchDescriptor<Place>(
            predicate: #Predicate { $0.id == id }
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Search cached places offline
    func searchCachedPlaces(query: String) -> [Place] {
        let lowercaseQuery = query.lowercased()
        let descriptor = FetchDescriptor<Place>()

        guard let places = try? modelContext.fetch(descriptor) else { return [] }

        return places.filter { place in
            place.name.lowercased().contains(lowercaseQuery) ||
            place.address.lowercased().contains(lowercaseQuery)
        }
    }
}
