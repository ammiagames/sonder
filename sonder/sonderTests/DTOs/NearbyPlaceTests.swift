import Testing
import Foundation
@testable import sonder

struct NearbyPlaceTests {

    @Test func idEqualsPlaceId() {
        let nearby = TestData.nearbyPlace(placeId: "nearby-abc")

        #expect(nearby.id == nearby.placeId)
        #expect(nearby.id == "nearby-abc")
    }
}
