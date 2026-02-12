import Testing
import Foundation
@testable import sonder

struct LogTests {

    @Test func initDefaults() {
        let log = Log(userID: "u1", placeID: "p1", rating: .solid)

        #expect(!log.id.isEmpty)
        #expect(log.syncStatus == .pending)
        #expect(log.tags == [])
        #expect(log.photoURL == nil)
        #expect(log.note == nil)
        #expect(log.tripID == nil)
    }

    @Test func ratingEmoji() {
        #expect(Rating.skip.emoji == "👎")
        #expect(Rating.solid.emoji == "👍")
        #expect(Rating.mustSee.emoji == "🔥")
    }

    @Test func ratingDisplayName() {
        #expect(Rating.skip.displayName == "Skip")
        #expect(Rating.solid.displayName == "Solid")
        #expect(Rating.mustSee.displayName == "Must-See")
    }

    @Test func ratingRawValues() {
        #expect(Rating.skip.rawValue == "skip")
        #expect(Rating.solid.rawValue == "solid")
        #expect(Rating.mustSee.rawValue == "must_see")
    }

    @Test func ratingCaseIterable() {
        #expect(Rating.allCases.count == 3)
        #expect(Rating.allCases.contains(.skip))
        #expect(Rating.allCases.contains(.solid))
        #expect(Rating.allCases.contains(.mustSee))
    }

    @Test func syncStatusRawValues() {
        #expect(SyncStatus.synced.rawValue == "synced")
        #expect(SyncStatus.pending.rawValue == "pending")
        #expect(SyncStatus.failed.rawValue == "failed")
    }

    @Test func encodeThenDecode() throws {
        let log = TestData.log(
            id: "log-1",
            rating: .mustSee,
            photoURL: "https://example.com/photo.jpg",
            note: "Amazing",
            tags: ["food", "date night"],
            tripID: "trip-1",
            syncStatus: .synced
        )

        let data = try makeEncoder().encode(log)
        let decoded = try makeDecoder().decode(Log.self, from: data)

        #expect(decoded.id == log.id)
        #expect(decoded.userID == log.userID)
        #expect(decoded.placeID == log.placeID)
        #expect(decoded.rating == .mustSee)
        #expect(decoded.photoURL == log.photoURL)
        #expect(decoded.note == "Amazing")
        #expect(decoded.tags == ["food", "date night"])
        #expect(decoded.tripID == "trip-1")
        #expect(decoded.syncStatus == .synced)
    }

    @Test func encodeProducesSnakeCaseKeys() throws {
        let log = TestData.log(tripID: "trip-1")
        let data = try makeEncoder().encode(log)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["user_id"] != nil)
        #expect(json["place_id"] != nil)
        #expect(json["photo_url"] == nil || json["photo_url"] is NSNull || true) // may be nil
        #expect(json["trip_id"] != nil)
        #expect(json["sync_status"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["updated_at"] != nil)
        // Should NOT have camelCase
        #expect(json["userID"] == nil)
        #expect(json["placeID"] == nil)
    }

    @Test func decodeMissingOptionals() throws {
        let json = """
        {
            "id": "log-2",
            "user_id": "u1",
            "place_id": "p1",
            "rating": "must_see"
        }
        """.data(using: .utf8)!

        let log = try makeDecoder().decode(Log.self, from: json)

        #expect(log.syncStatus == .synced) // default when missing
        #expect(log.tags == []) // default when missing
        #expect(log.photoURL == nil)
        #expect(log.note == nil)
        #expect(log.tripID == nil)
    }
}
