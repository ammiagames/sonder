//
//  SavedListsService.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import Foundation
import SwiftData
import Supabase
import os

@MainActor
@Observable
final class SavedListsService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "SavedListsService")
    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client

    /// In-memory cache of user's saved lists, sorted by sortOrder
    var lists: [SavedList] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch Lists

    /// Sync lists from Supabase and merge with local SwiftData
    func fetchLists(for userID: String) async {
        do {
            let remoteLists: [SavedList] = try await supabase
                .from("saved_lists")
                .select()
                .eq("user_id", value: userID)
                .order("sort_order", ascending: true)
                .execute()
                .value

            let localLists = getLocalLists(for: userID)
            let remoteIDs = Set(remoteLists.map(\.id))
            let localIDs = Set(localLists.map(\.id))

            // Import remote-only lists
            for list in remoteLists where !localIDs.contains(list.id) {
                modelContext.insert(list)
            }

            // Update local lists with remote data
            for list in remoteLists {
                if let local = localLists.first(where: { $0.id == list.id }) {
                    local.name = list.name
                    local.emoji = list.emoji
                    local.isDefault = list.isDefault
                    local.sortOrder = list.sortOrder
                    local.updatedAt = list.updatedAt
                }
            }

            // Push local-only lists to Supabase
            let localOnly = localLists.filter { !remoteIDs.contains($0.id) }
            for list in localOnly {
                _ = try? await supabase
                    .from("saved_lists")
                    .upsert(list)
                    .execute()
            }

            try modelContext.save()
            lists = getLocalLists(for: userID)
        } catch {
            logger.error("Error fetching saved lists: \(error.localizedDescription)")
            lists = getLocalLists(for: userID)
        }
    }

    // MARK: - CRUD

    /// Create a new saved list
    @discardableResult
    func createList(name: String, emoji: String = "\u{1F516}", userID: String) async -> SavedList? {
        let nextOrder = (lists.map(\.sortOrder).max() ?? -1) + 1
        let list = SavedList(
            userID: userID,
            name: name,
            emoji: emoji,
            isDefault: false,
            sortOrder: nextOrder
        )

        modelContext.insert(list)
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        lists = getLocalLists(for: userID)

        // Push to Supabase
        do {
            try await supabase
                .from("saved_lists")
                .upsert(list)
                .execute()
        } catch {
            logger.warning("Saved list remote create deferred: \(error.localizedDescription)")
        }

        return list
    }

    /// Delete a list and all its associated WantToGo items
    func deleteList(_ list: SavedList, userID: String) async {
        let listID = list.id

        // Delete associated WantToGo items locally
        let listIDCopy = listID
        let userIDCopy = userID
        let wtgDescriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { $0.listID == listIDCopy && $0.userID == userIDCopy }
        )
        if let wtgItems = try? modelContext.fetch(wtgDescriptor) {
            for item in wtgItems {
                modelContext.delete(item)
            }
        }

        // Delete the list locally
        modelContext.delete(list)
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        lists = getLocalLists(for: userID)

        // Delete from Supabase (cascade will handle want_to_go rows)
        do {
            try await supabase
                .from("saved_lists")
                .delete()
                .eq("id", value: listID)
                .execute()
        } catch {
            logger.warning("Saved list remote delete deferred: \(error.localizedDescription)")
        }
    }

    /// Rename a list
    func renameList(_ list: SavedList, newName: String) async {
        list.name = newName
        list.updatedAt = Date()
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }

        struct RenameUpdate: Encodable {
            let name: String
            let updated_at: Date
        }
        do {
            try await supabase
                .from("saved_lists")
                .update(RenameUpdate(name: newName, updated_at: list.updatedAt))
                .eq("id", value: list.id)
                .execute()
        } catch {
            logger.warning("Saved list remote rename deferred: \(error.localizedDescription)")
        }
    }

    /// Update a list's emoji
    func updateEmoji(_ list: SavedList, emoji: String) async {
        list.emoji = emoji
        list.updatedAt = Date()
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }

        struct EmojiUpdate: Encodable {
            let emoji: String
            let updated_at: Date
        }
        do {
            try await supabase
                .from("saved_lists")
                .update(EmojiUpdate(emoji: emoji, updated_at: list.updatedAt))
                .eq("id", value: list.id)
                .execute()
        } catch {
            logger.warning("Saved list remote emoji update deferred: \(error.localizedDescription)")
        }
    }

    /// Reorder lists
    func reorderLists(_ orderedLists: [SavedList], userID: String) async {
        for (index, list) in orderedLists.enumerated() {
            list.sortOrder = index
            list.updatedAt = Date()
        }
        do { try modelContext.save() } catch { logger.error("SwiftData save failed: \(error.localizedDescription)") }
        lists = getLocalLists(for: userID)

        // Push new order to Supabase
        struct ReorderUpdate: Encodable {
            let sort_order: Int
            let updated_at: Date
        }
        for list in orderedLists {
            _ = try? await supabase
                .from("saved_lists")
                .update(ReorderUpdate(sort_order: list.sortOrder, updated_at: list.updatedAt))
                .eq("id", value: list.id)
                .execute()
        }
    }

    // MARK: - Helpers

    /// Get place count for a specific list
    func placeCount(for listID: String, userID: String) -> Int {
        let listIDCopy = listID
        let userIDCopy = userID
        let descriptor = FetchDescriptor<WantToGo>(
            predicate: #Predicate { $0.listID == listIDCopy && $0.userID == userIDCopy }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Fetch local lists sorted by sortOrder (excludes auto-created default lists)
    func getLocalLists(for userID: String) -> [SavedList] {
        let userIDCopy = userID
        let descriptor = FetchDescriptor<SavedList>(
            predicate: #Predicate { $0.userID == userIDCopy && $0.isDefault == false },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
