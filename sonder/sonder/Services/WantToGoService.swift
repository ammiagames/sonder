//
//  WantToGoService.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData
import Supabase
import CoreLocation

@MainActor
@Observable
final class WantToGoService {
    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client

    // Cached want-to-go items
    var items: [WantToGo] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Pending Deletion Tracking (persisted via UserDefaults)

    private static let pendingDeletionsKey = "wtg_pending_deletion_place_ids"

    /// Place IDs removed locally but not yet confirmed deleted on Supabase.
    /// Persisted so they survive app kill and are retried on next sync.
    private var pendingDeletionPlaceIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.pendingDeletionsKey) ?? [])
    }

    private func addPendingDeletion(_ placeID: String) {
        var ids = pendingDeletionPlaceIDs
        ids.insert(placeID)
        UserDefaults.standard.set(Array(ids), forKey: Self.pendingDeletionsKey)
    }

    private func removePendingDeletion(_ placeID: String) {
        var ids = pendingDeletionPlaceIDs
        ids.remove(placeID)
        UserDefaults.standard.set(Array(ids), forKey: Self.pendingDeletionsKey)
    }

    private func clearPendingDeletions() {
        UserDefaults.standard.removeObject(forKey: Self.pendingDeletionsKey)
    }

    // MARK: - Add/Remove (local-first)

    /// Add a place to Want to Go list.
    /// Writes to SwiftData immediately, then pushes to Supabase.
    /// Data survives app kill; unsynced adds are pushed on next sync.
    func addToWantToGo(placeID: String, userID: String, placeName: String? = nil, placeAddress: String? = nil, photoReference: String? = nil, sourceLogID: String? = nil) async throws {
        // Check if already saved
        guard !isInWantToGo(placeID: placeID, userID: userID) else { return }

        let item = WantToGo(
            userID: userID,
            placeID: placeID,
            placeName: placeName,
            placeAddress: placeAddress,
            photoReference: photoReference,
            sourceLogID: sourceLogID
        )

        // Cancel any pending remote deletion for this place
        removePendingDeletion(placeID)

        // Local first — data survives app kill
        modelContext.insert(item)
        try modelContext.save()
        items = getWantToGoList(for: userID)

        // Then push to Supabase (failure is non-fatal; retried on next sync)
        do {
            try await supabase
                .from("want_to_go")
                .upsert(item)
                .execute()
        } catch {
            print("WTG remote add deferred: \(error)")
        }
    }

    /// Remove a place from Want to Go list.
    /// Deletes from SwiftData immediately, then deletes from Supabase.
    /// Pending deletion is persisted so it survives app kill.
    func removeFromWantToGo(placeID: String, userID: String) async throws {
        // Local first — immediate UI update
        removeLocalBookmark(placeID: placeID, userID: userID)

        // Track for remote deletion (persisted across app restarts)
        addPendingDeletion(placeID)

        // Then delete from Supabase (failure is non-fatal; retried on next sync)
        do {
            try await supabase
                .from("want_to_go")
                .delete()
                .eq("user_id", value: userID)
                .eq("place_id", value: placeID)
                .execute()
            removePendingDeletion(placeID)
        } catch {
            print("WTG remote delete deferred: \(error)")
        }
    }

    /// Toggle want-to-go status for a place
    func toggleWantToGo(placeID: String, userID: String, placeName: String? = nil, placeAddress: String? = nil, photoReference: String? = nil, sourceLogID: String? = nil) async throws {
        if isInWantToGo(placeID: placeID, userID: userID) {
            try await removeFromWantToGo(placeID: placeID, userID: userID)
        } else {
            try await addToWantToGo(placeID: placeID, userID: userID, placeName: placeName, placeAddress: placeAddress, photoReference: photoReference, sourceLogID: sourceLogID)
        }
    }

    // MARK: - Check Status

    /// Check if a place is in the user's Want to Go list (uses cached items for reactivity)
    func isInWantToGo(placeID: String, userID: String) -> Bool {
        // Use cached items array so SwiftUI can observe changes
        // If items is empty, fall back to database check (initial load)
        if items.isEmpty {
            let userIDCopy = userID
            let placeIDCopy = placeID
            let descriptor = FetchDescriptor<WantToGo>(
                predicate: #Predicate { item in
                    item.userID == userIDCopy && item.placeID == placeIDCopy
                }
            )
            return (try? modelContext.fetch(descriptor).first) != nil
        }
        return items.contains { $0.placeID == placeID && $0.userID == userID }
    }

    // MARK: - Fetch List

    /// Get the user's Want to Go list
    func getWantToGoList(for userID: String) -> [WantToGo] {
        let userIDCopy = userID
        let descriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { item in
                item.userID == userIDCopy
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Refresh the cached items list
    private func refreshItems(for userID: String) async {
        items = getWantToGoList(for: userID)
    }

    // MARK: - Auto-remove on Log

    /// Removes a bookmark for a place that was just logged.
    /// Deletes locally first (always succeeds), then best-effort deletes from Supabase.
    func removeBookmarkIfLoggedPlace(placeID: String, userID: String) async {
        guard isInWantToGo(placeID: placeID, userID: userID) else { return }

        // Remove from local SwiftData
        removeLocalBookmark(placeID: placeID, userID: userID)

        // Track for retry in case remote delete fails
        addPendingDeletion(placeID)

        // Best-effort remote delete (don't block or fail the log flow)
        do {
            try await supabase
                .from("want_to_go")
                .delete()
                .eq("user_id", value: userID)
                .eq("place_id", value: placeID)
                .execute()
            removePendingDeletion(placeID)
        } catch {
            print("WTG auto-remove remote delete deferred: \(error)")
        }
    }

    /// Removes a bookmark from the local SwiftData store and updates the cached items array.
    func removeLocalBookmark(placeID: String, userID: String) {
        let userIDCopy = userID
        let placeIDCopy = placeID
        let descriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { item in
                item.userID == userIDCopy && item.placeID == placeIDCopy
            }
        )

        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try? modelContext.save()
        }

        items.removeAll { $0.placeID == placeID && $0.userID == userID }
    }

    // MARK: - Sync

    /// Sync Want to Go list with Supabase.
    /// Pushes local-only items first (handles adds that survived an app kill),
    /// retries pending deletions, then imports remote-only items.
    func syncWantToGo(for userID: String) async {
        do {
            // 1. Fetch remote state
            let remoteItems: [WantToGo] = try await supabase
                .from("want_to_go")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            let localItems = getWantToGoList(for: userID)
            let remotePlaceIDs = Set(remoteItems.map(\.placeID))
            let localPlaceIDs = Set(localItems.map(\.placeID))

            // 2. Push local-only items to Supabase (added offline or before app kill)
            let localOnly = localItems.filter {
                !remotePlaceIDs.contains($0.placeID) && !pendingDeletionPlaceIDs.contains($0.placeID)
            }
            for item in localOnly {
                try? await supabase
                    .from("want_to_go")
                    .upsert(item)
                    .execute()
            }

            // 3. Retry pending remote deletions
            for placeID in pendingDeletionPlaceIDs {
                try? await supabase
                    .from("want_to_go")
                    .delete()
                    .eq("user_id", value: userID)
                    .eq("place_id", value: placeID)
                    .execute()
            }
            let deletedPlaceIDs = pendingDeletionPlaceIDs
            clearPendingDeletions()

            // 4. Import remote-only items locally (except those pending deletion)
            for item in remoteItems where !localPlaceIDs.contains(item.placeID) && !deletedPlaceIDs.contains(item.placeID) {
                modelContext.insert(item)
            }

            try modelContext.save()
            items = getWantToGoList(for: userID)
        } catch {
            print("Error syncing want to go: \(error)")
            // Offline: use whatever is in local SwiftData
            items = getWantToGoList(for: userID)
        }
    }
}

