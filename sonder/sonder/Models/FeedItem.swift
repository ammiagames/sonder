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

// MARK: - Relative Date Display

extension Date {
    /// Returns a human-readable relative time string:
    /// "Just now", "5m ago", "3h ago", "2d ago", or the actual date for older posts.
    var relativeDisplay: String {
        let now = Date()
        let seconds = Int(now.timeIntervalSince(self))

        if seconds < 60 { return "Just now" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }

        let days = hours / 24
        if days < 7 { return "\(days)d ago" }

        return self.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Trip Feed Item

/// A composite DTO representing a trip with its logs in the feed.
struct FeedTripItem: Identifiable {
    let id: String
    let name: String
    let coverPhotoURL: String?
    let startDate: Date?
    let endDate: Date?
    let user: FeedItem.FeedUser
    let logs: [LogSummary]
    let latestActivityAt: Date

    struct LogSummary: Identifiable {
        let id: String
        let photoURL: String?
        let rating: String
        let placeName: String
        let placePhotoReference: String?
        let createdAt: Date
    }

    var dateRangeDisplay: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if let start = startDate, let end = endDate {
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = startDate {
            return "From \(formatter.string(from: start))"
        }
        return nil
    }
}

// MARK: - Unified Feed Entry

enum FeedEntry: Identifiable {
    case trip(FeedTripItem)
    case log(FeedItem)

    var id: String {
        switch self {
        case .trip(let item): return "trip-\(item.id)"
        case .log(let item): return "log-\(item.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .trip(let item): return item.latestActivityAt
        case .log(let item): return item.createdAt
        }
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
    let tripID: String?
    let user: FeedItem.FeedUser
    let place: FeedItem.FeedPlace

    enum CodingKeys: String, CodingKey {
        case id
        case rating
        case photoURL = "photo_url"
        case note
        case tags
        case createdAt = "created_at"
        case tripID = "trip_id"
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

// MARK: - Trip Feed Response

/// Response for trip query with joined user data
struct FeedTripResponse: Codable {
    let id: String
    let name: String
    let coverPhotoURL: String?
    let startDate: Date?
    let endDate: Date?
    let createdBy: String
    let user: FeedItem.FeedUser

    enum CodingKeys: String, CodingKey {
        case id, name
        case coverPhotoURL = "cover_photo_url"
        case startDate = "start_date"
        case endDate = "end_date"
        case createdBy = "created_by"
        case user = "users"
    }
}

/// Response for logs belonging to a trip
struct TripLogResponse: Codable {
    let id: String
    let rating: String
    let photoURL: String?
    let createdAt: Date
    let place: FeedItem.FeedPlace

    enum CodingKeys: String, CodingKey {
        case id, rating
        case photoURL = "photo_url"
        case createdAt = "created_at"
        case place = "places"
    }
}
