import Testing
import Foundation
import CoreLocation
import UIKit
@testable import sonder

struct ExportAspectRatioTests {

    @Test func storiesHasCorrectDimensions() {
        let ratio = ExportAspectRatio.stories
        #expect(ratio.width == 1080)
        #expect(ratio.height == 1920)
        #expect(ratio.size == CGSize(width: 1080, height: 1920))
    }

    @Test func feedHasCorrectDimensions() {
        let ratio = ExportAspectRatio.feed
        #expect(ratio.width == 1080)
        #expect(ratio.height == 1350)
        #expect(ratio.size == CGSize(width: 1080, height: 1350))
    }

    @Test func squareHasCorrectDimensions() {
        let ratio = ExportAspectRatio.square
        #expect(ratio.width == 1080)
        #expect(ratio.height == 1080)
        #expect(ratio.size == CGSize(width: 1080, height: 1080))
    }

    @Test func allCasesHasThreeRatios() {
        #expect(ExportAspectRatio.allCases.count == 3)
    }

    @Test func eachRatioHasTitleAndIcon() {
        for ratio in ExportAspectRatio.allCases {
            #expect(!ratio.title.isEmpty)
            #expect(!ratio.icon.isEmpty)
        }
    }

    @Test func idMatchesRawValue() {
        for ratio in ExportAspectRatio.allCases {
            #expect(ratio.id == ratio.rawValue)
        }
    }
}

struct ExportColorThemeTests {

    @Test func allThemesHasFiveEntries() {
        #expect(ExportColorTheme.allThemes.count == 5)
    }

    @Test func eachThemeHasUniqueID() {
        let ids = ExportColorTheme.allThemes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func eachThemeHasThreePreviewColors() {
        for theme in ExportColorTheme.allThemes {
            #expect(theme.previewColors.count == 3)
        }
    }

    @Test func eachThemeHasNonEmptyName() {
        for theme in ExportColorTheme.allThemes {
            #expect(!theme.name.isEmpty)
        }
    }

    @Test func overlayGradientHasFourStops() {
        for theme in ExportColorTheme.allThemes {
            #expect(theme.overlayGradient.count == 4)
        }
    }

    @Test func classicIsDefault() {
        let customization = TripExportCustomization()
        #expect(customization.theme == .classic)
    }

    @Test func equalityComparesById() {
        let a = ExportColorTheme.classic
        let b = ExportColorTheme.midnight
        #expect(a == a)
        #expect(a != b)
    }

    @Test func staticThemeAccessors() {
        #expect(ExportColorTheme.classic.id == "classic")
        #expect(ExportColorTheme.warmSand.id == "warmSand")
        #expect(ExportColorTheme.midnight.id == "midnight")
        #expect(ExportColorTheme.sage.id == "sage")
        #expect(ExportColorTheme.dustyRose.id == "dustyRose")
    }
}

struct TripExportCustomizationTests {

    @Test func defaultValues() {
        let c = TripExportCustomization()
        #expect(c.theme == .classic)
        #expect(c.aspectRatio == .stories)
        #expect(c.customCaption == "")
        #expect(c.selectedHeroPhotoIndex == 0)
        #expect(c.selectedLogPhotoIndices.isEmpty)
    }

    @Test func canvasSizeDelegatesToAspectRatio() {
        var c = TripExportCustomization()
        c.aspectRatio = .feed
        #expect(c.canvasSize == CGSize(width: 1080, height: 1350))

        c.aspectRatio = .square
        #expect(c.canvasSize == CGSize(width: 1080, height: 1080))

        c.aspectRatio = .stories
        #expect(c.canvasSize == CGSize(width: 1080, height: 1920))
    }

    @Test func equatable() {
        var a = TripExportCustomization()
        var b = TripExportCustomization()
        #expect(a == b)

        a.customCaption = "Hello"
        #expect(a != b)

        b.customCaption = "Hello"
        #expect(a == b)

        a.theme = .midnight
        #expect(a != b)
    }

    @Test func selectedLogPhotoIndicesMutation() {
        var c = TripExportCustomization()
        c.selectedLogPhotoIndices = [0, 2, 4]
        #expect(c.selectedLogPhotoIndices.count == 3)
        #expect(c.selectedLogPhotoIndices.contains(2))

        c.selectedLogPhotoIndices.remove(2)
        #expect(c.selectedLogPhotoIndices.count == 2)
        #expect(!c.selectedLogPhotoIndices.contains(2))
    }
}

struct ExportStyleTests {

    @Test func allCasesHasFourStyles() {
        #expect(ExportStyle.allCases.count == 4)
    }

    @Test func eachStyleHasTitleAndIcon() {
        for style in ExportStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(!style.icon.isEmpty)
        }
    }

