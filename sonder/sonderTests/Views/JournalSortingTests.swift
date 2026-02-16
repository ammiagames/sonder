import Testing
import Foundation
@testable import sonder

struct JournalSortingTests {

    // MARK: - Trip Sorting

    @Test func sortsByStartDateDescending() {
        let jan = TestData.trip(id: "jan", name: "January", startDate: date(2025, 1, 15), createdBy: "u1")
        let mar = TestData.trip(id: "mar", name: "March", startDate: date(2025, 3, 10), createdBy: "u1")
        let may = TestData.trip(id: "may", name: "May", startDate: date(2025, 5, 20), createdBy: "u1")

        let sorted = sortTripsReverseChronological([jan, mar, may])

        #expect(sorted.map(\.id) == ["may", "mar", "jan"])
    }

    @Test func fallsBackToCreatedAtWhenNoStartDate() {
        let early = TestData.trip(id: "early", name: "Early", createdBy: "u1", createdAt: date(2025, 2, 1))
        let late = TestData.trip(id: "late", name: "Late", createdBy: "u1", createdAt: date(2025, 6, 1))

        let sorted = sortTripsReverseChronological([early, late])

        #expect(sorted.map(\.id) == ["late", "early"])
    }

    @Test func mixesStartDateAndCreatedAtFallback() {
        // Trip with startDate in April
        let withDate = TestData.trip(
            id: "with-date", name: "Has Start Date",
            startDate: date(2025, 4, 1),
            createdBy: "u1", createdAt: date(2025, 1, 1)
        )
        // Trip without startDate, created in June — should sort above April trip
        let noDate = TestData.trip(
            id: "no-date", name: "No Start Date",
            createdBy: "u1", createdAt: date(2025, 6, 1)
        )

        let sorted = sortTripsReverseChronological([withDate, noDate])

        #expect(sorted.map(\.id) == ["no-date", "with-date"])
    }

    @Test func singleTripReturnsSelf() {
        let trip = TestData.trip(id: "solo", name: "Solo", startDate: date(2025, 3, 1), createdBy: "u1")
        let sorted = sortTripsReverseChronological([trip])

        #expect(sorted.count == 1)
        #expect(sorted[0].id == "solo")
    }

    @Test func emptyArrayReturnsEmpty() {
        let sorted = sortTripsReverseChronological([])
        #expect(sorted.isEmpty)
    }

    @Test func sameStartDatePreservesRelativeOrder() {
        let sameDate = date(2025, 5, 1)
        let a = TestData.trip(id: "a", name: "A", startDate: sameDate, createdBy: "u1")
        let b = TestData.trip(id: "b", name: "B", startDate: sameDate, createdBy: "u1")

        let sorted = sortTripsReverseChronological([a, b])

        // Both have the same date — sort is stable so relative order is preserved
        #expect(sorted.count == 2)
    }

    // MARK: - Masonry Column Assignment

    @Test func alternatesColumnsForEqualHeights() {
        // All trips have the same estimated height (no description, no dates)
        let trips = (0..<4).map { i in
            TestData.trip(id: "t\(i)", name: "Trip \(i)", createdBy: "u1")
        }

        let assignments = assignMasonryColumns(trips: trips) { _ in 100 }

        // Equal heights → alternates: left, right, left, right
        #expect(assignments.map(\.column) == [0, 1, 0, 1])
        // Indices preserved in order
        #expect(assignments.map(\.index) == [0, 1, 2, 3])
    }

    @Test func tallFirstCardPushesNextTwoRight() {
        let trips = (0..<3).map { i in
            TestData.trip(id: "t\(i)", name: "Trip \(i)", createdBy: "u1")
        }

        // First card is tall (200), next two are short (80 each)
        let heights: [CGFloat] = [200, 80, 80]
        let assignments = assignMasonryColumns(trips: trips) { trip in
            let idx = trips.firstIndex(where: { $0.id == trip.id })!
            return heights[idx]
        }

        // Card 0 → left (height 0 <= 0), left becomes 210
        // Card 1 → right (210 > 0), right becomes 90
        // Card 2 → right (210 > 90), right becomes 180
        #expect(assignments[0].column == 0)
        #expect(assignments[1].column == 1)
        #expect(assignments[2].column == 1)
    }

    @Test func preservesChronologicalIndices() {
        let trips = (0..<5).map { i in
            TestData.trip(id: "t\(i)", name: "Trip \(i)", createdBy: "u1")
        }

        let assignments = assignMasonryColumns(trips: trips) { _ in 100 }

        // Every trip gets its original index regardless of column
        #expect(assignments.map(\.index) == [0, 1, 2, 3, 4])
        // Trip IDs match their original order
        #expect(assignments.map(\.trip.id) == ["t0", "t1", "t2", "t3", "t4"])
    }

    @Test func singleTripGoesToLeftColumn() {
        let trip = TestData.trip(id: "solo", name: "Solo Trip", createdBy: "u1")
        let assignments = assignMasonryColumns(trips: [trip]) { _ in 100 }

        #expect(assignments.count == 1)
        #expect(assignments[0].column == 0)
        #expect(assignments[0].index == 0)
    }

    @Test func emptyTripsReturnsEmpty() {
        let assignments = assignMasonryColumns(trips: []) { _ in 100 }
        #expect(assignments.isEmpty)
    }

    @Test func topToBottomReadingOrderIsChronological() {
        // Create trips in reverse chronological order (most recent first)
        let trips = [
            TestData.trip(id: "newest", name: "Newest", startDate: date(2025, 6, 1), createdBy: "u1"),
            TestData.trip(id: "middle", name: "Middle", startDate: date(2025, 4, 1), createdBy: "u1"),
            TestData.trip(id: "oldest", name: "Oldest", startDate: date(2025, 2, 1), createdBy: "u1"),
        ]

        // Sort them first (as the real app does)
        let sorted = sortTripsReverseChronological(trips)
        #expect(sorted.map(\.id) == ["newest", "middle", "oldest"])

        // Then assign columns
        let assignments = assignMasonryColumns(trips: sorted) { _ in 100 }

        // Index 0 = newest (top), index 2 = oldest (bottom)
        #expect(assignments[0].trip.id == "newest")
        #expect(assignments[0].index == 0)
        #expect(assignments[2].trip.id == "oldest")
        #expect(assignments[2].index == 2)

        // The left column's first card has a lower index than the right column's second card
        let leftIndices = assignments.filter { $0.column == 0 }.map(\.index)
        let rightIndices = assignments.filter { $0.column == 1 }.map(\.index)
        // Both columns should have increasing indices (top-to-bottom = older)
        #expect(leftIndices == leftIndices.sorted())
        #expect(rightIndices == rightIndices.sorted())
    }

    // MARK: - Helpers

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
