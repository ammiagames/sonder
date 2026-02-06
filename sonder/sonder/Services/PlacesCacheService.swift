//
//  PlacesCacheService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData

/// Service for caching places and managing recent searches
@Observable
@MainActor
final class PlacesCacheService {
    private let modelContext: ModelContext

    /// Triggers view updates when recent searches change
    private(set) var recentSearchesVersion = 0

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

        try? modelContext.save()
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
            modelContext.delete(search)
            try? modelContext.save()
            recentSearchesVersion += 1
        }
    }

    /// Clear all recent searches
    func clearAllRecentSearches() {
        let descriptor = FetchDescriptor<RecentSearch>()

        if let searches = try? modelContext.fetch(descriptor) {
            for search in searches {
                modelContext.delete(search)
            }
            try? modelContext.save()
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
                modelContext.delete(search)
            }
        }
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
            try? modelContext.save()
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
        try? modelContext.save()
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
                try? modelContext.save()
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
        try? modelContext.save()
        return place
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
