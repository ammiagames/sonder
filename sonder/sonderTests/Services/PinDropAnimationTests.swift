import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct PinDropAnimationTests {

    // MARK: - Helpers

    private func makePersonalPin(
        placeID: String,
        latitude: Double,
        longitude: Double
    ) throws -> UnifiedMapPin {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let place = TestData.place(
            id: placeID,
            name: "Place \(placeID)",
            latitude: latitude,
            longitude: longitude
        )
        let log = TestData.log(placeID: placeID, rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()
        return .personal(logs: [LogSnapshot(from: log)], place: place)
    }

    // MARK: - findPinByProximity

    @Test func findPinByProximity_exactMatch() throws {
        let pin = try makePersonalPin(placeID: "p1", latitude: 37.7749, longitude: -122.4194)
        let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let result = ExploreMapService.findPinByProximity(coordinate: coord, in: [pin])

        #expect(result?.placeID == "p1")
    }

    @Test func findPinByProximity_closeMatch() throws {
        let pin = try makePersonalPin(placeID: "p1", latitude: 37.7749, longitude: -122.4194)
        // ~30m offset (well within default 0.0005 threshold ≈ 55m)
        let coord = CLLocationCoordinate2D(latitude: 37.77503, longitude: -122.41955)

        let result = ExploreMapService.findPinByProximity(coordinate: coord, in: [pin])

        #expect(result?.placeID == "p1")
    }

    @Test func findPinByProximity_noMatch_farCoordinate() throws {
        let pin = try makePersonalPin(placeID: "p1", latitude: 37.7749, longitude: -122.4194)
        // ~1km away — well beyond the 0.0005 threshold
        let coord = CLLocationCoordinate2D(latitude: 37.784, longitude: -122.410)

        let result = ExploreMapService.findPinByProximity(coordinate: coord, in: [pin])

        #expect(result == nil)
    }

    @Test func findPinByProximity_closestWins() throws {
        let pinA = try makePersonalPin(placeID: "pA", latitude: 37.7749, longitude: -122.4194)
        let pinB = try makePersonalPin(placeID: "pB", latitude: 37.77495, longitude: -122.41945)
        let coord = CLLocationCoordinate2D(latitude: 37.77496, longitude: -122.41946)

        let result = ExploreMapService.findPinByProximity(coordinate: coord, in: [pinA, pinB])

        #expect(result?.placeID == "pB")
    }

    @Test func findPinByProximity_emptyPins() {
        let coord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let result = ExploreMapService.findPinByProximity(coordinate: coord, in: [])

        #expect(result == nil)
    }

    // MARK: - Pending Upload URL Edge Case

    @Test func pendingUploadURL_isNotHTTP() {
        let pendingURL = "pending-upload:\(UUID().uuidString)"

        // "pending-upload:UUID" parses as a URL (scheme = "pending-upload"),
        // but it's not an HTTP(S) URL so AsyncImage won't load it.
        // The pin falls back to Google Places photo or emoji.
        let url = URL(string: pendingURL)
        #expect(url != nil) // it does parse
        #expect(url?.scheme == "pending-upload") // non-http scheme
        #expect(url?.host == nil) // no host → AsyncImage fails gracefully
    }
}
