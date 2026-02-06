//
//  Follow.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData

@Model
final class Follow {
    var followerID: String
    var followingID: String
    var createdAt: Date

    init(
        followerID: String,
        followingID: String,
        createdAt: Date = Date()
    ) {
        self.followerID = followerID
        self.followingID = followingID
        self.createdAt = createdAt
    }
}

// MARK: - Codable for Supabase sync
extension Follow: Codable {
    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
        case createdAt = "created_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let followerID = try container.decode(String.self, forKey: .followerID)
        let followingID = try container.decode(String.self, forKey: .followingID)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.init(
            followerID: followerID,
            followingID: followingID,
            createdAt: createdAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(followerID, forKey: .followerID)
        try container.encode(followingID, forKey: .followingID)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
