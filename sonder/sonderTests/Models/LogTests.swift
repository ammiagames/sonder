import Testing
import Foundation
@testable import sonder

struct LogTests {

    @Test func initDefaults() {
        let log = Log(userID: "u1", placeID: "p1", rating: .okay)

        #expect(!log.id.isEmpty)
        #expect(log.syncStatus == .pending)
        #expect(log.tags == [])
        #expect(log.photoURLs == [])
        #expect(log.photoURL == nil)
        #expect(log.note == nil)
        #expect(log.tripID == nil)
    }

    @Test func ratingEmoji() {
        #expect(Rating.skip.emoji == "👎")
        #expect(Rating.okay.emoji == "👌")
        #expect(Rating.great.emoji == "⭐")
        #expect(Rating.mustSee.emoji == "🔥")
    }

    @Test func ratingDisplayName() {
        #expect(Rating.skip.displayName == "Skip")
        #expect(Rating.okay.displayName == "Okay")
        #expect(Rating.great.displayName == "Great")
        #expect(Rating.mustSee.displayName == "Must-See")
    }

    @Test func ratingRawValues() {
        #expect(Rating.skip.rawValue == "skip")
        #expect(Rating.okay.rawValue == "okay")
        #expect(Rating.great.rawValue == "great")
        #expect(Rating.mustSee.rawValue == "must_see")
    }

    @Test func ratingCaseIterable() {
        #expect(Rating.allCases.count == 4)
        #expect(Rating.allCases.contains(.skip))
        #expect(Rating.allCases.contains(.okay))
        #expect(Rating.allCases.contains(.great))
        #expect(Rating.allCases.contains(.mustSee))
    }

    @Test func legacySolidDecodesAsOkay() throws {
        let json = """
        {
            "id": "log-legacy-solid",
            "user_id": "u1",
            "place_id": "p1",
            "rating": "solid"
        }
        """.data(using: .utf8)!

        let log = try makeDecoder().decode(Log.self, from: json)
        #expect(log.rating == .okay)
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
            photoURLs: ["https://example.com/photo.jpg"],
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
        #expect(decoded.photoURLs == ["https://example.com/photo.jpg"])
        #expect(decoded.photoURL == "https://example.com/photo.jpg")
        #expect(decoded.note == "Amazing")
        #expect(decoded.tags == ["food", "date night"])
        #expect(decoded.tripID == "trip-1")
        #expect(decoded.syncStatus == .synced)
    }

    @Test func multiplePhotoURLsEncodeDecode() throws {
        let urls = ["https://example.com/1.jpg", "https://example.com/2.jpg", "https://example.com/3.jpg"]
        let log = TestData.log(id: "log-multi", photoURLs: urls)

        let data = try makeEncoder().encode(log)
        let decoded = try makeDecoder().decode(Log.self, from: data)

        #expect(decoded.photoURLs == urls)
        #expect(decoded.photoURL == urls.first)
    }

    @Test func emptyPhotoURLsEncodesAsEmptyArray() throws {
        let log = TestData.log(id: "log-empty")

        let data = try makeEncoder().encode(log)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let photoUrls = json["photo_urls"] as? [String]
        #expect(photoUrls == [])
    }

    @Test func decoderFallsBackFromSinglePhotoURL() throws {
        // Simulates old format with single photo_url string
        let json = """
        {
            "id": "log-legacy",
            "user_id": "u1",
            "place_id": "p1",
            "rating": "solid",
            "photo_url": "https://example.com/old.jpg"
        }
        """.data(using: .utf8)!

        let log = try makeDecoder().decode(Log.self, from: json)

        #expect(log.photoURLs == ["https://example.com/old.jpg"])
        #expect(log.photoURL == "https://example.com/old.jpg")
    }

    @Test func encodeProducesSnakeCaseKeys() throws {
        let log = TestData.log(tripID: "trip-1")
        let data = try makeEncoder().encode(log)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["user_id"] != nil)
        #expect(json["place_id"] != nil)
        #expect(json["photo_urls"] != nil)
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
        #expect(log.photoURLs == [])
        #expect(log.photoURL == nil)
        #expect(log.note == nil)
        #expect(log.tripID == nil)
    }
}
