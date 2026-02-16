import Testing
import Foundation
@testable import sonder

struct FeedItemTests {

    @Test func ratingConvenience() {
        let item = TestData.feedItem(log: TestData.feedLog(rating: "must_see"))
        #expect(item.rating == .mustSee)
    }

    @Test func ratingFallback() {
        let item = TestData.feedItem(log: TestData.feedLog(rating: "unknown_value"))
        #expect(item.rating == .solid) // default fallback
    }

    @Test func createdAtDelegation() {
        let date = fixedDate()
        let item = TestData.feedItem(log: TestData.feedLog(createdAt: date))
        #expect(item.createdAt == date)
    }

    @Test func identifiable() {
        let item = TestData.feedItem(id: "custom-id")
        #expect(item.id == "custom-id")
    }

    @Test func feedLogResponseToFeedItem() {
        let date = fixedDate()
        let response = FeedLogResponse(
            id: "log-1",
            rating: "must_see",
            photoURLs: ["https://example.com/photo.jpg"],
            note: "Amazing",
            tags: ["food"],
            createdAt: date,
            tripID: nil,
            user: TestData.feedUser(id: "u1", username: "alice"),
            place: TestData.feedPlace(id: "p1", name: "Cafe")
        )

        let feedItem = response.toFeedItem()

        #expect(feedItem.id == "log-1")
        #expect(feedItem.log.rating == "must_see")
        #expect(feedItem.log.photoURLs == ["https://example.com/photo.jpg"])
        #expect(feedItem.log.photoURL == "https://example.com/photo.jpg")
        #expect(feedItem.log.note == "Amazing")
        #expect(feedItem.log.tags == ["food"])
        #expect(feedItem.user.id == "u1")
        #expect(feedItem.user.username == "alice")
        #expect(feedItem.place.id == "p1")
        #expect(feedItem.place.name == "Cafe")
    }

    @Test func feedLogCodableSnakeCase() throws {
        let log = TestData.feedLog(photoURLs: ["https://example.com/pic.jpg"])
        let data = try makeEncoder().encode(log)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["photo_urls"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["photoURLs"] == nil)
        #expect(json["createdAt"] == nil)
    }

    // MARK: - Date.relativeDisplay

    @Test func relativeDisplay_justNow() {
        let date = Date()
        #expect(date.relativeDisplay == "Just now")
    }

    @Test func relativeDisplay_secondsAgo() {
        let date = Date().addingTimeInterval(-30)
        #expect(date.relativeDisplay == "Just now")
    }

    @Test func relativeDisplay_minutesAgo() {
        let date = Date().addingTimeInterval(-5 * 60)
        #expect(date.relativeDisplay == "5m ago")
    }

    @Test func relativeDisplay_oneMinuteAgo() {
        let date = Date().addingTimeInterval(-60)
        #expect(date.relativeDisplay == "1m ago")
    }

    @Test func relativeDisplay_hoursAgo() {
        let date = Date().addingTimeInterval(-3 * 3600)
        #expect(date.relativeDisplay == "3h ago")
    }

    @Test func relativeDisplay_daysAgo() {
        let date = Date().addingTimeInterval(-2 * 86400)
        #expect(date.relativeDisplay == "2d ago")
    }

    @Test func relativeDisplay_sixDaysAgo() {
        let date = Date().addingTimeInterval(-6 * 86400)
        #expect(date.relativeDisplay == "6d ago")
    }

    @Test func relativeDisplay_olderThanWeek_showsDate() {
        let date = Date().addingTimeInterval(-10 * 86400)
        // Should fall back to abbreviated date, not relative
        #expect(!date.relativeDisplay.contains("ago"))
        #expect(!date.relativeDisplay.contains("Just now"))
    }

    // MARK: - Activity Subtitle

    @Test func activitySubtitle_logAddedWithPlace() {
        let activity = TestData.tripActivityResponse(activityType: "log_added", placeName: "Blue Bottle Coffee")
        let subtitle = FeedService.activitySubtitle(for: activity)
        #expect(subtitle == "added Blue Bottle Coffee")
    }

    @Test func activitySubtitle_logAddedWithoutPlace() {
        let activity = TestData.tripActivityResponse(activityType: "log_added", placeName: nil)
        let subtitle = FeedService.activitySubtitle(for: activity)
        #expect(subtitle == "added a new stop")
    }

    @Test func activitySubtitle_logAddedEmptyPlace() {
        let activity = TestData.tripActivityResponse(activityType: "log_added", placeName: "")
        let subtitle = FeedService.activitySubtitle(for: activity)
        #expect(subtitle == "added a new stop")
    }

    @Test func activitySubtitle_tripCreated() {
        let activity = TestData.tripActivityResponse(activityType: "trip_created", logID: nil, placeName: nil)
        let subtitle = FeedService.activitySubtitle(for: activity)
        #expect(subtitle == "started this trip")
    }

    @Test func activitySubtitle_unknownFallback() {
        let activity = TestData.tripActivityResponse(activityType: "unknown", logID: nil, placeName: nil)
        let subtitle = FeedService.activitySubtitle(for: activity)
        #expect(subtitle == "trip")
    }

    // MARK: - FeedEntry with tripCreated

    @Test func feedEntry_tripCreated_id() {
        let item = TestData.feedTripCreatedItem(id: "act-1")
        let entry = FeedEntry.tripCreated(item)
        #expect(entry.id == "tripCreated-act-1")
    }

    @Test func feedEntry_tripCreated_sortDate() {
        let date = fixedDate()
        let item = TestData.feedTripCreatedItem(createdAt: date)
        let entry = FeedEntry.tripCreated(item)
        #expect(entry.sortDate == date)
    }

    // MARK: - FeedTripItem activitySubtitle

    @Test func feedTripItem_activitySubtitle() {
        let item = TestData.feedTripItem(activitySubtitle: "added Blue Bottle Coffee")
        #expect(item.activitySubtitle == "added Blue Bottle Coffee")
    }

    // MARK: - TripActivityResponse Codable

    @Test func tripActivityResponseCodableSnakeCase() throws {
        let response = TestData.tripActivityResponse(
            tripID: "trip-123",
            activityType: "log_added",
            logID: "log-456",
            placeName: "Cafe"
        )
        let data = try makeEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["trip_id"] as? String == "trip-123")
        #expect(json["activity_type"] as? String == "log_added")
        #expect(json["log_id"] as? String == "log-456")
        #expect(json["place_name"] as? String == "Cafe")
        #expect(json["tripID"] == nil)
        #expect(json["activityType"] == nil)
    }

    @Test func feedUserCodableSnakeCase() throws {
        let user = TestData.feedUser(avatarURL: "https://example.com/avatar.jpg")
        let data = try makeEncoder().encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["avatar_url"] != nil)
        #expect(json["is_public"] != nil)
        #expect(json["avatarURL"] == nil)
        #expect(json["isPublic"] == nil)
    }
}
