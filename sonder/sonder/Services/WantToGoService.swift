//
//  WantToGoService.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData
import Supabase

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

    // MARK: - Add/Remove

    /// Add a place to Want to Go list
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

        // Sync to Supabase
        try await supabase
            .from("want_to_go")
            .upsert(item)
            .execute()

        // Save locally only after Supabase succeeds
        modelContext.insert(item)
        try modelContext.save()

        // Refresh local list
        await refreshItems(for: userID)
    }

    /// Remove a place from Want to Go list
    func removeFromWantToGo(placeID: String, userID: String) async throws {
        // Delete from Supabase
        try await supabase
            .from("want_to_go")
            .delete()
            .eq("user_id", value: userID)
            .eq("place_id", value: placeID)
            .execute()

        // Remove locally
        let userIDCopy = userID
        let placeIDCopy = placeID
        let descriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { item in
                item.userID == userIDCopy && item.placeID == placeIDCopy
            }
        )

        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try modelContext.save()
        }

        // Refresh local list
        await refreshItems(for: userID)
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

    /// Check if a place is in the user's Want to Go list (local check)
    func isInWantToGo(placeID: String, userID: String) -> Bool {
        let userIDCopy = userID
        let placeIDCopy = placeID
        let descriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { item in
                item.userID == userIDCopy && item.placeID == placeIDCopy
            }
        )

        return (try? modelContext.fetch(descriptor).first) != nil
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

    // MARK: - Sync

    /// Sync Want to Go list from Supabase to local cache
    func syncWantToGo(for userID: String) async {
        do {
            // Fetch from Supabase
            let remoteItems: [WantToGo] = try await supabase
                .from("want_to_go")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            // Clear existing local cache for this user
            let userIDCopy = userID
            let descriptor = FetchDescriptor<WantToGo>(
                predicate: #Predicate { item in
                    item.userID == userIDCopy
                }
            )

            let existing = try modelContext.fetch(descriptor)
            for item in existing {
                modelContext.delete(item)
            }

            // Insert fresh data
            for item in remoteItems {
                modelContext.insert(item)
            }

            try modelContext.save()

            // Update cached list
            items = remoteItems
        } catch {
            print("Error syncing want to go: \(error)")
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
}
