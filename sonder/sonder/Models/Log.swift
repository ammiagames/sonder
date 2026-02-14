//
//  Log.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData

enum Rating: String, Codable, CaseIterable {
    case skip = "skip"
    case solid = "solid"
    case mustSee = "must_see"
    
    var emoji: String {
        switch self {
        case .skip: return "👎"
        case .solid: return "👍"
        case .mustSee: return "🔥"
        }
    }
    
    var displayName: String {
        switch self {
        case .skip: return "Skip"
        case .solid: return "Solid"
        case .mustSee: return "Must-See"
        }
    }

    var subtitle: String {
        switch self {
        case .skip: return "Wouldn't recommend"
        case .solid: return "Good, would go again"
        case .mustSee: return "Go out of your way"
        }
    }
}

enum SyncStatus: String, Codable {
    case synced
    case pending
    case failed
}

@Model
final class Log {
    @Attribute(.unique) var id: String
    var userID: String
    var placeID: String
    var rating: Rating
    var photoURL: String?
    var note: String?
    var tags: [String]
    var tripID: String?
    var syncStatus: SyncStatus
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: String = UUID().uuidString.lowercased(),
        userID: String,
        placeID: String,
        rating: Rating,
        photoURL: String? = nil,
        note: String? = nil,
        tags: [String] = [],
        tripID: String? = nil,
        syncStatus: SyncStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.placeID = placeID
        self.rating = rating
        self.photoURL = photoURL
        self.note = note
        self.tags = tags
        self.tripID = tripID
        self.syncStatus = syncStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Codable for Supabase sync
extension Log: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case placeID = "place_id"
        case rating
        case photoURL = "photo_url"
        case note
        case tags
        case tripID = "trip_id"
        case syncStatus = "sync_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let userID = try container.decode(String.self, forKey: .userID)
        let placeID = try container.decode(String.self, forKey: .placeID)
        let rating = try container.decode(Rating.self, forKey: .rating)
        let photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        let note = try container.decodeIfPresent(String.self, forKey: .note)
        let tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        let tripID = try container.decodeIfPresent(String.self, forKey: .tripID)
        let syncStatus = try container.decodeIfPresent(SyncStatus.self, forKey: .syncStatus) ?? .synced
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        self.init(
            id: id,
            userID: userID,
            placeID: placeID,
            rating: rating,
            photoURL: photoURL,
            note: note,
            tags: tags,
            tripID: tripID,
            syncStatus: syncStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(placeID, forKey: .placeID)
        try container.encode(rating, forKey: .rating)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(tripID, forKey: .tripID)
        try container.encode(syncStatus, forKey: .syncStatus)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