    @Test func rawValues() {
        #expect(ExportStyle.cover.rawValue == "cover")
        #expect(ExportStyle.route.rawValue == "route")
        #expect(ExportStyle.journey.rawValue == "journey")
        #expect(ExportStyle.collage.rawValue == "collage")
    }
}

struct TripExportDataTests {

    @Test func customCaptionDefaultsToNil() {
        let data = TripExportData(
            tripName: "Test",
            tripDescription: nil,
            dateRangeText: nil,
            placeCount: 3,
            dayCount: 2,
            ratingCounts: (mustSee: 1, solid: 1, skip: 1),
            topTags: [],
            heroImage: nil,
            logPhotos: [],
            stops: []
        )
        #expect(data.customCaption == nil)
        #expect(data.allAvailablePhotos.isEmpty)
        #expect(data.allHeroImages.isEmpty)
    }

    @Test func mutableFieldsCanBeSet() {
        var data = TripExportData(
            tripName: "Trip",
            tripDescription: nil,
            dateRangeText: nil,
            placeCount: 0,
            dayCount: 1,
            ratingCounts: (mustSee: 0, solid: 0, skip: 0),
            topTags: [],
            heroImage: nil,
            logPhotos: [],
            stops: []
        )

        data.customCaption = "My caption"
        #expect(data.customCaption == "My caption")

        data.customCaption = nil
        #expect(data.customCaption == nil)
    }

    @Test func exportStopStoresCoordinate() {
        let coord = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        let stop = ExportStop(placeName: "Eiffel Tower", coordinate: coord, rating: .mustSee)
        #expect(stop.placeName == "Eiffel Tower")
        #expect(stop.coordinate.latitude == 48.8566)
        #expect(stop.coordinate.longitude == 2.3522)
        #expect(stop.rating == .mustSee)
    }

    @Test func exportStopStoresNoteAndTags() {
        let coord = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let stop = ExportStop(
            placeName: "Ichiran Ramen",
            coordinate: coord,
            rating: .mustSee,
            placeID: "place123",
            note: "Best ramen ever",
            tags: ["ramen", "must-try"]
        )
        #expect(stop.note == "Best ramen ever")
        #expect(stop.tags == ["ramen", "must-try"])
    }

    @Test func exportStopDefaultsNoteAndTagsToEmpty() {
        let coord = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let stop = ExportStop(placeName: "Test", coordinate: coord, rating: .solid)
        #expect(stop.note == nil)
        #expect(stop.tags.isEmpty)
    }

    @Test func logPhotoDataStoresNoteAndTags() {
        let image = UIImage()
        let photo = LogPhotoData(
            image: image,
            placeName: "Shibuya",
            rating: .solid,
            placeID: "abc",
            note: "Iconic crossing",
            tags: ["nightlife", "iconic"]
        )
        #expect(photo.note == "Iconic crossing")
        #expect(photo.tags == ["nightlife", "iconic"])
    }

    @Test func logPhotoDataDefaultsNoteAndTagsToEmpty() {
        let image = UIImage()
        let photo = LogPhotoData(image: image, placeName: "Test", rating: .skip)
        #expect(photo.note == nil)
        #expect(photo.tags.isEmpty)
    }

    @Test func categoryBreakdownAndBestQuoteDefaults() {
        let data = TripExportData(
            tripName: "Test",
            tripDescription: nil,
            dateRangeText: nil,
            placeCount: 1,
            dayCount: 1,
            ratingCounts: (mustSee: 1, solid: 0, skip: 0),
            topTags: [],
            heroImage: nil,
            logPhotos: [],
            stops: []
        )
        #expect(data.categoryBreakdown.isEmpty)
        #expect(data.bestQuote == nil)
    }

    @Test func categoryBreakdownCanBeSet() {
        var data = TripExportData(
            tripName: "Tokyo",
            tripDescription: nil,
            dateRangeText: nil,
            placeCount: 5,
            dayCount: 3,
            ratingCounts: (mustSee: 2, solid: 2, skip: 1),
            topTags: [],
            heroImage: nil,
            logPhotos: [],
            stops: [],
            categoryBreakdown: [
                (emoji: "🍴", label: "Food", count: 3),
                (emoji: "☕", label: "Coffee", count: 2)
            ],
            bestQuote: (text: "Best ramen ever", placeName: "Ichiran")
        )
        #expect(data.categoryBreakdown.count == 2)
        #expect(data.categoryBreakdown[0].emoji == "🍴")
        #expect(data.categoryBreakdown[0].label == "Food")
        #expect(data.categoryBreakdown[0].count == 3)
        #expect(data.bestQuote?.text == "Best ramen ever")
        #expect(data.bestQuote?.placeName == "Ichiran")
    }
}
