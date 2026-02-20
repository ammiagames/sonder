//
//  SavedList.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class SavedList {
    #Index<SavedList>([\.userID])

    @Attribute(.unique) var id: String
    var userID: String
    var name: String
    var emoji: String
    var isDefault: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userID: String,
        name: String,
        emoji: String = "\u{1F516}",
        isDefault: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.emoji = emoji
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Codable for Supabase sync
extension SavedList: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case emoji
        case isDefault = "is_default"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let userID = try container.decode(String.self, forKey: .userID)
        let name = try container.decode(String.self, forKey: .name)
        let emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "\u{1F516}"
        let isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        let sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.init(
            id: id,
            userID: userID,
            name: name,
            emoji: emoji,
            isDefault: isDefault,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
