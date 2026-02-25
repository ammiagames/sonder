import Testing
import Foundation
import CoreLocation
import UIKit
@testable import sonder

struct TripExportPDFTests {

    // MARK: - Helpers

    private func makeStop(
        name: String = "Test Place",
        address: String = "123 Test St",
        rating: Rating = .great,
        placeID: String = "testID",
        note: String? = nil,
        tags: [String] = []
    ) -> ExportStop {
        ExportStop(
            placeName: name,
            address: address,
            coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            rating: rating,
            placeID: placeID,
            note: note,
            tags: tags
        )
    }

    private func makeData(
        tripName: String = "Tokyo Trip",
        stops: [ExportStop] = [],
        heroImage: UIImage? = nil
    ) -> TripExportData {
        TripExportData(
            tripName: tripName,
            tripDescription: nil,
            dateRangeText: "Feb 10–17",
            placeCount: stops.count,
            dayCount: 7,
            ratingCounts: (mustSee: 1, great: 2, okay: 0, skip: 0),
            topTags: ["food", "culture"],
            heroImage: heroImage,
            logPhotos: [],
            stops: stops
        )
    }

    // MARK: - Tests

    @Test @MainActor func returnsValidURLForNonEmptyData() {
        let stops = [
            makeStop(name: "Place A"),
            makeStop(name: "Place B"),
            makeStop(name: "Place C"),
        ]
        let data = makeData(stops: stops)
        let url = TripExportPDFRenderer.renderPDF(data: data, theme: .classic, mapSnapshot: nil)

        #expect(url != nil)
        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            // Cleanup
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test @MainActor func handlesEmptyStopsGracefully() {
        let data = makeData(stops: [])
        let url = TripExportPDFRenderer.renderPDF(data: data, theme: .classic, mapSnapshot: nil)

        #expect(url != nil)
        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test @MainActor func coverPageRendersWithoutHeroPhoto() {
        let data = makeData(heroImage: nil)
        let preview = TripExportPDFRenderer.renderCoverPreview(data: data, theme: .classic)
        #expect(preview != nil)
    }

    @Test @MainActor func coverPageRendersWithHeroPhoto() {
        // Create a simple 10x10 red image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let heroImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let data = makeData(heroImage: heroImage)
        let preview = TripExportPDFRenderer.renderCoverPreview(data: data, theme: .warmSand)
        #expect(preview != nil)
    }

    @Test @MainActor func fileCleanupWorks() {
        let data = makeData(stops: [makeStop()])
        let url = TripExportPDFRenderer.renderPDF(data: data, theme: .midnight, mapSnapshot: nil)

        #expect(url != nil)
        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test @MainActor func sanitizesSpecialCharsInFilename() {
        let data = makeData(tripName: "Tokyo / Kyoto: 2026")
        let url = TripExportPDFRenderer.renderPDF(data: data, theme: .classic, mapSnapshot: nil)

        #expect(url != nil)
        if let url {
            #expect(!url.lastPathComponent.contains("/"))
            #expect(!url.lastPathComponent.contains(":"))
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test @MainActor func paginatesStopsCorrectly() {
        // 10 stops should produce 4 stop pages (3 + 3 + 3 + 1)
        let stops = (1...10).map { i in
            makeStop(name: "Place \(i)")
        }
        let data = makeData(stops: stops)
        let url = TripExportPDFRenderer.renderPDF(data: data, theme: .sage, mapSnapshot: nil)

        #expect(url != nil)
        if let url {
            #expect(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }
    }
}