// MARK: - WantToGo with Place Details

/// A want-to-go item with its associated place details
struct WantToGoWithPlace: Identifiable {
    let id: String
    let wantToGo: WantToGo
    let place: FeedItem.FeedPlace
    let sourceUser: FeedItem.FeedUser?

    /// Convenience accessor for creation date
    var createdAt: Date {
        wantToGo.createdAt
    }

    init(wantToGo: WantToGo, place: FeedItem.FeedPlace, sourceUser: FeedItem.FeedUser? = nil) {
        self.id = wantToGo.id
        self.wantToGo = wantToGo
        self.place = place
        self.sourceUser = sourceUser
    }
}

// MARK: - Extended Service Methods

extension WantToGoService {
    /// Fetch want-to-go list with place details from Supabase
    func fetchWantToGoWithPlaces(for userID: String) async throws -> [WantToGoWithPlace] {
        struct WantToGoResponse: Codable {
            let id: String
            let user_id: String
            let place_id: String
            let place_name: String?
            let place_address: String?
            let photo_reference: String?
            let source_log_id: String?
            let created_at: Date
            let source_log: SourceLog?

            struct SourceLog: Codable {
                let users: FeedItem.FeedUser
            }
        }

        let response: [WantToGoResponse] = try await supabase
            .from("want_to_go")
            .select("""
                id,
                user_id,
                place_id,
                place_name,
                place_address,
                photo_reference,
                source_log_id,
                created_at,
                source_log:logs!want_to_go_source_log_id_fkey(users!logs_user_id_fkey(id, username, avatar_url, is_public))
            """)
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response.map { item in
            let wantToGo = WantToGo(
                id: item.id,
                userID: item.user_id,
                placeID: item.place_id,
                placeName: item.place_name,
                placeAddress: item.place_address,
                photoReference: item.photo_reference,
                sourceLogID: item.source_log_id,
                createdAt: item.created_at
            )
            // Create a simple FeedPlace from stored data
            let place = FeedItem.FeedPlace(
                id: item.place_id,
                name: item.place_name ?? "Unknown Place",
                address: item.place_address ?? "",
                latitude: 0,
                longitude: 0,
                photoReference: item.photo_reference
            )
            return WantToGoWithPlace(
                wantToGo: wantToGo,
                place: place,
                sourceUser: item.source_log?.users
            )
        }
    }

