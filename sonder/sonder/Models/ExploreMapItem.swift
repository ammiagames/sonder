//
//  ExploreMapItem.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - LogSnapshot

/// Value-type snapshot of a Log's display properties.
/// Pins store these instead of live SwiftData `Log` references so that
/// deleted models never cause "detached backing data" crashes.
struct LogSnapshot: Equatable {
    let id: String
    let rating: Rating
    let photoURL: String?
    let note: String?
    let createdAt: Date
    let tags: [String]

    init(from log: Log) {
        self.id = log.id
        self.rating = log.rating
        self.photoURL = log.photoURL
        self.note = log.note
        self.createdAt = log.createdAt
        self.tags = log.tags
    }
}

// MARK: - UnifiedMapPin

/// A single pin on the unified map, representing the user's own log, friends' logs, or both.
enum UnifiedMapPin: Identifiable {
    case personal(logs: [LogSnapshot], place: Place)
    case friends(place: ExploreMapPlace)
    case combined(logs: [LogSnapshot], place: Place, friendPlace: ExploreMapPlace)

    var id: String {
        switch self {
        case .personal(_, let place): return "personal-\(place.id)"
        case .friends(let place): return "friends-\(place.id)"
        case .combined(_, let place, _): return "combined-\(place.id)"
        }
    }

    var placeID: String {
        switch self {
        case .personal(_, let place): return place.id
        case .friends(let place): return place.id
        case .combined(_, let place, _): return place.id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .personal(_, let place): return place.coordinate
        case .friends(let place): return place.coordinate
        case .combined(_, let place, _): return place.coordinate
        }
    }

    var placeName: String {
        switch self {
        case .personal(_, let place): return place.name
        case .friends(let place): return place.name
        case .combined(_, let place, _): return place.name
        }
    }

    var placeAddress: String {
        switch self {
        case .personal(_, let place): return place.address
        case .friends(let place): return place.address
        case .combined(_, let place, _): return place.address
        }
    }

    var photoReference: String? {
        switch self {
        case .personal(_, let place): return place.photoReference
        case .friends(let place): return place.photoReference
        case .combined(_, let place, _): return place.photoReference
        }
    }

    var userRating: Rating? {
        switch self {
        case .personal(let logs, _): return logs.first?.rating
        case .friends: return nil
        case .combined(let logs, _, _): return logs.first?.rating
        }
    }

    var friendCount: Int {
        switch self {
        case .personal: return 0
        case .friends(let place): return place.friendCount
        case .combined(_, _, let friendPlace): return friendPlace.friendCount
        }
    }

    var isFriendsLoved: Bool {
        switch self {
        case .personal: return false
        case .friends(let place): return place.isFriendsLoved
        case .combined(_, _, let friendPlace): return friendPlace.isFriendsLoved
        }
    }

    /// Best rating across all data (user + friends)
    var bestRating: Rating {
        switch self {
        case .personal(let logs, _):
            if logs.contains(where: { $0.rating == .mustSee }) { return .mustSee }
            if logs.contains(where: { $0.rating == .great }) { return .great }
            if logs.contains(where: { $0.rating == .okay }) { return .okay }
            return .skip
        case .friends(let place): return place.bestRating
        case .combined(let logs, _, let friendPlace):
            let friendBest = friendPlace.bestRating
            let personalBest: Rating
            if logs.contains(where: { $0.rating == .mustSee }) { personalBest = .mustSee }
            else if logs.contains(where: { $0.rating == .great }) { personalBest = .great }
            else if logs.contains(where: { $0.rating == .okay }) { personalBest = .okay }
            else { personalBest = .skip }
            if personalBest == .mustSee || friendBest == .mustSee { return .mustSee }
            if personalBest == .great || friendBest == .great { return .great }
            if personalBest == .okay || friendBest == .okay { return .okay }
            return .skip
        }
    }

    /// Most recent date across all data
    var latestDate: Date {
        switch self {
        case .personal(let logs, _): return logs.first?.createdAt ?? .distantPast
        case .friends(let place): return place.latestDate
        case .combined(let logs, _, let friendPlace):
            let personalLatest = logs.first?.createdAt ?? .distantPast
            return max(personalLatest, friendPlace.latestDate)
        }
    }
}

// MARK: - ExploreMapPlace

/// Groups multiple FeedItems sharing the same place_id for map display
struct ExploreMapPlace: Identifiable {
    let id: String // place_id
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let photoReference: String?
    var logs: [FeedItem]

    /// Deduplicated users who logged this place
    var users: [FeedItem.FeedUser] {
        var seen = Set<String>()
        return logs.compactMap { item in
            guard seen.insert(item.user.id).inserted else { return nil }
            return item.user
        }
    }

    /// Number of distinct friends who logged this place
    var friendCount: Int {
        users.count
    }

    /// Highest rating among all logs for this place
    var bestRating: Rating {
        if logs.contains(where: { $0.rating == .mustSee }) { return .mustSee }
        if logs.contains(where: { $0.rating == .great }) { return .great }
        if logs.contains(where: { $0.rating == .okay }) { return .okay }
        return .skip
    }

    /// True when any friend log has a written note
    var hasNote: Bool {
        logs.contains { $0.log.note?.isEmpty == false }
    }

    /// True when 2+ friends rated must-see
    var isFriendsLoved: Bool {
        logs.filter { $0.rating == .mustSee }.count >= 2
    }

    /// Most recent log date
    var latestDate: Date {
        logs.map(\.createdAt).max() ?? .distantPast
    }
}

