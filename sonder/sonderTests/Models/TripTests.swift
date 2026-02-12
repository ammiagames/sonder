import Testing
import Foundation
@testable import sonder

struct TripTests {

    @Test func initDefaults() {
        let trip = Trip(name: "My Trip", createdBy: "u1")

        #expect(!trip.id.isEmpty)
        #expect(trip.collaboratorIDs == [])
        #expect(trip.tripDescription == nil)
        #expect(trip.coverPhotoURL == nil)
        #expect(trip.startDate == nil)
        #expect(trip.endDate == nil)
    }

    @Test func encodeThenDecode() throws {
        let trip = TestData.trip(
            id: "trip-1",
            name: "Europe Trip",
            tripDescription: "Summer vacation",
            coverPhotoURL: "https://example.com/cover.jpg",
            startDate: fixedDate(),
            endDate: fixedDate(),
            collaboratorIDs: ["u2", "u3"],
            createdBy: "u1"
        )

        let data = try makeEncoder().encode(trip)
        let decoded = try makeDecoder().decode(Trip.self, from: data)

        #expect(decoded.id == trip.id)
        #expect(decoded.name == trip.name)
        #expect(decoded.tripDescription == "Summer vacation")
        #expect(decoded.coverPhotoURL == trip.coverPhotoURL)
        #expect(decoded.collaboratorIDs == ["u2", "u3"])
        #expect(decoded.createdBy == "u1")
    }

    @Test func tripDescriptionMapsToDescription() throws {
        let trip = TestData.trip(tripDescription: "A fun trip")
        let data = try makeEncoder().encode(trip)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["description"] as? String == "A fun trip")
        #expect(json["tripDescription"] == nil)
    }

    @Test func collaboratorIDsEncoding() throws {
        let trip = TestData.trip(collaboratorIDs: ["u2", "u3"])
        let data = try makeEncoder().encode(trip)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["collaborator_ids"] != nil)
        #expect(json["collaboratorIDs"] == nil)
        let ids = json["collaborator_ids"] as? [String]
        #expect(ids == ["u2", "u3"])
    }

    @Test func decodeMissingOptionals() throws {
        let json = """
        {
            "id": "trip-2",
            "name": "Quick Trip",
            "created_by": "u1",
            "created_at": "2025-01-15T12:00:00Z",
            "updated_at": "2025-01-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let trip = try makeDecoder().decode(Trip.self, from: json)

        #expect(trip.startDate == nil)
        #expect(trip.endDate == nil)
        #expect(trip.tripDescription == nil)
        #expect(trip.coverPhotoURL == nil)
        #expect(trip.collaboratorIDs == [])
    }
}
