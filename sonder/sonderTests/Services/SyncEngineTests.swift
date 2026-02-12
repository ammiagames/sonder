import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct SyncEngineTests {

    private func makeSUT() throws -> (SyncEngine, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        // Use startAutomatically: false to avoid network monitoring and periodic sync in tests
        let engine = SyncEngine(modelContext: context, startAutomatically: false)
        return (engine, context, container)
    }

    @Test func getFailedLogs_returnsOnlyFailed() throws {
        let (engine, context, container) = try makeSUT()
        _ = container  // Keep container alive

        context.insert(TestData.log(id: "synced-1", syncStatus: .synced))
        context.insert(TestData.log(id: "pending-1", syncStatus: .pending))
        context.insert(TestData.log(id: "failed-1", syncStatus: .failed))
        context.insert(TestData.log(id: "failed-2", syncStatus: .failed))
        try context.save()

        let failed = engine.getFailedLogs()
        #expect(failed.count == 2)
        #expect(failed.allSatisfy { $0.syncStatus == .failed })
    }

    @Test func getFailedLogs_emptyWhenNone() throws {
        let (engine, context, container) = try makeSUT()
        _ = container  // Keep container alive

        context.insert(TestData.log(id: "synced-1", syncStatus: .synced))
        context.insert(TestData.log(id: "synced-2", syncStatus: .synced))
        try context.save()

        let failed = engine.getFailedLogs()
        #expect(failed.isEmpty)
    }

    @Test func updatePendingCount_correct() async throws {
        let (engine, context, container) = try makeSUT()
        _ = container  // Keep container alive

        context.insert(TestData.log(id: "synced-1", syncStatus: .synced))
        context.insert(TestData.log(id: "pending-1", syncStatus: .pending))
        context.insert(TestData.log(id: "failed-1", syncStatus: .failed))
        try context.save()

        await engine.updatePendingCount()
        #expect(engine.pendingCount == 2)
    }

    @Test func updatePendingCount_zero() async throws {
        let (engine, context, container) = try makeSUT()
        _ = container  // Keep container alive

        context.insert(TestData.log(id: "synced-1", syncStatus: .synced))
        context.insert(TestData.log(id: "synced-2", syncStatus: .synced))
        try context.save()

        await engine.updatePendingCount()
        #expect(engine.pendingCount == 0)
    }
}
