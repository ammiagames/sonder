import Testing
import Foundation
import SwiftData
@testable import sonder

/// Tests for the trip log reorder algorithm:
/// assigns sequential `tripSortOrder` values without modifying `createdAt`.
@Suite(.serialized)
@MainActor
struct ReorderTripLogsTests {

    private func makeSUT() throws -> (ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        return (context, container)
    }

    /// Core reorder algorithm extracted for testability — mirrors ReorderTripLogsSheet.saveNewOrder()
    private func applyReorder(_ orderedLogs: [Log]) {
        let now = Date()
        for (i, log) in orderedLogs.enumerated() {
            log.tripSortOrder = i
            log.syncStatus = .pending
            log.updatedAt = now
        }
    }

    // MARK: - tripSortOrder Assignment

    @Test func reorder_assignsSequentialSortOrder() throws {
        let (context, container) = try makeSUT()
        _ = container

        let logA = TestData.log(id: "a", tripID: "trip-1", syncStatus: .synced, createdAt: fixedDate())
        let logB = TestData.log(id: "b", tripID: "trip-1", syncStatus: .synced, createdAt: fixedDate().addingTimeInterval(3600))
        let logC = TestData.log(id: "c", tripID: "trip-1", syncStatus: .synced, createdAt: fixedDate().addingTimeInterval(7200))

        context.insert(logA)
        context.insert(logB)
        context.insert(logC)
        try context.save()

        // User wants order: C, A, B
        applyReorder([logC, logA, logB])

        #expect(logC.tripSortOrder == 0)
        #expect(logA.tripSortOrder == 1)
        #expect(logB.tripSortOrder == 2)
    }

    @Test func reorder_doesNotModifyCreatedAt() throws {
        let (context, container) = try makeSUT()
        _ = container

        let early = fixedDate()
        let late = early.addingTimeInterval(3600)

        let logA = TestData.log(id: "a", tripID: "trip-1", syncStatus: .synced, createdAt: early)
        let logB = TestData.log(id: "b", tripID: "trip-1", syncStatus: .synced, createdAt: late)

        context.insert(logA)
        context.insert(logB)
        try context.save()

        // User drags B before A → new order: [B, A]
        applyReorder([logB, logA])

        // createdAt must remain unchanged
        #expect(logA.createdAt == early)
        #expect(logB.createdAt == late)
    }

    @Test func reorder_threeLogsReversed() throws {
        let (context, container) = try makeSUT()
        _ = container

        let t1 = fixedDate()
        let t2 = t1.addingTimeInterval(3600)
        let t3 = t1.addingTimeInterval(7200)

        let logA = TestData.log(id: "a", tripID: "trip-1", syncStatus: .synced, createdAt: t1)
        let logB = TestData.log(id: "b", tripID: "trip-1", syncStatus: .synced, createdAt: t2)
        let logC = TestData.log(id: "c", tripID: "trip-1", syncStatus: .synced, createdAt: t3)

        context.insert(logA)
        context.insert(logB)
        context.insert(logC)
        try context.save()

        // User reverses order → [C, B, A]
        applyReorder([logC, logB, logA])

        #expect(logC.tripSortOrder == 0)
        #expect(logB.tripSortOrder == 1)
        #expect(logA.tripSortOrder == 2)

        // createdAt unchanged
        #expect(logA.createdAt == t1)
        #expect(logB.createdAt == t2)
        #expect(logC.createdAt == t3)
    }

    // MARK: - Sync Status

    @Test func reorder_marksSyncPending() throws {
        let (context, container) = try makeSUT()
        _ = container

        let logA = TestData.log(id: "a", tripID: "trip-1", syncStatus: .synced, createdAt: fixedDate())
        let logB = TestData.log(id: "b", tripID: "trip-1", syncStatus: .synced, createdAt: fixedDate().addingTimeInterval(3600))

        context.insert(logA)
        context.insert(logB)
        try context.save()

        #expect(logA.syncStatus == .synced)
        #expect(logB.syncStatus == .synced)

        applyReorder([logB, logA])

        #expect(logA.syncStatus == .pending)
        #expect(logB.syncStatus == .pending)
    }

    @Test func reorder_updatesUpdatedAt() throws {
        let (context, container) = try makeSUT()
        _ = container

        let oldDate = fixedDate()
        let logA = TestData.log(id: "a", tripID: "trip-1", createdAt: oldDate, updatedAt: oldDate)
        let logB = TestData.log(id: "b", tripID: "trip-1", createdAt: oldDate.addingTimeInterval(3600), updatedAt: oldDate)

        context.insert(logA)
        context.insert(logB)
        try context.save()

        let beforeReorder = Date()
        applyReorder([logB, logA])

        #expect(logA.updatedAt >= beforeReorder)
        #expect(logB.updatedAt >= beforeReorder)
    }

    // MARK: - Sort Propagation

    @Test func reorder_sortByTripSortOrderGivesIntendedOrder() throws {
        let (context, container) = try makeSUT()
        _ = container

        let t1 = fixedDate()
        let t2 = t1.addingTimeInterval(3600)
        let t3 = t1.addingTimeInterval(7200)

        let logA = TestData.log(id: "a", tripID: "trip-1", syncStatus: .synced, createdAt: t1)
        let logB = TestData.log(id: "b", tripID: "trip-1", syncStatus: .synced, createdAt: t2)
        let logC = TestData.log(id: "c", tripID: "trip-1", syncStatus: .synced, createdAt: t3)

        context.insert(logA)
        context.insert(logB)
        context.insert(logC)
        try context.save()

        // User wants order: C, A, B
        applyReorder([logC, logA, logB])

        // Sort using the same logic as TripDetailView.tripLogs
        let sorted = [logA, logB, logC].sorted {
            if let a = $0.tripSortOrder, let b = $1.tripSortOrder {
                return a < b
            }
            return $0.createdAt < $1.createdAt
        }
        #expect(sorted[0].id == "c")
        #expect(sorted[1].id == "a")
        #expect(sorted[2].id == "b")
    }

    @Test func reorder_sameOrderAssignsSequentialIndices() throws {
        let (context, container) = try makeSUT()
        _ = container

        let t1 = fixedDate()
        let t2 = t1.addingTimeInterval(3600)

        let logA = TestData.log(id: "a", tripID: "trip-1", syncStatus: .synced, createdAt: t1)
        let logB = TestData.log(id: "b", tripID: "trip-1", syncStatus: .synced, createdAt: t2)

        context.insert(logA)
        context.insert(logB)
        try context.save()

        // Same order → still assigns tripSortOrder
        applyReorder([logA, logB])

        #expect(logA.tripSortOrder == 0)
        #expect(logB.tripSortOrder == 1)
        // createdAt unchanged
        #expect(logA.createdAt == t1)
        #expect(logB.createdAt == t2)
    }
}
