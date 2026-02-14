//
//  ExploreMapService.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import Foundation
import CoreLocation
import Supabase

@MainActor
@Observable
final class ExploreMapService {
    private let supabase = SupabaseConfig.client

    // State
    var placesMap: [String: ExploreMapPlace] = [:]
    var isLoading = false
    var hasLoaded = false
    var error: String?

    // MARK: - Load Friends' Places

    /// Fetches all logs from users the current user follows, grouped by place_id
    func loadFriendsPlaces(for currentUserID: String) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let followingIDs = try await getFollowingIDs(for: currentUserID)

            guard !followingIDs.isEmpty else {
                placesMap = [:]
                isLoading = false
                return
            }

            let selectQuery = """
                id,
                rating,
                photo_url,
                note,
                tags,
                created_at,
                users!logs_user_id_fkey(id, username, avatar_url, is_public),
                places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
            """

            let response: [FeedLogResponse] = try await supabase
                .from("logs")
                .select(selectQuery)
                .in("user_id", values: followingIDs)
                .order("created_at", ascending: false)
                .limit(500)
                .execute()
                .value

            let feedItems = response.map { $0.toFeedItem() }
            placesMap = groupByPlace(feedItems)
        } catch {
            self.error = error.localizedDescription
            print("Error loading explore map: \(error)")
        }

        isLoading = false
        hasLoaded = true
    }

    // MARK: - Filtering

    /// Returns places matching the given filter
    func filteredPlaces(filter: ExploreMapFilter) -> [ExploreMapPlace] {
        var results = Array(placesMap.values)

        // Rating filter
        if filter.rating != .all {
            results = results.filter { place in
                filter.rating.matches(place.bestRating)
            }
        }

        // Recency filter
        if let cutoff = filter.recency.cutoffDate {
            results = results.filter { place in
                place.latestDate >= cutoff
            }
        }

        // Category filter — empty set means "All", non-empty means filter
        if !filter.categories.isEmpty {
            let allKeywords = filter.categories.flatMap(\.keywords)
            results = results.filter { place in
                let name = place.name.lowercased()
                let tags = place.logs.flatMap(\.log.tags).joined(separator: " ").lowercased()
                return allKeywords.contains { name.contains($0) || tags.contains($0) }
            }
        }

        return results
    }

    /// All unique friends who have logged at least one place on the map
    var allFriends: [FeedItem.FeedUser] {
        var seen = Set<String>()
        var result: [FeedItem.FeedUser] = []
        for place in placesMap.values {
            for item in place.logs {
                if seen.insert(item.user.id).inserted {
                    result.append(item.user)
                }
            }
        }
        return result.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    /// Returns places where 2+ friends rated must-see
    func friendsLovedPlaces() -> [ExploreMapPlace] {
        Array(placesMap.values).filter { $0.isFriendsLoved }
    }

    // MARK: - Unified Pin Computation

    /// Merges personal logs with friends' places into unified pins.
    /// Snapshots Log objects into value types to avoid holding live SwiftData references.
    func computeUnifiedPins(personalLogs: [Log], places: [Place]) -> [UnifiedMapPin] {
        // Build lookup: placeID -> ([LogSnapshot], Place)
        var personalByPlaceID: [String: ([LogSnapshot], Place)] = [:]
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })

        for log in personalLogs {
            guard let place = placesByID[log.placeID] else { continue }
            let snapshot = LogSnapshot(from: log)
            if var existing = personalByPlaceID[log.placeID] {
                existing.0.append(snapshot)
                personalByPlaceID[log.placeID] = existing
            } else {
                personalByPlaceID[log.placeID] = ([snapshot], place)
            }
        }

        // Sort each group by createdAt descending (most recent first)
        for (placeID, var entry) in personalByPlaceID {
            entry.0.sort { $0.createdAt > $1.createdAt }
            personalByPlaceID[placeID] = entry
        }

        let personalIDs = Set(personalByPlaceID.keys)
        let friendIDs = Set(placesMap.keys)

        var pins: [UnifiedMapPin] = []

        // Both personal + friends
        for placeID in personalIDs.intersection(friendIDs) {
            let (logs, place) = personalByPlaceID[placeID]!
            let friendPlace = placesMap[placeID]!
            pins.append(.combined(logs: logs, place: place, friendPlace: friendPlace))
        }

        // Personal only
        for placeID in personalIDs.subtracting(friendIDs) {
            let (logs, place) = personalByPlaceID[placeID]!
            pins.append(.personal(logs: logs, place: place))
        }

        // Friends only
        for placeID in friendIDs.subtracting(personalIDs) {
            let friendPlace = placesMap[placeID]!
            pins.append(.friends(place: friendPlace))
        }

        return pins
    }

    /// Filters unified pins based on layer visibility and standard filters
    func filteredUnifiedPins(pins: [UnifiedMapPin], filter: ExploreMapFilter, bookmarkedPlaceIDs: Set<String> = []) -> [UnifiedMapPin] {
        pins.compactMap { pin -> UnifiedMapPin? in
            let isBookmarked = bookmarkedPlaceIDs.contains(pin.placeID)

            // Layer visibility + friend ID filtering
            let visiblePin: UnifiedMapPin?
            switch pin {
            case .personal:
                visiblePin = (filter.showMyPlaces || isBookmarked) ? pin : nil
            case .friends(let friendPlace):
                guard filter.showFriendsPlaces || isBookmarked else { visiblePin = nil; break }
                visiblePin = filterFriendPlace(friendPlace, selectedIDs: filter.selectedFriendIDs)
                    .map { .friends(place: $0) } ?? (isBookmarked ? pin : nil)
            case .combined(let logs, let place, let friendPlace):
                let filteredFriend = filter.showFriendsPlaces
                    ? filterFriendPlace(friendPlace, selectedIDs: filter.selectedFriendIDs)
                    : nil

                if filter.showMyPlaces && filteredFriend != nil {
                    visiblePin = .combined(logs: logs, place: place, friendPlace: filteredFriend!)
                } else if filter.showMyPlaces {
                    visiblePin = .personal(logs: logs, place: place)
                } else if let filtered = filteredFriend {
                    visiblePin = .friends(place: filtered)
                } else if isBookmarked {
                    // Place is bookmarked but neither layer is on — still show it
                    visiblePin = .combined(logs: logs, place: place, friendPlace: friendPlace)
                } else {
                    visiblePin = nil
                }
            }

            guard let resultPin = visiblePin else { return nil }

            // Rating filter
            if filter.rating != .all {
                guard filter.rating.matches(resultPin.bestRating) else { return nil }
            }

            // Recency filter
            if let cutoff = filter.recency.cutoffDate {
                guard resultPin.latestDate >= cutoff else { return nil }
            }

            // Category filter
            if !filter.categories.isEmpty {
                guard filter.matchesCategories(placeName: resultPin.placeName) else { return nil }
            }

            return resultPin
        }
    }

    /// Returns a filtered copy of the friend place keeping only logs from selectedIDs,
    /// or the original place if selectedIDs is empty (show all). Returns nil if no logs remain.
    private func filterFriendPlace(_ place: ExploreMapPlace, selectedIDs: Set<String>) -> ExploreMapPlace? {
        guard !selectedIDs.isEmpty else { return place }
        let filtered = place.logs.filter { selectedIDs.contains($0.user.id) }
        guard !filtered.isEmpty else { return nil }
        var copy = place
        copy.logs = filtered
        return copy
    }

    // MARK: - Private Helpers

    private func getFollowingIDs(for userID: String) async throws -> [String] {
        struct FollowingID: Codable {
            let following_id: String
        }

        let response: [FollowingID] = try await supabase
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userID)
            .execute()
            .value

        return response.map { $0.following_id }
    }

    private func groupByPlace(_ items: [FeedItem]) -> [String: ExploreMapPlace] {
        var map: [String: ExploreMapPlace] = [:]

        for item in items {
            let placeID = item.place.id
            if var existing = map[placeID] {
                existing.logs.append(item)
                map[placeID] = existing
            } else {
                map[placeID] = ExploreMapPlace(
                    id: placeID,
                    name: item.place.name,
                    address: item.place.address,
                    coordinate: CLLocationCoordinate2D(
                        latitude: item.place.latitude,
                        longitude: item.place.longitude
                    ),
                    photoReference: item.place.photoReference,
                    logs: [item]
                )
            }
        }

        return map
    }

}
