//
//  SocialService.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData
import Supabase
import os

@MainActor
@Observable
final class SocialService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "SocialService")
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
            logger.error("Error checking follow status: \(error.localizedDescription)")
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
            logger.error("Error fetching follower count: \(error.localizedDescription)")
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
            logger.error("Error fetching following count: \(error.localizedDescription)")
            return 0
        }
    }

    /// Refresh cached counts for current user
    func refreshCounts(for userID: String) async {
        async let f = getFollowerCount(for: userID)
        async let g = getFollowingCount(for: userID)
        (followerCount, followingCount) = await (f, g)
        countsLoaded = true
    }

    // MARK: - User Search

    /// Search for users by username with autocomplete
    func searchUsers(query: String) async throws -> [User] {
        guard !query.isEmpty else { return [] }

        // Search by username with partial matching
        let users: [User] = try await supabase
            .from("users")
            .select()
            .ilike("username", pattern: "%\(query)%")
            .limit(20)
            .execute()
            .value

        // Sort results: prefix matches first, then alphabetical
        let lowercaseQuery = query.lowercased()
        return users.sorted { user1, user2 in
            let u1StartsWithQuery = user1.username.lowercased().hasPrefix(lowercaseQuery)
            let u2StartsWithQuery = user2.username.lowercased().hasPrefix(lowercaseQuery)

            if u1StartsWithQuery && !u2StartsWithQuery {
                return true
            } else if !u1StartsWithQuery && u2StartsWithQuery {
                return false
            } else {
                return user1.username.lowercased() < user2.username.lowercased()
            }
        }
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

}
