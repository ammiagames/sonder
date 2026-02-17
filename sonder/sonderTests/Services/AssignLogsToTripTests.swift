import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct AssignLogsToTripTests {

    private func makeSUT() throws -> (ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        return (context, container)
    }

    /// Simulates the local portion of TripService.associateLog(_:with:)
    /// (sets tripID + updatedAt and saves). The real method also syncs to
    /// Supabase, which is unavailable in unit tests.
    private func associateLogLocally(_ log: Log, with trip: Trip?, context: ModelContext) throws {
        log.tripID = trip?.id
        log.updatedAt = Date()
        try context.save()
    }

    // MARK: - Associate Log (local logic)

    @Test func associateLog_setsTripID() throws {
        let (context, container) = try makeSUT()
        _ = container

        let log = TestData.log(id: "log-1", tripID: nil)
        let trip = TestData.trip(id: "trip-1")
        context.insert(log)
        context.insert(trip)
        try context.save()

        #expect(log.tripID == nil)

        try associateLogLocally(log, with: trip, context: context)

        #expect(log.tripID == "trip-1")
    }

    @Test func associateLog_updatesTimestamp() throws {
        let (context, container) = try makeSUT()
        _ = container

        let log = TestData.log(id: "log-1", tripID: nil)
        let trip = TestData.trip(id: "trip-1")
        let originalUpdatedAt = log.updatedAt
        context.insert(log)
        context.insert(trip)
        try context.save()

        Thread.sleep(forTimeInterval: 0.01)
        try associateLogLocally(log, with: trip, context: context)

        #expect(log.updatedAt > originalUpdatedAt)
    }

    @Test func associateLog_batchAssignment() throws {
        let (context, container) = try makeSUT()
        _ = container

        let trip = TestData.trip(id: "trip-1")
        let log1 = TestData.log(id: "log-1", tripID: nil)
        let log2 = TestData.log(id: "log-2", tripID: nil)
        let log3 = TestData.log(id: "log-3", tripID: nil)
        context.insert(trip)
        context.insert(log1)
        context.insert(log2)
        context.insert(log3)
        try context.save()

        // Simulate what AssignLogsToTripSheet does
        for log in [log1, log2, log3] {
            try associateLogLocally(log, with: trip, context: context)
        }

        #expect(log1.tripID == "trip-1")
        #expect(log2.tripID == "trip-1")
        #expect(log3.tripID == "trip-1")
    }

    @Test func associateLog_partialSelection() throws {
        let (context, container) = try makeSUT()
        _ = container

        let trip = TestData.trip(id: "trip-1")
        let log1 = TestData.log(id: "log-1", tripID: nil)
        let log2 = TestData.log(id: "log-2", tripID: nil)
        let log3 = TestData.log(id: "log-3", tripID: nil)
        context.insert(trip)
        context.insert(log1)
        context.insert(log2)
        context.insert(log3)
        try context.save()

        // Only assign selected logs (simulates partial selection in the sheet)
        let selectedIDs: Set<String> = ["log-1", "log-3"]
        for log in [log1, log2, log3] where selectedIDs.contains(log.id) {
            try associateLogLocally(log, with: trip, context: context)
        }

        #expect(log1.tripID == "trip-1")
        #expect(log2.tripID == nil)
        #expect(log3.tripID == "trip-1")
    }

    @Test func associateLog_doesNotAffectOtherTrips() throws {
        let (context, container) = try makeSUT()
        _ = container

        let trip1 = TestData.trip(id: "trip-1")
        let logInTrip2 = TestData.log(id: "log-existing", tripID: "trip-2")
        let orphanLog = TestData.log(id: "log-orphan", tripID: nil)
        context.insert(trip1)
        context.insert(logInTrip2)
        context.insert(orphanLog)
        try context.save()

        try associateLogLocally(orphanLog, with: trip1, context: context)

        #expect(orphanLog.tripID == "trip-1")
        #expect(logInTrip2.tripID == "trip-2")
    }

    @Test func associateLog_withNilRemovesFromTrip() throws {
        let (context, container) = try makeSUT()
        _ = container

        let log = TestData.log(id: "log-1", tripID: "trip-1")
        context.insert(log)
        try context.save()

        #expect(log.tripID == "trip-1")

        try associateLogLocally(log, with: nil, context: context)

        #expect(log.tripID == nil)
    }

    // MARK: - Orphaned Log Filtering

    @Test func orphanedLogs_filtersCorrectly() throws {
        let (context, container) = try makeSUT()
        _ = container

        let log1 = TestData.log(id: "log-1", userID: "user-1", tripID: nil)
        let log2 = TestData.log(id: "log-2", userID: "user-1", tripID: "trip-1")
        let log3 = TestData.log(id: "log-3", userID: "user-1", tripID: nil)
        let log4 = TestData.log(id: "log-4", userID: "user-2", tripID: nil)
        context.insert(log1)
        context.insert(log2)
        context.insert(log3)
        context.insert(log4)
        try context.save()

        // Simulate JournalContainerView.orphanedLogs logic
        let userLogs = [log1, log2, log3, log4].filter { $0.userID == "user-1" }
        let orphaned = userLogs.filter { $0.tripID == nil }

        #expect(orphaned.count == 2)
        #expect(orphaned.contains { $0.id == "log-1" })
        #expect(orphaned.contains { $0.id == "log-3" })
        #expect(!orphaned.contains { $0.id == "log-2" })
        #expect(!orphaned.contains { $0.id == "log-4" })
    }

    @Test func orphanedLogs_emptyWhenAllAssigned() throws {
        let (context, container) = try makeSUT()
        _ = container

        let log1 = TestData.log(id: "log-1", userID: "user-1", tripID: "trip-1")
        let log2 = TestData.log(id: "log-2", userID: "user-1", tripID: "trip-2")
        context.insert(log1)
        context.insert(log2)
        try context.save()

        let userLogs = [log1, log2].filter { $0.userID == "user-1" }
        let orphaned = userLogs.filter { $0.tripID == nil }

        #expect(orphaned.isEmpty)
    }

    @Test func orphanedLogs_becomeAssignedAfterBatchAssociation() throws {
        let (context, container) = try makeSUT()
        _ = container

        let trip = TestData.trip(id: "trip-1")
        let log1 = TestData.log(id: "log-1", userID: "user-1", tripID: nil)
        let log2 = TestData.log(id: "log-2", userID: "user-1", tripID: nil)
        context.insert(trip)
        context.insert(log1)
        context.insert(log2)
        try context.save()

        let allUserLogs = [log1, log2]
        var orphaned = allUserLogs.filter { $0.tripID == nil }
        #expect(orphaned.count == 2)

        // Assign all
        for log in orphaned {
            try associateLogLocally(log, with: trip, context: context)
        }

        orphaned = allUserLogs.filter { $0.tripID == nil }
        #expect(orphaned.isEmpty)
    }
}
