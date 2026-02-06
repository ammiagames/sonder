//
//  FeedItem.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation

/// A composite DTO representing a log with its associated user and place data for feed display.
/// This is not persisted in SwiftData - it's assembled from joined Supabase queries.
struct FeedItem: Identifiable, Codable {
    let id: String
    let log: FeedLog
    let user: FeedUser
    let place: FeedPlace

    struct FeedLog: Codable {
        let id: String
        let rating: String
        let photoURL: String?
        let note: String?
        let tags: [String]
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case rating
            case photoURL = "photo_url"
            case note
            case tags
            case createdAt = "created_at"
        }
    }

    struct FeedUser: Codable {
        let id: String
        let username: String
        let avatarURL: String?
        let isPublic: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case username
            case avatarURL = "avatar_url"
            case isPublic = "is_public"
        }
    }

    struct FeedPlace: Codable {
        let id: String
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let photoReference: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case address
            case latitude = "lat"
            case longitude = "lng"
            case photoReference = "photo_reference"
        }
    }
}

// MARK: - Convenience Extensions

extension FeedItem {
    var rating: Rating {
        Rating(rawValue: log.rating) ?? .solid
    }

    var createdAt: Date {
        log.createdAt
    }
}

// MARK: - Supabase Response Decoding

/// Response structure for the feed query with joined data
struct FeedLogResponse: Codable {
    let id: String
    let rating: String
    let photoURL: String?
    let note: String?
    let tags: [String]
    let createdAt: Date
    let user: FeedItem.FeedUser
    let place: FeedItem.FeedPlace

    enum CodingKeys: String, CodingKey {
        case id
        case rating
        case photoURL = "photo_url"
        case note
        case tags
        case createdAt = "created_at"
        case user = "users"
        case place = "places"
    }

    func toFeedItem() -> FeedItem {
        FeedItem(
            id: id,
            log: FeedItem.FeedLog(
                id: id,
                rating: rating,
                photoURL: photoURL,
                note: note,
                tags: tags,
                createdAt: createdAt
            ),
            user: user,
            place: place
        )
    }
}
