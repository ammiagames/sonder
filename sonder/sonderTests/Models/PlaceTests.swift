import Testing
import Foundation
import CoreLocation
@testable import sonder

struct PlaceTests {

    @Test func initDefaults() {
        let place = Place(
            id: "p-1",
            name: "Cafe",
            address: "100 Main St",
            latitude: 40.0,
            longitude: -74.0
        )

        #expect(place.types == [])
        #expect(place.photoReference == nil)
    }

    @Test func coordinateComputedProperty() {
        let place = TestData.place(latitude: 37.7749, longitude: -122.4194)
        let coord = place.coordinate

        #expect(coord.latitude == 37.7749)
        #expect(coord.longitude == -122.4194)
    }

    @Test func encodeThenDecode() throws {
        let place = TestData.place(
            types: ["restaurant", "cafe"],
            photoReference: "photo-ref-abc"
        )

        let data = try makeEncoder().encode(place)
        let decoded = try makeDecoder().decode(Place.self, from: data)

        #expect(decoded.id == place.id)
        #expect(decoded.name == place.name)
        #expect(decoded.address == place.address)
        #expect(decoded.latitude == place.latitude)
        #expect(decoded.longitude == place.longitude)
        #expect(decoded.types == place.types)
        #expect(decoded.photoReference == place.photoReference)
    }

    @Test func encodeUsesLatLngKeys() throws {
        let place = TestData.place(photoReference: "ref")
        let data = try makeEncoder().encode(place)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["lat"] != nil)
        #expect(json["lng"] != nil)
        #expect(json["photo_reference"] != nil)
        // Should NOT have original property names
        #expect(json["latitude"] == nil)
        #expect(json["longitude"] == nil)
        #expect(json["photoReference"] == nil)
    }

    @Test func decodeFromSupabaseJSON() throws {
        let json = """
        {
            "id": "p-2",
            "name": "Bakery",
            "address": "200 Elm St",
            "lat": 41.0,
            "lng": -73.5,
            "types": ["bakery"],
            "photo_reference": "ref-xyz",
            "created_at": "2025-01-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let place = try makeDecoder().decode(Place.self, from: json)

        #expect(place.id == "p-2")
        #expect(place.name == "Bakery")
        #expect(place.latitude == 41.0)
        #expect(place.longitude == -73.5)
        #expect(place.photoReference == "ref-xyz")
    }
}