    /// Fetch want-to-go items with coordinates for map display.
    /// Joins want_to_go with places table to get lat/lng, falling back to local Place cache.
    func fetchWantToGoForMap(for userID: String) async throws -> [WantToGoMapItem] {
        struct WantToGoPlaceResponse: Codable {
            let id: String
            let place_id: String
            let place_name: String?
            let place_address: String?
            let photo_reference: String?
            let place: PlaceCoord?

            struct PlaceCoord: Codable {
                let lat: Double
                let lng: Double
            }
        }

        // Try joining to places table for coordinates
        // Use left join (no !) in case FK doesn't exist on all rows
        do {
            let response: [WantToGoPlaceResponse] = try await supabase
                .from("want_to_go")
                .select("""
                    id,
                    place_id,
                    place_name,
                    place_address,
                    photo_reference,
                    place:places(lat, lng)
                """)
                .eq("user_id", value: userID)
                .execute()
                .value

            var results: [WantToGoMapItem] = []
            var missingPlaceIDs: Set<String> = []

            for item in response {
                if let place = item.place, place.lat != 0, place.lng != 0 {
                    results.append(WantToGoMapItem(
                        id: item.id,
                        placeID: item.place_id,
                        placeName: item.place_name ?? "Saved Place",
                        placeAddress: item.place_address,
                        photoReference: item.photo_reference,
                        coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
                    ))
                } else {
                    missingPlaceIDs.insert(item.place_id)
                }
            }

            // Fall back to local SwiftData Place cache for items without coordinates
            var stillMissing: Set<String> = []
            for placeID in missingPlaceIDs {
                let placeIDCopy = placeID
                let descriptor = FetchDescriptor<Place>(
                    predicate: #Predicate { $0.id == placeIDCopy }
                )
                if let cachedPlace = try? modelContext.fetch(descriptor).first {
                    let item = response.first { $0.place_id == placeID }
                    results.append(WantToGoMapItem(
                        id: item?.id ?? UUID().uuidString,
                        placeID: placeID,
                        placeName: item?.place_name ?? cachedPlace.name,
                        placeAddress: item?.place_address ?? cachedPlace.address,
                        photoReference: item?.photo_reference ?? cachedPlace.photoReference,
                        coordinate: cachedPlace.coordinate
                    ))
                } else {
                    stillMissing.insert(placeID)
                }
            }

            // Fetch remaining missing places directly from Supabase
            if !stillMissing.isEmpty {
                let remotePlaces: [Place] = try await supabase
                    .from("places")
                    .select()
                    .in("id", values: Array(stillMissing))
                    .execute()
                    .value

                for place in remotePlaces {
                    let item = response.first { $0.place_id == place.id }
                    results.append(WantToGoMapItem(
                        id: item?.id ?? UUID().uuidString,
                        placeID: place.id,
                        placeName: item?.place_name ?? place.name,
                        placeAddress: item?.place_address ?? place.address,
                        photoReference: item?.photo_reference ?? place.photoReference,
                        coordinate: place.coordinate
                    ))
                    // Cache locally for future use
                    modelContext.insert(place)
                }
                try? modelContext.save()
            }

            return results
        } catch {
            // If the join fails entirely (no FK), fall back to local cache only
            return try fallbackFetchWantToGoForMap(for: userID)
        }
    }

    /// Fallback: fetch want-to-go items and resolve coordinates from local Place cache only
    private func fallbackFetchWantToGoForMap(for userID: String) throws -> [WantToGoMapItem] {
        let userIDCopy = userID
        let descriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { $0.userID == userIDCopy }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []

        return items.compactMap { item in
            let placeIDCopy = item.placeID
            let placeDescriptor = FetchDescriptor<Place>(
                predicate: #Predicate { $0.id == placeIDCopy }
            )
            guard let place = try? modelContext.fetch(placeDescriptor).first else { return nil }
            return WantToGoMapItem(
                id: item.id,
                placeID: item.placeID,
                placeName: item.placeName ?? place.name,
                placeAddress: item.placeAddress ?? place.address,
                photoReference: item.photoReference ?? place.photoReference,
                coordinate: place.coordinate
            )
        }
    }
}
