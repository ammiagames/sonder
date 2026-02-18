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
    var feedEntries: [FeedEntry] = []
    var isLoading = false
    var hasLoadedOnce = false
    var hasMore = true
    var newPostsAvailable = false

    // Pagination
    private var lastFetchedDate: Date?
    private let pageSize = 25
    private let maxItemsInMemory = 100

    // Realtime
    private var realtimeChannel: RealtimeChannelV2?

    // Cached following IDs to avoid repeated network calls
    private var cachedFollowingIDs: [String]?
    private var followingIDsCacheTime: Date?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Feed Loading

    /// Load initial feed (trips + standalone logs from followed users)
    func loadFeed(for currentUserID: String) async {
        guard !isLoading else { return }

        isLoading = true
        hasMore = true
        lastFetchedDate = nil
        newPostsAvailable = false

        do {
            let followingIDs = try await getFollowingIDs(for: currentUserID)
            guard !followingIDs.isEmpty else {
                feedEntries = []
                isLoading = false
                hasLoadedOnce = true
                return
            }

            // Fetch logs (required)
            let logResponses = try await fetchFeedLogs(followingIDs: followingIDs, before: nil)

            // Fetch trips (non-fatal — feed still works without trip cards)
            let trips: [FeedTripItem]
            do {
                trips = try await fetchTripFeedItems(followingIDs: followingIDs)
            } catch {
                print("Error loading trip feed items (non-fatal): \(error)")
                trips = []
            }

            // IDs of logs that belong to a trip (shown in trip cards, not individually)
            let tripLogIDs = Set(trips.flatMap { $0.logs.map { $0.id } })

            // Standalone logs = those not in any trip card
            let standaloneLogs = logResponses
                .filter { $0.tripID == nil || !tripLogIDs.contains($0.id) }
                .map { FeedEntry.log($0.toFeedItem()) }

            let tripFeedEntries = trips.map { FeedEntry.trip($0) }

            // Trip IDs that already appear as full trip cards (have logs)
            let tripIDsWithLogs = Set(trips.map { $0.id })

            // Fetch trip-created entries for trips with no logs (non-fatal)
            let tripCreatedEntries: [FeedEntry]
            do {
                let tripCreated = try await fetchTripCreatedEntries(
                    followingIDs: followingIDs,
                    excludeTripIDs: tripIDsWithLogs
                )
                tripCreatedEntries = tripCreated.map { FeedEntry.tripCreated($0) }
            } catch {
                print("Error loading trip created entries (non-fatal): \(error)")
                tripCreatedEntries = []
            }

            var merged = standaloneLogs + tripFeedEntries + tripCreatedEntries
            merged.sort { $0.sortDate > $1.sortDate }

            feedEntries = merged
            lastFetchedDate = logResponses.last?.createdAt
            hasMore = logResponses.count >= pageSize
        } catch {
            print("Error loading feed: \(error)")
        }

        isLoading = false
        hasLoadedOnce = true
    }

    /// Load more feed items (pagination — standalone logs only, trips already fully loaded)
    func loadMoreFeed(for currentUserID: String) async {
        guard !isLoading, hasMore, let cursor = lastFetchedDate else { return }

        isLoading = true

        do {
            let followingIDs = try await getFollowingIDs(for: currentUserID)
            let logResponses = try await fetchFeedLogs(followingIDs: followingIDs, before: cursor)

            // Filter out logs that belong to trips (already shown in trip cards)
            let existingTripLogIDs = feedEntries.compactMap { entry -> [String]? in
                if case .trip(let t) = entry { return t.logs.map { $0.id } }
                return nil
            }.flatMap { $0 }
            let tripLogIDs = Set(existingTripLogIDs)

            let newEntries = logResponses
                .filter { $0.tripID == nil || !tripLogIDs.contains($0.id) }
                .map { FeedEntry.log($0.toFeedItem()) }

            feedEntries.append(contentsOf: newEntries)

            // Sliding window
            if feedEntries.count > maxItemsInMemory {
                feedEntries.removeFirst(feedEntries.count - maxItemsInMemory)
            }

            lastFetchedDate = logResponses.last?.createdAt
            hasMore = logResponses.count >= pageSize
        } catch {
            print("Error loading more feed: \(error)")
        }

        isLoading = false
    }

    /// Refresh feed (pull-to-refresh)
    func refreshFeed(for currentUserID: String) async {
        cachedFollowingIDs = nil
        followingIDsCacheTime = nil
        await loadFeed(for: currentUserID)
    }

    // MARK: - Feed Logs (all logs, filtered client-side)

    private let selectQuery = """
        id,
        rating,
        photo_urls,
        note,
        tags,
        created_at,
        trip_id,
        users!logs_user_id_fkey(id, username, avatar_url, is_public),
        places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference, types)
    """

    private func fetchFeedLogs(followingIDs: [String], before cursor: Date?) async throws -> [FeedLogResponse] {
        if let cursor = cursor {
            let cursorString = ISO8601DateFormatter().string(from: cursor)
            return try await supabase
                .from("logs")
                .select(selectQuery)
                .in("user_id", values: followingIDs)
                .lt("created_at", value: cursorString)
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
        } else {
            return try await supabase
                .from("logs")
                .select(selectQuery)
                .in("user_id", values: followingIDs)
                .order("created_at", ascending: false)
                .limit(pageSize)
                .execute()
                .value
        }
    }

    // MARK: - Trip Feed Items

    private func fetchTripFeedItems(followingIDs: [String]) async throws -> [FeedTripItem] {
        // Fetch trips from followed users
        let trips: [FeedTripResponse] = try await supabase
            .from("trips")
            .select("""
                id, name, cover_photo_url, start_date, end_date, created_by,
                users!trips_created_by_fkey(id, username, avatar_url, is_public)
            """)
            .in("created_by", values: followingIDs)
            .order("updated_at", ascending: false)
            .limit(50)
            .execute()
            .value

        guard !trips.isEmpty else { return [] }

        let tripIDs = trips.map { $0.id }

        // Fetch logs for these trips
        let tripLogs: [TripLogWithTripID] = try await supabase
            .from("logs")
            .select("""
                id, rating, photo_urls, created_at, trip_id,
                places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference, types)
            """)
            .in("trip_id", values: tripIDs)
            .order("created_at", ascending: false)
            .limit(500)
            .execute()
            .value

        // Fetch activities for these trips (non-fatal)
        let activities: [TripActivityResponse]
        do {
            activities = try await supabase
                .from("trip_activity")
                .select("id, trip_id, activity_type, log_id, place_name, created_at")
                .in("trip_id", values: tripIDs)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
        } catch {
            print("Error fetching trip activities (non-fatal): \(error)")
            activities = []
        }

        // Latest activity per trip for subtitle
        let latestActivityByTrip = Dictionary(grouping: activities) { $0.tripID }
            .compactMapValues { $0.first }

        // Group logs by trip_id
        let logsByTrip = Dictionary(grouping: tripLogs) { $0.tripID }

        // Build FeedTripItems
        return trips.compactMap { trip in
            let logs = logsByTrip[trip.id] ?? []
            // Skip trips with no logs
            guard !logs.isEmpty else { return nil }

            let summaries = logs.map { log in
                FeedTripItem.LogSummary(
                    id: log.id,
                    photoURLs: log.photoURLs,
                    rating: log.rating,
                    placeName: log.place.name,
                    placePhotoReference: log.place.photoReference,
                    createdAt: log.createdAt
                )
            }

            let latestActivity = logs.first?.createdAt ?? Date.distantPast

            // Compute activity subtitle from latest activity
            let subtitle: String
            if let activity = latestActivityByTrip[trip.id] {
                subtitle = Self.activitySubtitle(for: activity)
            } else {
                subtitle = "trip"
            }

            return FeedTripItem(
                id: trip.id,
                name: trip.name,
                coverPhotoURL: trip.coverPhotoURL,
                startDate: trip.startDate,
                endDate: trip.endDate,
                user: trip.user,
                logs: summaries,
                latestActivityAt: latestActivity,
                activitySubtitle: subtitle
            )
        }
    }

    /// Compute a human-readable subtitle from a trip activity
    nonisolated static func activitySubtitle(for activity: TripActivityResponse) -> String {
        switch activity.activityType {
        case "log_added":
            if let name = activity.placeName, !name.isEmpty {
                return "added \(name)"
            }
            return "added a new stop"
        case "trip_created":
            return "started this trip"
        default:
            return "trip"
        }
    }

    // MARK: - Trip Created Entries (no-log trips)

    private func fetchTripCreatedEntries(
        followingIDs: [String],
        excludeTripIDs: Set<String>
    ) async throws -> [FeedTripCreatedItem] {
        let responses: [TripCreatedActivityResponse] = try await supabase
            .from("trip_activity")
            .select("""
                id, trip_id, activity_type, created_at,
                trips!trip_activity_trip_id_fkey(id, name, cover_photo_url),
                users!trip_activity_user_id_fkey(id, username, avatar_url, is_public)
            """)
            .in("user_id", values: followingIDs)
            .eq("activity_type", value: "trip_created")
            .order("created_at", ascending: false)
            .limit(20)
            .execute()
            .value

        return responses
            .filter { !excludeTripIDs.contains($0.tripID) }
            .map { $0.toFeedTripCreatedItem() }
    }

    /// Get IDs of users the current user is following (cached for 60s)
    private func getFollowingIDs(for userID: String) async throws -> [String] {
        // Return cached value if fresh (< 60 seconds old)
        if let cached = cachedFollowingIDs,
           let cacheTime = followingIDsCacheTime,
           Date().timeIntervalSince(cacheTime) < 60 {
            return cached
        }

        struct FollowingID: Codable {
            let following_id: String
        }

        let response: [FollowingID] = try await supabase
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userID)
            .execute()
            .value

        let ids = response.map { $0.following_id }
        cachedFollowingIDs = ids
        followingIDsCacheTime = Date()
        return ids
    }

    // MARK: - Realtime Updates

    /// Subscribe to realtime updates for new logs from followed users
    func subscribeToRealtimeUpdates(for currentUserID: String) async {
        await unsubscribeFromRealtimeUpdates()

        do {
            let followingIDs = try await getFollowingIDs(for: currentUserID)
            guard !followingIDs.isEmpty else { return }

            let channel = supabase.channel("feed-\(currentUserID)")

            let logChanges = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "logs"
            )

            let tripActivityChanges = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "trip_activity"
            )

            await channel.subscribe()

            Task {
                for await change in logChanges {
                    if let userID = change.record["user_id"]?.stringValue,
                       followingIDs.contains(userID) {
                        await MainActor.run {
                            self.newPostsAvailable = true
                        }
                    }
                }
            }

            Task {
                for await change in tripActivityChanges {
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

    func unsubscribeFromRealtimeUpdates() async {
        if let channel = realtimeChannel {
            await supabase.removeChannel(channel)
            realtimeChannel = nil
        }
    }

    func showNewPosts(for currentUserID: String) async {
        newPostsAvailable = false
        await loadFeed(for: currentUserID)
    }

    // MARK: - Single Log Fetch

    func fetchFeedItem(logID: String) async throws -> FeedItem? {
        let response: [FeedLogResponse] = try await supabase
            .from("logs")
            .select("""
                id,
                rating,
                photo_urls,
                note,
                tags,
                created_at,
                users!logs_user_id_fkey(id, username, avatar_url, is_public),
                places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference, types)
            """)
            .eq("id", value: logID)
            .limit(1)
            .execute()
            .value

        return response.first?.toFeedItem()
    }

    // MARK: - User's Logs

    func fetchUserLogs(userID: String) async throws -> [FeedItem] {
        let response: [FeedLogResponse] = try await supabase
            .from("logs")
            .select("""
                id,
                rating,
                photo_urls,
                note,
                tags,
                created_at,
                users!logs_user_id_fkey(id, username, avatar_url, is_public),
                places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference, types)
            """)
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value

        return response.map { $0.toFeedItem() }
    }
}

// MARK: - Trip Log Response with trip_id

private struct TripLogWithTripID: Codable {
    let id: String
    let rating: String
    let photoURLs: [String]
    let createdAt: Date
    let tripID: String
    let place: FeedItem.FeedPlace

    /// Backward-compat: returns the first photo URL
    var photoURL: String? { photoURLs.first }

    enum CodingKeys: String, CodingKey {
        case id, rating
        case photoURLs = "photo_urls"
        case createdAt = "created_at"
        case tripID = "trip_id"
        case place = "places"
    }
}
