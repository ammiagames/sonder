//
//  FeedService.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData
import Supabase

@MainActor
@Observable
final class FeedService {
    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client

    // Feed state
    var feedItems: [FeedItem] = []
    var isLoading = false
    var hasMore = true
    var newPostsAvailable = false

    // Pagination
    private var lastFetchedDate: Date?
    private let pageSize = 20

    // Realtime
    private var realtimeChannel: RealtimeChannelV2?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Feed Loading

    /// Load initial feed (logs from followed users)
    func loadFeed(for currentUserID: String) async {
        guard !isLoading else { return }

        isLoading = true
        hasMore = true
        lastFetchedDate = nil
        newPostsAvailable = false

        do {
            let items = try await fetchFeedPage(for: currentUserID, before: nil)
            feedItems = items
            lastFetchedDate = items.last?.createdAt
            hasMore = items.count >= pageSize
        } catch {
            print("Error loading feed: \(error)")
        }

        isLoading = false
    }

    /// Load more feed items (pagination)
    func loadMoreFeed(for currentUserID: String) async {
        guard !isLoading, hasMore, let cursor = lastFetchedDate else { return }

        isLoading = true

        do {
            let items = try await fetchFeedPage(for: currentUserID, before: cursor)
            feedItems.append(contentsOf: items)
            lastFetchedDate = items.last?.createdAt
            hasMore = items.count >= pageSize
        } catch {
            print("Error loading more feed: \(error)")
        }

        isLoading = false
    }

    /// Refresh feed (pull-to-refresh)
    func refreshFeed(for currentUserID: String) async {
        await loadFeed(for: currentUserID)
    }

    /// Fetch a page of feed items from Supabase
    private func fetchFeedPage(for currentUserID: String, before cursor: Date?) async throws -> [FeedItem] {
        // First get the list of users we're following
        let followingIDs = try await getFollowingIDs(for: currentUserID)

        guard !followingIDs.isEmpty else {
            return []
        }

        let selectQuery = """
            id,
            rating,
            photo_url,
            note,
            tags,
            created_at,
            users!logs_user_id_fkey(id, username, avatar_url, is_public),
            places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
        """

        // Build query - filters must come before order/limit
        let response: [FeedLogResponse]

        if let cursor = cursor {
            let cursorString = ISO8601DateFormatter().string(from: cursor)
            response = try await supabase
                .from("logs")
                .select(selectQuery)
                .in("user_id", values: followingIDs)
                .lt("created_at", value: cursorString)
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
        } else {
            response = try await supabase
                .from("logs")
                .select(selectQuery)
                .in("user_id", values: followingIDs)
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
        }

        return response.map { $0.toFeedItem() }
    }

    /// Get IDs of users the current user is following
    private func getFollowingIDs(for userID: String) async throws -> [String] {
        struct FollowingID: Codable {
            let following_id: String
        }

        let response: [FollowingID] = try await supabase
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userID)
            .execute()
            .value

        return response.map { $0.following_id }
    }

    // MARK: - Realtime Updates

    /// Subscribe to realtime updates for new logs from followed users
    func subscribeToRealtimeUpdates(for currentUserID: String) async {
        // Unsubscribe from existing channel
        await unsubscribeFromRealtimeUpdates()

        do {
            let followingIDs = try await getFollowingIDs(for: currentUserID)

            guard !followingIDs.isEmpty else { return }

            // Subscribe to INSERT events on logs table
            let channel = supabase.channel("feed-\(currentUserID)")

            let changes = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "logs"
            )

            await channel.subscribe()

            Task {
                for await change in changes {
                    // Check if the new log is from someone we follow
                    if let userID = change.record["user_id"]?.stringValue,
                       followingIDs.contains(userID) {
                        await MainActor.run {
                            self.newPostsAvailable = true
                        }
                    }
                }
            }

            realtimeChannel = channel
        } catch {
            print("Error subscribing to realtime: \(error)")
        }
    }

    /// Unsubscribe from realtime updates
    func unsubscribeFromRealtimeUpdates() async {
        if let channel = realtimeChannel {
            await supabase.removeChannel(channel)
            realtimeChannel = nil
        }
    }

    /// Show new posts (called when user taps "New posts available" banner)
    func showNewPosts(for currentUserID: String) async {
        newPostsAvailable = false
        await loadFeed(for: currentUserID)
    }

    // MARK: - Single Log Fetch

    /// Fetch a single log with its user and place data
    func fetchFeedItem(logID: String) async throws -> FeedItem? {
        let response: [FeedLogResponse] = try await supabase
            .from("logs")
            .select("""
                id,
                rating,
                photo_url,
                note,
                tags,
                created_at,
                users!logs_user_id_fkey(id, username, avatar_url, is_public),
                places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
            """)
            .eq("id", value: logID)
            .limit(1)
            .execute()
            .value

        return response.first?.toFeedItem()
    }

    // MARK: - User's Logs

    /// Fetch all logs for a specific user (for viewing their profile)
    func fetchUserLogs(userID: String) async throws -> [FeedItem] {
        let response: [FeedLogResponse] = try await supabase
            .from("logs")
            .select("""
                id,
                rating,
                photo_url,
                note,
                tags,
                created_at,
                users!logs_user_id_fkey(id, username, avatar_url, is_public),
                places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
            """)
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response.map { $0.toFeedItem() }
    }
}
