import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct TripCoverPhotoTests {

    // MARK: - Model persistence

    @Test func coverPhotoURL_persistsInSwiftData() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let trip = TestData.trip(
            id: "trip-1",
            name: "Japan Trip",
            coverPhotoURL: "https://example.com/cover.jpg",
            createdBy: "u1"
        )
        context.insert(trip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>()).first
        #expect(fetched?.coverPhotoURL == "https://example.com/cover.jpg")
    }

    @Test func coverPhotoURL_updatable() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let trip = TestData.trip(id: "trip-1", name: "Trip", createdBy: "u1")
        context.insert(trip)
        try context.save()

        // Initially nil
        #expect(trip.coverPhotoURL == nil)

        // Set cover photo
        trip.coverPhotoURL = "https://example.com/new-cover.jpg"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>()).first
        #expect(fetched?.coverPhotoURL == "https://example.com/new-cover.jpg")
    }

    @Test func coverPhotoURL_removable() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let trip = TestData.trip(
            id: "trip-1",
            name: "Trip",
            coverPhotoURL: "https://example.com/cover.jpg",
            createdBy: "u1"
        )
        context.insert(trip)
        try context.save()

        // Remove cover photo
        trip.coverPhotoURL = nil
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>()).first
        #expect(fetched?.coverPhotoURL == nil)
    }

    @Test func coverPhotoURL_replaceable() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let trip = TestData.trip(
            id: "trip-1",
            name: "Trip",
            coverPhotoURL: "https://example.com/old.jpg",
            createdBy: "u1"
        )
        context.insert(trip)
        try context.save()

        // Replace with new URL
        trip.coverPhotoURL = "https://example.com/new.jpg"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>()).first
        #expect(fetched?.coverPhotoURL == "https://example.com/new.jpg")
    }

    // MARK: - Encoding

    @Test func coverPhotoURL_encodesToSnakeCase() throws {
        let trip = TestData.trip(coverPhotoURL: "https://example.com/cover.jpg")
        let data = try makeEncoder().encode(trip)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["cover_photo_url"] as? String == "https://example.com/cover.jpg")
        #expect(json["coverPhotoURL"] == nil)
    }

    @Test func coverPhotoURL_decodesFromSnakeCase() throws {
        let json = """
        {
            "id": "trip-1",
            "name": "Trip",
            "cover_photo_url": "https://example.com/decoded.jpg",
            "created_by": "u1",
            "created_at": "2025-01-15T12:00:00Z",
            "updated_at": "2025-01-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let trip = try makeDecoder().decode(Trip.self, from: json)
        #expect(trip.coverPhotoURL == "https://example.com/decoded.jpg")
    }

    @Test func coverPhotoURL_nilWhenMissingFromJSON() throws {
        let json = """
        {
            "id": "trip-1",
            "name": "Trip",
            "created_by": "u1",
            "created_at": "2025-01-15T12:00:00Z",
            "updated_at": "2025-01-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let trip = try makeDecoder().decode(Trip.self, from: json)
        #expect(trip.coverPhotoURL == nil)
    }
}
