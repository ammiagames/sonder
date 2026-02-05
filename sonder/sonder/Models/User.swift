//
//  User.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: String
    var username: String
    var avatarURL: String?
    var bio: String?
    var isPublic: Bool
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: String,
        username: String,
        avatarURL: String? = nil,
        bio: String? = nil,
        isPublic: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.avatarURL = avatarURL
        self.bio = bio
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Codable for Supabase sync
extension User: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarURL = "avatar_url"
        case bio
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let username = try container.decode(String.self, forKey: .username)
        let avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        let bio = try container.decodeIfPresent(String.self, forKey: .bio)
        let isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.init(
            id: id,
            username: username,
            avatarURL: avatarURL,
            bio: bio,
            isPublic: isPublic,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encode(isPublic, forKey: .isPublic)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
