import Testing
import Foundation
@testable import sonder

struct TagSuggestionTests {

    @Test func recentTagsByUsage_usesMostRecentOrder_andDeduplicates() {
        let logs = [
            TestData.log(
                id: "newest",
                userID: "u1",
                tags: ["Coffee", "Brunch"],
                createdAt: date(2026, 2, 20)
            ),
            TestData.log(
                id: "middle",
                userID: "u2",
                tags: ["Museum"],
                createdAt: date(2026, 2, 19)
            ),
            TestData.log(
                id: "older",
                userID: "u1",
                tags: ["coffee", "Dinner", "   "],
                createdAt: date(2026, 2, 10)
            ),
        ]

        let result = recentTagsByUsage(logs: logs, userID: "u1")

        #expect(result == ["Coffee", "Brunch", "Dinner"])
    }

    @Test func prioritizedTagSuggestions_placesRecentFirst_andExcludesSelected() {
        let result = prioritizedTagSuggestions(
            recentTags: ["coffee", "café", "dinner"],
            fallbackTags: ["food", "coffee", "bar", "cafe"],
            selectedTags: ["DINNER"],
            limit: 10
        )

        #expect(result == ["coffee", "café", "food", "bar"])
    }

    @Test func prioritizedTagSuggestions_respectsLimit() {
        let result = prioritizedTagSuggestions(
            recentTags: ["coffee", "dinner", "brunch"],
            fallbackTags: ["food", "bar"],
            selectedTags: [],
            limit: 2
        )

        #expect(result == ["coffee", "dinner"])
    }

    @Test func prioritizedTagSuggestions_zeroLimitReturnsEmpty() {
        let result = prioritizedTagSuggestions(
            recentTags: ["coffee"],
            fallbackTags: ["food"],
            selectedTags: [],
            limit: 0
        )

        #expect(result.isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
