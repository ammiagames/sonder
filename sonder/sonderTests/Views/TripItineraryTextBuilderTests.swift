import Testing
import Foundation
import CoreLocation
import UIKit
@testable import sonder

struct TripItineraryTextBuilderTests {

    // MARK: - Helpers

    private func makeStop(
        name: String = "Test Place",
        address: String = "",
        rating: Rating = .great,
        placeID: String = "",
        note: String? = nil,
        tags: [String] = []
    ) -> ExportStop {
        ExportStop(
            placeName: name,
            address: address,
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            rating: rating,
            placeID: placeID,
            note: note,
            tags: tags
        )
    }

    private func makeData(
        tripName: String = "Tokyo 2026",
        dateRangeText: String? = "Feb 10–17",
        stops: [ExportStop] = []
    ) -> TripExportData {
        TripExportData(
            tripName: tripName,
            tripDescription: nil,
            dateRangeText: dateRangeText,
            placeCount: stops.count,
            dayCount: 7,
            ratingCounts: (mustSee: 0, great: 0, okay: 0, skip: 0),
            topTags: [],
            heroImage: nil,
            logPhotos: [],
            stops: stops
        )
    }

    // MARK: - Tests

    @Test func headerIncludesTripNameDateAndStopCount() {
        let data = makeData(tripName: "Tokyo 2026", dateRangeText: "Feb 10–17", stops: [
            makeStop(name: "Place A"),
            makeStop(name: "Place B"),
        ])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(text.contains("Tokyo 2026"))
        #expect(text.contains("Feb 10–17"))
        #expect(text.contains("2 stops"))
    }

    @Test func headerOmitsDateWhenNil() {
        let data = makeData(dateRangeText: nil, stops: [makeStop()])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(!text.contains("Feb"))
        #expect(text.contains("1 stops"))
    }

    @Test func emptyStopsProducesHeaderOnly() {
        let data = makeData(stops: [])
        let text = TripItineraryTextBuilder.buildText(from: data)
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
        #expect(lines[0].contains("Tokyo 2026"))
    }

    @Test func fullStopRendersAllFields() {
        let stop = makeStop(
            name: "Tsukiji Outer Market",
            address: "4-16-2 Tsukiji, Chuo City",
            rating: .mustSee,
            placeID: "ChIJabc123",
            note: "Best tuna bowl I've ever had",
            tags: ["sushi", "seafood"]
        )
        let data = makeData(stops: [stop])
        let text = TripItineraryTextBuilder.buildText(from: data)

        #expect(text.contains("1. \(Rating.mustSee.emoji) Tsukiji Outer Market"))
        #expect(text.contains("4-16-2 Tsukiji, Chuo City"))
        #expect(text.contains("Best tuna bowl"))
        #expect(text.contains("#sushi #seafood"))
        #expect(text.contains("place_id:ChIJabc123"))
    }

    @Test func skipsEmptyAddress() {
        let stop = makeStop(name: "Place", address: "")
        let data = makeData(stops: [stop])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(!text.contains("\u{1F4CD}"))
    }

    @Test func skipsEmptyNote() {
        let stop = makeStop(name: "Place", note: nil)
        let data = makeData(stops: [stop])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(!text.contains("\u{201C}"))
    }

    @Test func skipsEmptyTags() {
        let stop = makeStop(name: "Place", tags: [])
        let data = makeData(stops: [stop])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(!text.contains("#"))
    }

    @Test func skipsEmptyPlaceID() {
        let stop = makeStop(name: "Place", placeID: "")
        let data = makeData(stops: [stop])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(!text.contains("google.com"))
    }

    @Test func googleMapsLinkFormat() {
        let stop = makeStop(placeID: "ChIJxyz789")
        let data = makeData(stops: [stop])
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(text.contains("https://www.google.com/maps/place/?q=place_id:ChIJxyz789"))
    }

    @Test func multipleStopsNumberedSequentially() {
        let stops = [
            makeStop(name: "First", rating: .mustSee),
            makeStop(name: "Second", rating: .great),
            makeStop(name: "Third", rating: .okay),
        ]
        let data = makeData(stops: stops)
        let text = TripItineraryTextBuilder.buildText(from: data)

        #expect(text.contains("1. \(Rating.mustSee.emoji) First"))
        #expect(text.contains("2. \(Rating.great.emoji) Second"))
        #expect(text.contains("3. \(Rating.okay.emoji) Third"))
    }

    @Test func allStopsIncludedNoTruncation() {
        let stops = (1...30).map { i in
            makeStop(name: "Place \(i)")
        }
        let data = makeData(stops: stops)
        let text = TripItineraryTextBuilder.buildText(from: data)
        #expect(text.contains("30. "))
        #expect(!text.contains("more"))
    }
}
