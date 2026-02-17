import Testing
import Foundation
@testable import sonder

struct CityLogsGroupingTests {

    // MARK: - All logs without trips

    @Test func allLogsWithoutTrip_appearsInNilTripSection() {
        let log1 = TestData.log(id: "log-1", placeID: "p1", tripID: nil, createdAt: fixedDate())
        let log2 = TestData.log(id: "log-2", placeID: "p2", tripID: nil, createdAt: fixedDate().addingTimeInterval(3600))

        let groups = CityLogsView.buildTripGroups(logs: [log1, log2], trips: [])

        #expect(groups.count == 1)
        #expect(groups[0].trip == nil)
        #expect(groups[0].logs.count == 2)
    }

    // MARK: - Orphaned logs (tripID points to non-existent trip)

    @Test func orphanedLogs_includedInNilTripSection() {
        let log1 = TestData.log(id: "log-1", placeID: "p1", tripID: "deleted-trip", createdAt: fixedDate())
        let log2 = TestData.log(id: "log-2", placeID: "p2", tripID: "also-deleted", createdAt: fixedDate().addingTimeInterval(3600))

        let groups = CityLogsView.buildTripGroups(logs: [log1, log2], trips: [])

        #expect(groups.count == 1)
        #expect(groups[0].trip == nil)
        #expect(groups[0].logs.count == 2)
    }

    // MARK: - Mixed: some with trips, some without, some orphaned

    @Test func mixedLogs_groupsCorrectly() {
        let trip = TestData.trip(id: "trip-1", name: "Japan Trip")
        let trippedLog = TestData.log(id: "log-1", placeID: "p1", tripID: "trip-1", createdAt: fixedDate())
        let untripLog = TestData.log(id: "log-2", placeID: "p2", tripID: nil, createdAt: fixedDate().addingTimeInterval(3600))
        let orphanLog = TestData.log(id: "log-3", placeID: "p3", tripID: "gone-trip", createdAt: fixedDate().addingTimeInterval(7200))

        let groups = CityLogsView.buildTripGroups(logs: [trippedLog, untripLog, orphanLog], trips: [trip])

        // Should have 2 sections: one for trip-1, one nil section with untripped + orphaned
        #expect(groups.count == 2)

        let tripSection = groups.first { $0.trip != nil }
        #expect(tripSection?.trip?.id == "trip-1")
        #expect(tripSection?.logs.count == 1)
        #expect(tripSection?.logs[0].id == "log-1")

        let nilSection = groups.first { $0.trip == nil }
        #expect(nilSection?.logs.count == 2)
        let nilLogIDs = Set(nilSection?.logs.map(\.id) ?? [])
        #expect(nilLogIDs.contains("log-2"))
        #expect(nilLogIDs.contains("log-3"))
    }

    // MARK: - Empty logs

    @Test func emptyLogs_returnsNoSections() {
        let groups = CityLogsView.buildTripGroups(logs: [], trips: [])
        #expect(groups.isEmpty)
    }

    // MARK: - Trip sections sorted by most recent log

    @Test func tripSections_sortedByMostRecentLog() {
        let tripA = TestData.trip(id: "trip-a", name: "Old Trip")
        let tripB = TestData.trip(id: "trip-b", name: "New Trip")
        let oldLog = TestData.log(id: "log-1", placeID: "p1", tripID: "trip-a", createdAt: fixedDate())
        let newLog = TestData.log(id: "log-2", placeID: "p2", tripID: "trip-b", createdAt: fixedDate().addingTimeInterval(86400))

        let groups = CityLogsView.buildTripGroups(logs: [oldLog, newLog], trips: [tripA, tripB])

        // Trip sections (excluding nil) should be sorted newest first
        let tripSections = groups.filter { $0.trip != nil }
        #expect(tripSections.count == 2)
        #expect(tripSections[0].trip?.id == "trip-b")
        #expect(tripSections[1].trip?.id == "trip-a")
    }

    // MARK: - Nil section always appears last

    @Test func nilSection_appearsAfterTripSections() {
        let trip = TestData.trip(id: "trip-1", name: "Trip")
        let trippedLog = TestData.log(id: "log-1", placeID: "p1", tripID: "trip-1", createdAt: fixedDate())
        let untripLog = TestData.log(id: "log-2", placeID: "p2", tripID: nil, createdAt: fixedDate().addingTimeInterval(999_999))

        let groups = CityLogsView.buildTripGroups(logs: [trippedLog, untripLog], trips: [trip])

        #expect(groups.count == 2)
        #expect(groups[0].trip != nil) // Trip section first
        #expect(groups[1].trip == nil) // Nil section last
    }

    // MARK: - Orphaned logs sorted newest first within nil section

    @Test func nilSection_logsSortedNewestFirst() {
        let older = TestData.log(id: "log-old", placeID: "p1", tripID: nil, createdAt: fixedDate())
        let newer = TestData.log(id: "log-new", placeID: "p2", tripID: nil, createdAt: fixedDate().addingTimeInterval(86400))
        let orphan = TestData.log(id: "log-orphan", placeID: "p3", tripID: "gone", createdAt: fixedDate().addingTimeInterval(43200))

        let groups = CityLogsView.buildTripGroups(logs: [older, newer, orphan], trips: [])

        #expect(groups.count == 1)
        let logIDs = groups[0].logs.map(\.id)
        #expect(logIDs == ["log-new", "log-orphan", "log-old"])
    }
}
