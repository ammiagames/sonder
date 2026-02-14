import Testing
import Foundation
@testable import sonder

struct CitySectionIndexTests {

    // MARK: - resolveHighlightedCity

    @Test func highlightedCity_dragTakesPriority() {
        let result = CitySectionIndex.resolveHighlightedCity(
            dragCity: "Paris",
            visibleCity: "London"
        )
        #expect(result == "Paris")
    }

    @Test func highlightedCity_fallsBackToVisibleWhenNoDrag() {
        let result = CitySectionIndex.resolveHighlightedCity(
            dragCity: nil,
            visibleCity: "London"
        )
        #expect(result == "London")
    }

    @Test func highlightedCity_nilWhenBothNil() {
        let result = CitySectionIndex.resolveHighlightedCity(
            dragCity: nil,
            visibleCity: nil
        )
        #expect(result == nil)
    }

    @Test func highlightedCity_dragCityEvenWhenVisibleNil() {
        let result = CitySectionIndex.resolveHighlightedCity(
            dragCity: "Tokyo",
            visibleCity: nil
        )
        #expect(result == "Tokyo")
    }

    // MARK: - abbreviate

    @Test func abbreviate_shortCityUnchanged() {
        #expect(CitySectionIndex.abbreviate("LA") == "LA")
        #expect(CitySectionIndex.abbreviate("NYC") == "NYC")
    }

    @Test func abbreviate_longCityTruncated() {
        #expect(CitySectionIndex.abbreviate("Paris") == "Par")
        #expect(CitySectionIndex.abbreviate("Tokyo") == "Tok")
        #expect(CitySectionIndex.abbreviate("San Francisco") == "San")
    }

    // MARK: - Visible city from sections (the logic used by WantToGoListView)

    @Test func visibleCity_firstSortedCityInVisibleSet() {
        let sorted = ["Atlanta", "Boston", "Chicago", "Denver"]
        let visible: Set<String> = ["Boston", "Chicago"]

        let current = sorted.first { visible.contains($0) }
        #expect(current == "Boston")
    }

    @Test func visibleCity_allVisible_returnsFirst() {
        let sorted = ["Atlanta", "Boston", "Chicago"]
        let visible: Set<String> = ["Atlanta", "Boston", "Chicago"]

        let current = sorted.first { visible.contains($0) }
        #expect(current == "Atlanta")
    }

    @Test func visibleCity_noneVisible_returnsNil() {
        let sorted = ["Atlanta", "Boston", "Chicago"]
        let visible: Set<String> = []

        let current = sorted.first { visible.contains($0) }
        #expect(current == nil)
    }

    @Test func visibleCity_scrolledToEnd() {
        let sorted = ["Atlanta", "Boston", "Chicago", "Denver"]
        let visible: Set<String> = ["Denver"]

        let current = sorted.first { visible.contains($0) }
        #expect(current == "Denver")
    }
}
