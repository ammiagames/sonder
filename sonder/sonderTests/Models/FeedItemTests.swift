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
