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
            photoURL: "https://example.com/photo.jpg",
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
        #expect(feedItem.log.photoURL == "https://example.com/photo.jpg")
        #expect(feedItem.log.note == "Amazing")
        #expect(feedItem.log.tags == ["food"])
        #expect(feedItem.user.id == "u1")
        #expect(feedItem.user.username == "alice")
        #expect(feedItem.place.id == "p1")
        #expect(feedItem.place.name == "Cafe")
    }

    @Test func feedLogCodableSnakeCase() throws {
        let log = TestData.feedLog(photoURL: "https://example.com/pic.jpg")
        let data = try makeEncoder().encode(log)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["photo_url"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["photoURL"] == nil)
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
