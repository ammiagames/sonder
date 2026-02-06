//
//  SocialService.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData
import Supabase

@MainActor
@Observable
final class SocialService {
    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client

    // Cached counts for current user
    var followerCount = 0
    var followingCount = 0
    var countsLoaded = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Follow/Unfollow

    /// Follow a user
    func followUser(userID: String, currentUserID: String) async throws {
        guard userID != currentUserID else { return }

        // Insert into Supabase
        struct FollowInsert: Codable {
            let follower_id: String
            let following_id: String
        }

        try await supabase
            .from("follows")
            .insert(FollowInsert(follower_id: currentUserID, following_id: userID))
            .execute()

        // Cache locally
        let follow = Follow(followerID: currentUserID, followingID: userID)
        modelContext.insert(follow)
        try modelContext.save()

        // Update counts
        await refreshCounts(for: currentUserID)
    }

    /// Unfollow a user
    func unfollowUser(userID: String, currentUserID: String) async throws {
        // Delete from Supabase
        try await supabase
            .from("follows")
            .delete()
            .eq("follower_id", value: currentUserID)
            .eq("following_id", value: userID)
            .execute()

        // Remove from local cache
        let followerIDCopy = currentUserID
        let followingIDCopy = userID
        let descriptor = FetchDescriptor<Follow>(
            predicate: #Predicate { follow in
                follow.followerID == followerIDCopy && follow.followingID == followingIDCopy
            }
        )

        if let cached = try? modelContext.fetch(descriptor).first {
            modelContext.delete(cached)
            try modelContext.save()
        }

        // Update counts
        await refreshCounts(for: currentUserID)
    }

    /// Check if current user is following another user
    func isFollowing(userID: String, currentUserID: String) -> Bool {
        let followerIDCopy = currentUserID
        let followingIDCopy = userID
        let descriptor = FetchDescriptor<Follow>(
            predicate: #Predicate { follow in
                follow.followerID == followerIDCopy && follow.followingID == followingIDCopy
            }
        )

        return (try? modelContext.fetch(descriptor).first) != nil
    }

    /// Check if current user is following (async - checks Supabase if not cached)
    func isFollowingAsync(userID: String, currentUserID: String) async -> Bool {
        // First check local cache
        if isFollowing(userID: userID, currentUserID: currentUserID) {
            return true
        }

        // Check Supabase
        do {
            let response: [Follow] = try await supabase
                .from("follows")
                .select()
                .eq("follower_id", value: currentUserID)
                .eq("following_id", value: userID)
                .execute()
                .value

            if let follow = response.first {
                // Cache locally
                modelContext.insert(follow)
                try modelContext.save()
                return true
            }
        } catch {
            print("Error checking follow status: \(error)")
        }

        return false
    }

    // MARK: - Follower/Following Lists

    /// Get list of users the given user is following
    func getFollowing(for userID: String) async throws -> [User] {
        struct FollowWithUser: Codable {
            let following_id: String
            let users: User

            enum CodingKeys: String, CodingKey {
                case following_id
                case users
            }
        }

        let response: [FollowWithUser] = try await supabase
            .from("follows")
            .select("following_id, users!follows_following_id_fkey(*)")
            .eq("follower_id", value: userID)
            .execute()
            .value

        return response.map { $0.users }
    }

    /// Get list of users following the given user
    func getFollowers(for userID: String) async throws -> [User] {
        struct FollowWithUser: Codable {
            let follower_id: String
            let users: User

            enum CodingKeys: String, CodingKey {
                case follower_id
                case users
            }
        }

        let response: [FollowWithUser] = try await supabase
            .from("follows")
            .select("follower_id, users!follows_follower_id_fkey(*)")
            .eq("following_id", value: userID)
            .execute()
            .value

        return response.map { $0.users }
    }

    /// Get follower count for a user
    func getFollowerCount(for userID: String) async -> Int {
        do {
            let response = try await supabase
                .from("follows")
                .select("*", head: true, count: .exact)
                .eq("following_id", value: userID)
                .execute()

            return response.count ?? 0
        } catch {
            print("Error fetching follower count: \(error)")
            return 0
        }
    }

    /// Get following count for a user
    func getFollowingCount(for userID: String) async -> Int {
        do {
            let response = try await supabase
                .from("follows")
                .select("*", head: true, count: .exact)
                .eq("follower_id", value: userID)
                .execute()

            return response.count ?? 0
        } catch {
            print("Error fetching following count: \(error)")
            return 0
        }
    }

    /// Refresh cached counts for current user
    func refreshCounts(for userID: String) async {
        followerCount = await getFollowerCount(for: userID)
        followingCount = await getFollowingCount(for: userID)
        countsLoaded = true
    }

    // MARK: - User Search

    /// Search for users by username
    func searchUsers(query: String) async throws -> [User] {
        guard !query.isEmpty else { return [] }

        let users: [User] = try await supabase
            .from("users")
            .select()
            .ilike("username", pattern: "%\(query)%")
            .limit(20)
            .execute()
            .value

        return users
    }

    /// Get a user by ID
    func getUser(id: String) async throws -> User? {
        let users: [User] = try await supabase
            .from("users")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        return users.first
    }

    // MARK: - Local Cache Sync

    /// Sync follow relationships from Supabase to local cache
    func syncFollows(for userID: String) async {
        do {
            // Fetch all follows where user is follower
            let following: [Follow] = try await supabase
                .from("follows")
                .select()
                .eq("follower_id", value: userID)
                .execute()
                .value

            // Clear existing local cache for this user
            let userIDCopy = userID
            let descriptor = FetchDescriptor<Follow>(
                predicate: #Predicate { follow in
                    follow.followerID == userIDCopy
                }
            )

            let existing = try modelContext.fetch(descriptor)
            for follow in existing {
                modelContext.delete(follow)
            }

            // Insert fresh data
            for follow in following {
                modelContext.insert(follow)
            }

            try modelContext.save()

            // Update counts
            await refreshCounts(for: userID)
        } catch {
            print("Error syncing follows: \(error)")
        }
    }
}
