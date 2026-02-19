import Foundation
@testable import sonder

/// Factory for creating test model instances with sensible defaults
enum TestData {

    // MARK: - User

    static func user(
        id: String = "user-1",
        username: String = "testuser",
        firstName: String? = nil,
        email: String? = "test@example.com",
        avatarURL: String? = nil,
        bio: String? = nil,
        isPublic: Bool = true,
        pinnedPlaceIDs: [String] = [],
        createdAt: Date = fixedDate(),
        updatedAt: Date = fixedDate()
    ) -> User {
        User(
            id: id,
            username: username,
            firstName: firstName,
            email: email,
            avatarURL: avatarURL,
            bio: bio,
            isPublic: isPublic,
            pinnedPlaceIDs: pinnedPlaceIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Place

    static func place(
        id: String = "place-1",
        name: String = "Test Place",
        address: String = "123 Test St",
        latitude: Double = 40.7128,
        longitude: Double = -74.0060,
        types: [String] = ["restaurant"],
        photoReference: String? = nil,
        createdAt: Date = fixedDate()
    ) -> Place {
        Place(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            types: types,
            photoReference: photoReference,
            createdAt: createdAt
        )
    }

    // MARK: - Log

    static func log(
        id: String = UUID().uuidString,
        userID: String = "user-1",
        placeID: String = "place-1",
        rating: Rating = .solid,
        photoURLs: [String] = [],
        note: String? = nil,
        tags: [String] = [],
        tripID: String? = nil,
        tripSortOrder: Int? = nil,
        visitedAt: Date = fixedDate(),
        syncStatus: SyncStatus = .pending,
        createdAt: Date = fixedDate(),
        updatedAt: Date = fixedDate()
    ) -> Log {
        Log(
            id: id,
            userID: userID,
            placeID: placeID,
            rating: rating,
            photoURLs: photoURLs,
            note: note,
            tags: tags,
            tripID: tripID,
            tripSortOrder: tripSortOrder,
            visitedAt: visitedAt,
            syncStatus: syncStatus,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Trip

    static func trip(
        id: String = UUID().uuidString,
        name: String = "Test Trip",
        tripDescription: String? = nil,
        coverPhotoURL: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        collaboratorIDs: [String] = [],
        createdBy: String = "user-1",
        createdAt: Date = fixedDate(),
        updatedAt: Date = fixedDate()
    ) -> Trip {
        Trip(
            id: id,
            name: name,
            tripDescription: tripDescription,
            coverPhotoURL: coverPhotoURL,
            startDate: startDate,
            endDate: endDate,
            collaboratorIDs: collaboratorIDs,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: .synced
        )
    }

    // MARK: - TripInvitation

    static func tripInvitation(
        id: String = UUID().uuidString,
        tripID: String = "trip-1",
        inviterID: String = "user-1",
        inviteeID: String = "user-2",
        status: InvitationStatus = .pending,
        createdAt: Date = fixedDate()
    ) -> TripInvitation {
        TripInvitation(
            id: id,
            tripID: tripID,
            inviterID: inviterID,
            inviteeID: inviteeID,
            status: status,
            createdAt: createdAt
        )
    }

    // MARK: - Follow

    static func follow(
        followerID: String = "user-1",
        followingID: String = "user-2",
        createdAt: Date = fixedDate()
    ) -> Follow {
        Follow(
            followerID: followerID,
            followingID: followingID,
            createdAt: createdAt
        )
    }

    // MARK: - WantToGo

    static func wantToGo(
        id: String = UUID().uuidString,
        userID: String = "user-1",
        placeID: String = "place-1",
        placeName: String? = nil,
        placeAddress: String? = nil,
        photoReference: String? = nil,
        sourceLogID: String? = nil,
        createdAt: Date = fixedDate()
    ) -> WantToGo {
        WantToGo(
            id: id,
            userID: userID,
            placeID: placeID,
            placeName: placeName,
            placeAddress: placeAddress,
            photoReference: photoReference,
            sourceLogID: sourceLogID,
            createdAt: createdAt
        )
    }

    // MARK: - RecentSearch

    static func recentSearch(
        placeId: String = "place-1",
        name: String = "Test Place",
        address: String = "123 Test St",
        searchedAt: Date = fixedDate()
    ) -> RecentSearch {
        RecentSearch(
            placeId: placeId,
            name: name,
            address: address,
            searchedAt: searchedAt
        )
    }

    // MARK: - FeedItem

    static func feedItem(
        id: String = "feed-1",
        log: FeedItem.FeedLog? = nil,
        user: FeedItem.FeedUser? = nil,
        place: FeedItem.FeedPlace? = nil
    ) -> FeedItem {
        FeedItem(
            id: id,
            log: log ?? feedLog(),
            user: user ?? feedUser(),
            place: place ?? feedPlace()
        )
    }

    static func feedLog(
        id: String = "log-1",
        rating: String = "solid",
        photoURLs: [String] = [],
        note: String? = "Great spot",
        tags: [String] = ["food"],
        createdAt: Date = fixedDate(),
        tripID: String? = nil
    ) -> FeedItem.FeedLog {
        FeedItem.FeedLog(
            id: id,
            rating: rating,
            photoURLs: photoURLs,
            note: note,
            tags: tags,
            createdAt: createdAt,
            tripID: tripID
        )
    }

    static func feedUser(
        id: String = "user-1",
        username: String = "testuser",
        avatarURL: String? = nil,
        isPublic: Bool = true
    ) -> FeedItem.FeedUser {
        FeedItem.FeedUser(
            id: id,
            username: username,
            avatarURL: avatarURL,
            isPublic: isPublic
        )
    }

    static func feedPlace(
        id: String = "place-1",
        name: String = "Test Place",
        address: String = "123 Test St",
        latitude: Double = 40.7128,
        longitude: Double = -74.0060,
        photoReference: String? = nil,
        types: [String] = []
    ) -> FeedItem.FeedPlace {
        FeedItem.FeedPlace(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            photoReference: photoReference,
            types: types
        )
    }

    // MARK: - FeedTripItem

    static func feedTripItem(
        id: String = "trip-1",
        name: String = "Test Trip",
        coverPhotoURL: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        user: FeedItem.FeedUser? = nil,
        logs: [FeedTripItem.LogSummary] = [],
        latestActivityAt: Date = fixedDate(),
        activitySubtitle: String = "trip"
    ) -> FeedTripItem {
        FeedTripItem(
            id: id,
            name: name,
            coverPhotoURL: coverPhotoURL,
            startDate: startDate,
            endDate: endDate,
            user: user ?? feedUser(),
            logs: logs,
            latestActivityAt: latestActivityAt,
            activitySubtitle: activitySubtitle
        )
    }

    // MARK: - FeedTripCreatedItem

    static func feedTripCreatedItem(
        id: String = "activity-1",
        tripID: String = "trip-1",
        tripName: String = "Test Trip",
        coverPhotoURL: String? = nil,
        user: FeedItem.FeedUser? = nil,
        createdAt: Date = fixedDate()
    ) -> FeedTripCreatedItem {
        FeedTripCreatedItem(
            id: id,
            tripID: tripID,
            tripName: tripName,
            coverPhotoURL: coverPhotoURL,
            user: user ?? feedUser(),
            createdAt: createdAt
        )
    }

    // MARK: - TripActivityResponse

    static func tripActivityResponse(
        id: String = "activity-1",
        tripID: String = "trip-1",
        activityType: String = "log_added",
        logID: String? = "log-1",
        placeName: String? = "Test Place",
        createdAt: Date = fixedDate()
    ) -> TripActivityResponse {
        TripActivityResponse(
            id: id,
            tripID: tripID,
            activityType: activityType,
            logID: logID,
            placeName: placeName,
            createdAt: createdAt
        )
    }

    // MARK: - PlaceDetails

    static func placeDetails(
        placeId: String = "place-1",
        name: String = "Test Place",
        formattedAddress: String = "123 Test St",
        latitude: Double = 40.7128,
        longitude: Double = -74.0060,
        types: [String] = ["restaurant"],
        photoReference: String? = "photo-ref-1",
        rating: Double? = 4.5,
        userRatingCount: Int? = 100,
        priceLevel: PriceLevel? = .moderate,
        editorialSummary: String? = "A great place"
    ) -> PlaceDetails {
        PlaceDetails(
            placeId: placeId,
            name: name,
            formattedAddress: formattedAddress,
            latitude: latitude,
            longitude: longitude,
            types: types,
            photoReference: photoReference,
            rating: rating,
            userRatingCount: userRatingCount,
            priceLevel: priceLevel,
            editorialSummary: editorialSummary
        )
    }

    // MARK: - NearbyPlace

    static func nearbyPlace(
        placeId: String = "nearby-1",
        name: String = "Nearby Place",
        address: String = "456 Nearby Ave",
        latitude: Double = 40.7130,
        longitude: Double = -74.0062,
        types: [String] = ["cafe"],
        photoReference: String? = nil
    ) -> NearbyPlace {
        NearbyPlace(
            placeId: placeId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            types: types,
            photoReference: photoReference
        )
    }
}
