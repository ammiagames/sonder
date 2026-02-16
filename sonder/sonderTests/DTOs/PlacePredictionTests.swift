import Testing
import Foundation
@testable import sonder

struct PlacePredictionTests {

    @Test func idEqualsPlaceId() {
        let prediction = PlacePrediction(
            placeId: "ChIJ123",
            mainText: "Central Park",
            secondaryText: "New York, NY",
            distanceMeters: nil
        )

        #expect(prediction.id == prediction.placeId)
        #expect(prediction.id == "ChIJ123")
    }

    @Test func descriptionFormat() {
        let prediction = PlacePrediction(
            placeId: "ChIJ456",
            mainText: "Times Square",
            secondaryText: "Manhattan, NY",
            distanceMeters: nil
        )

        #expect(prediction.description == "Times Square, Manhattan, NY")
    }
}