// MARK: - ExploreMapFilter

struct ExploreMapFilter: Equatable {
    var rating: RatingFilter = .all
    /// Empty set means "All" (no category filtering). Non-empty means filter to only these.
    var categories: Set<CategoryFilter> = []
    var recency: RecencyFilter = .allTime
    var showWantToGo: Bool = true
    var showMyPlaces: Bool = true
    var showFriendsPlaces: Bool = true
    /// Empty set means show all friends. Non-empty means only show these friend IDs.
    var selectedFriendIDs: Set<String> = []
    /// Empty set means show all saved lists. Non-empty means only show these list IDs.
    var selectedSavedListIDs: Set<String> = []
    /// Empty set = show all. Non-empty = only show pins that have at least one of these tags.
    var selectedTags: Set<String> = []

    var isActive: Bool {
        rating != .all || !categories.isEmpty || recency != .allTime || !showWantToGo || !showMyPlaces || !showFriendsPlaces || !selectedFriendIDs.isEmpty || !selectedSavedListIDs.isEmpty || !selectedTags.isEmpty
    }

    mutating func toggleCategory(_ cat: CategoryFilter) {
        if categories.contains(cat) {
            categories.remove(cat)
        } else {
            categories.insert(cat)
        }
    }

    mutating func selectAllCategories() {
        categories = []
    }

    // MARK: - Rating Filter

    enum RatingFilter: CaseIterable {
        case all, okayPlus, greatPlus, mustSeeOnly

        var label: String {
            switch self {
            case .all: return "All"
            case .okayPlus: return "Okay+"
            case .greatPlus: return "Great+"
            case .mustSeeOnly: return "Must-See"
            }
        }

        func matches(_ rating: Rating) -> Bool {
            switch self {
            case .all: return true
            case .okayPlus: return rating == .okay || rating == .great || rating == .mustSee
            case .greatPlus: return rating == .great || rating == .mustSee
            case .mustSeeOnly: return rating == .mustSee
            }
        }
    }

    // MARK: - Category Filter

    enum CategoryFilter: CaseIterable {
        case food, coffee, nightlife, outdoors, shopping, attractions

        var label: String {
            switch self {
            case .food: return "Food"
            case .coffee: return "Coffee"
            case .nightlife: return "Nightlife"
            case .outdoors: return "Outdoors"
            case .shopping: return "Shopping"
            case .attractions: return "Attractions"
            }
        }

        var icon: String {
            switch self {
            case .food: return "fork.knife"
            case .coffee: return "cup.and.saucer"
            case .nightlife: return "moon.stars"
            case .outdoors: return "leaf"
            case .shopping: return "bag"
            case .attractions: return "building.columns"
            }
        }

        /// Google Place types that map to this category
        var placeTypes: Set<String> {
            switch self {
            case .food: return ["restaurant", "food", "meal_delivery", "meal_takeaway", "bakery"]
            case .coffee: return ["cafe", "coffee_shop"]
            case .nightlife: return ["bar", "night_club", "liquor_store"]
            case .outdoors: return ["park", "campground", "natural_feature", "hiking_area"]
            case .shopping: return ["shopping_mall", "store", "clothing_store", "shoe_store", "jewelry_store", "book_store"]
            case .attractions: return ["museum", "art_gallery", "tourist_attraction", "amusement_park", "aquarium", "zoo"]
            }
        }

        var color: Color {
            switch self {
            case .food:        return SonderColors.terracotta
            case .coffee:      return SonderColors.sage
            case .nightlife:   return SonderColors.ochre
            case .outdoors:    return SonderColors.dustyRose
            case .shopping:    return SonderColors.warmBlue
            case .attractions: return SonderColors.inkMuted
            }
        }

        static func category(for placeTypes: [String]) -> CategoryFilter? {
            let typeSet = Set(placeTypes)
            return allCases.first { !typeSet.isDisjoint(with: $0.placeTypes) }
        }

        /// Keywords for name-based matching (used for filtering pins)
        var keywords: [String] {
            switch self {
            case .food: return ["restaurant", "food", "grill", "sushi", "pizza", "burger", "taco", "ramen", "bistro", "diner", "eatery"]
            case .coffee: return ["coffee", "cafe", "espresso", "latte", "tea"]
            case .nightlife: return ["bar", "pub", "club", "lounge", "brewery", "cocktail", "wine"]
            case .outdoors: return ["park", "trail", "hike", "garden", "beach", "lake", "nature"]
            case .shopping: return ["shop", "store", "mall", "boutique", "market"]
            case .attractions: return ["museum", "gallery", "theater", "theatre", "landmark", "monument", "temple"]
            }
        }
    }

    /// Returns true if a place name matches the active category filters
    func matchesCategories(placeName: String) -> Bool {
        guard !categories.isEmpty else { return true }
        let name = placeName.lowercased()
        let allKeywords = categories.flatMap(\.keywords)
        return allKeywords.contains { name.contains($0) }
    }

    // MARK: - Recency Filter

    enum RecencyFilter: CaseIterable {
        case lastMonth, lastYear, allTime

        var label: String {
            switch self {
            case .lastMonth: return "Last Month"
            case .lastYear: return "Last Year"
            case .allTime: return "All Time"
            }
        }

        var cutoffDate: Date? {
            switch self {
            case .lastMonth: return Calendar.current.date(byAdding: .month, value: -1, to: Date())
            case .lastYear: return Calendar.current.date(byAdding: .year, value: -1, to: Date())
            case .allTime: return nil
            }
        }
    }
}
