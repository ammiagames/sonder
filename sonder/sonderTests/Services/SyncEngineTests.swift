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

    // MARK: - Network Status

    @Test func isOnline_defaultsToTrue() throws {
        let (engine, _, container) = try makeSUT()
        _ = container
        #expect(engine.isOnline == true)
    }

    @Test func handleNetworkChange_goesOffline() throws {
        let (engine, _, container) = try makeSUT()
        _ = container
        engine.isOnline = true

        engine.handleNetworkChange(isConnected: false)
        #expect(engine.isOnline == false)
    }

    @Test func handleNetworkChange_goesOnline() throws {
        let (engine, _, container) = try makeSUT()
        _ = container
        engine.isOnline = false

        engine.handleNetworkChange(isConnected: true)
        #expect(engine.isOnline == true)
    }

    @Test func handleNetworkChange_ignoresDuplicateState() throws {
        let (engine, _, container) = try makeSUT()
        _ = container
        engine.isOnline = true

        // Same state — should be a no-op (guard skips)
        engine.handleNetworkChange(isConnected: true)
        #expect(engine.isOnline == true)

        engine.isOnline = false
        engine.handleNetworkChange(isConnected: false)
        #expect(engine.isOnline == false)
    }

    @Test func syncNow_skipsWhenOffline() async throws {
        let (engine, _, container) = try makeSUT()
        _ = container
        engine.isOnline = false

        // syncNow should return early without syncing
        await engine.syncNow()
        #expect(engine.isSyncing == false)
    }

    // MARK: - Merge Remote Logs

    @Test func mergeRemoteLogs_insertsNewLog() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.place(id: "place-1"))
        try context.save()

        let remote = RemoteLog(
            id: "remote-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "okay",
            note: "Great spot",
            tags: ["food"],
            createdAt: fixedDate(),
            updatedAt: fixedDate()
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].id == "remote-1")
        #expect(logs[0].syncStatus == .synced)
        #expect(logs[0].note == "Great spot")
        #expect(logs[0].rating == .okay)
    }

    @Test func mergeRemoteLogs_skipsLocalPendingLog() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.log(id: "log-1", rating: .okay, syncStatus: .pending))
        try context.save()

        let remote = RemoteLog(
            id: "log-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "must_see",
            note: "remote note",
            createdAt: fixedDate(),
            updatedAt: fixedDate().addingTimeInterval(100)
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].syncStatus == .pending)
        #expect(logs[0].rating == .okay)  // Local value preserved
    }

    @Test func mergeRemoteLogs_updatesStaleLocalLog() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.log(
            id: "log-1",
            rating: .okay,
            syncStatus: .synced,
            updatedAt: fixedDate()
        ))
        try context.save()

        let remote = RemoteLog(
            id: "log-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "must_see",
            note: "updated note",
            tags: ["nightlife"],
            createdAt: fixedDate(),
            updatedAt: fixedDate().addingTimeInterval(60)  // Newer
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].rating == .mustSee)
        #expect(logs[0].note == "updated note")
        #expect(logs[0].tags == ["nightlife"])
        #expect(logs[0].syncStatus == .synced)
    }

    @Test func mergeRemoteLogs_preservesNewerLocalLog() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.log(
            id: "log-1",
            rating: .mustSee,
            note: "local note",
            syncStatus: .synced,
            updatedAt: fixedDate().addingTimeInterval(120)  // Newer than remote
        ))
        try context.save()

        let remote = RemoteLog(
            id: "log-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "solid",
            note: "old remote note",
            createdAt: fixedDate(),
            updatedAt: fixedDate().addingTimeInterval(60)  // Older
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].rating == .mustSee)  // Local preserved
        #expect(logs[0].note == "local note")
    }

    @Test func mergeRemoteLogs_insertsMultipleLogs() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        let place = TestData.place(id: "place-A", name: "Place A")
        let remotePlaces = [place]

        let remoteLogs = [
            RemoteLog(id: "r1", userID: "user-1", placeID: "place-A", rating: "solid",
                      createdAt: fixedDate(), updatedAt: fixedDate()),
            RemoteLog(id: "r2", userID: "user-1", placeID: "place-A", rating: "must_see",
                      note: "Amazing", createdAt: fixedDate(), updatedAt: fixedDate()),
            RemoteLog(id: "r3", userID: "user-1", placeID: "place-A", rating: "skip",
                      createdAt: fixedDate(), updatedAt: fixedDate()),
        ]

        try engine.mergeRemoteLogs(remoteLogs, remotePlaces: remotePlaces)

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 3)
        #expect(logs.allSatisfy { $0.syncStatus == .synced })

        let places = try context.fetch(FetchDescriptor<Place>())
        #expect(places.count == 1)
        #expect(places[0].name == "Place A")
    }

    @Test func mergeRemoteLogs_skipsLocalFailedLog() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.log(id: "log-1", rating: .skip, syncStatus: .failed))
        try context.save()

        let remote = RemoteLog(
            id: "log-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "must_see",
            note: "overwrite attempt",
            createdAt: fixedDate(),
            updatedAt: fixedDate().addingTimeInterval(200)
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].syncStatus == .failed)
        #expect(logs[0].rating == .skip)  // Local value preserved
    }

    @Test func mergeRemoteLogs_insertsMissingPlaces() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        // No local places — merge should insert the remote place
        let remotePlace = TestData.place(id: "new-place", name: "New Cafe", address: "456 New St")
        let remote = RemoteLog(
            id: "r1",
            userID: "user-1",
            placeID: "new-place",
            rating: "solid",
            createdAt: fixedDate(),
            updatedAt: fixedDate()
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [remotePlace])

        let places = try context.fetch(FetchDescriptor<Place>())
        #expect(places.count == 1)
        #expect(places[0].id == "new-place")
        #expect(places[0].name == "New Cafe")

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].placeID == "new-place")
    }

    @Test func mergeRemoteLogs_visibleFromSeparateContext() throws {
        let container = try makeTestModelContainer()
        let mainContext = container.mainContext
        let engine = SyncEngine(modelContext: mainContext, startAutomatically: false)

        // Merge inserts into the main context and saves
        let remotePlace = TestData.place(id: "place-1")
        let remote = RemoteLog(
            id: "cross-ctx-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "must_see",
            createdAt: fixedDate(),
            updatedAt: fixedDate()
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [remotePlace])

        // Data should be visible from a separate context (simulates @Query on a different context)
        let otherContext = ModelContext(container)
        let otherLogs = try otherContext.fetch(FetchDescriptor<Log>())
        #expect(otherLogs.count == 1)
        #expect(otherLogs[0].id == "cross-ctx-1")
        #expect(otherLogs[0].syncStatus == .synced)
    }

    // MARK: - Merge Remote Trips

    @Test func mergeRemoteTrips_insertsNewTrip() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        let remote = RemoteTrip(
            id: "trip-1",
            name: "Japan 2026",
            tripDescription: "Spring trip",
            createdBy: "user-1",
            createdAt: fixedDate(),
            updatedAt: fixedDate()
        )

        try engine.mergeRemoteTrips([remote])

        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
        #expect(trips[0].id == "trip-1")
        #expect(trips[0].name == "Japan 2026")
        #expect(trips[0].tripDescription == "Spring trip")
        #expect(trips[0].createdBy == "user-1")
    }

    @Test func mergeRemoteTrips_updatesStaleLocalTrip() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.trip(
            id: "trip-1",
            name: "Old Name",
            createdBy: "user-1",
            updatedAt: fixedDate()
        ))
        try context.save()

        let remote = RemoteTrip(
            id: "trip-1",
            name: "Updated Name",
            tripDescription: "New description",
            collaboratorIDs: ["user-2"],
            createdBy: "user-1",
            createdAt: fixedDate(),
            updatedAt: fixedDate().addingTimeInterval(60)  // Newer
        )

        try engine.mergeRemoteTrips([remote])

        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
        #expect(trips[0].name == "Updated Name")
        #expect(trips[0].tripDescription == "New description")
        #expect(trips[0].collaboratorIDs == ["user-2"])
    }

    @Test func mergeRemoteTrips_preservesNewerLocalTrip() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.trip(
            id: "trip-1",
            name: "Local Name",
            createdBy: "user-1",
            updatedAt: fixedDate().addingTimeInterval(120)  // Newer
        ))
        try context.save()

        let remote = RemoteTrip(
            id: "trip-1",
            name: "Old Remote Name",
            createdBy: "user-1",
            createdAt: fixedDate(),
            updatedAt: fixedDate().addingTimeInterval(60)  // Older
        )

        try engine.mergeRemoteTrips([remote])

        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
        #expect(trips[0].name == "Local Name")  // Local preserved
    }

    @Test func mergeRemoteTrips_insertsMultipleTrips() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        let remoteTrips = [
            RemoteTrip(id: "t1", name: "Trip A", createdBy: "user-1",
                       createdAt: fixedDate(), updatedAt: fixedDate()),
            RemoteTrip(id: "t2", name: "Trip B", createdBy: "user-1",
                       createdAt: fixedDate(), updatedAt: fixedDate()),
            RemoteTrip(id: "t3", name: "Trip C", collaboratorIDs: ["user-1"],
                       createdBy: "user-2", createdAt: fixedDate(), updatedAt: fixedDate()),
        ]

        try engine.mergeRemoteTrips(remoteTrips)

        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 3)
    }

    // MARK: - Independent Pull Failures

    @Test func mergeRemoteLogs_independentOfTrips() throws {
        // Verify that log merge works even if trip merge was never called
        let (engine, context, container) = try makeSUT()
        _ = container

        let place = TestData.place(id: "place-1")
        context.insert(place)
        try context.save()

        // Only merge logs (no trips) — should succeed independently
        let remoteLogs = [
            RemoteLog(id: "log-1", userID: "user-1", placeID: "place-1",
                      rating: "solid", createdAt: fixedDate(), updatedAt: fixedDate()),
        ]

        try engine.mergeRemoteLogs(remoteLogs, remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].syncStatus == .synced)

        // No trips should exist
        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.isEmpty)
    }

    // MARK: - Delete Sync

    @Test func deleteLog_removesFromLocalSwiftData() async throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        let log = TestData.log(id: "log-to-delete", syncStatus: .synced)
        context.insert(log)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Log>()).count == 1)

        // deleteLog removes locally (Supabase call will fail in tests — that's OK)
        await engine.deleteLog(id: log.id)

        let remaining = try context.fetch(FetchDescriptor<Log>())
        #expect(remaining.isEmpty)
    }

    @Test func deleteLog_addsToPendingDeletions() async throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        let log = TestData.log(id: "log-delete-pending", syncStatus: .synced)
        context.insert(log)
        try context.save()

        #expect(engine.pendingDeletions.isEmpty)

        await engine.deleteLog(id: log.id)

        // Supabase call fails in tests, so the ID stays in pendingDeletions
        #expect(engine.pendingDeletions.contains("log-delete-pending"))
    }

    @Test func mergeRemoteLogs_skipsPendingDeletion() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        // Simulate a log that was deleted locally but Supabase delete failed
        engine.pendingDeletions.insert("deleted-log-1")

        // Remote pull returns the "deleted" log — merge should skip it
        let remote = RemoteLog(
            id: "deleted-log-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "solid",
            createdAt: fixedDate(),
            updatedAt: fixedDate()
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        // The log should NOT be re-inserted
        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.isEmpty)
    }

    @Test func mergeRemoteLogs_insertsNonDeletedLogsNormally() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        // Only "deleted-log-1" is pending deletion
        engine.pendingDeletions.insert("deleted-log-1")

        let remoteLogs = [
            RemoteLog(id: "deleted-log-1", userID: "user-1", placeID: "place-1",
                      rating: "solid", createdAt: fixedDate(), updatedAt: fixedDate()),
            RemoteLog(id: "normal-log-2", userID: "user-1", placeID: "place-1",
                      rating: "must_see", createdAt: fixedDate(), updatedAt: fixedDate()),
        ]

        context.insert(TestData.place(id: "place-1"))
        try context.save()

        try engine.mergeRemoteLogs(remoteLogs, remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].id == "normal-log-2")
    }

    @Test func mergeRemoteTrips_independentOfLogs() throws {
        // Verify that trip merge works even if log merge was never called
        let (engine, context, container) = try makeSUT()
        _ = container

        let remoteTrips = [
            RemoteTrip(id: "trip-1", name: "Solo Trip", createdBy: "user-1",
                       createdAt: fixedDate(), updatedAt: fixedDate()),
        ]

        try engine.mergeRemoteTrips(remoteTrips)

        let trips = try context.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
        #expect(trips[0].name == "Solo Trip")

        // No logs should exist
        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.isEmpty)
    }

    @Test func mergeRemoteLogs_legacySolidStringDecodesAsOkay() throws {
        let (engine, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.place(id: "place-1"))
        try context.save()

        let remote = RemoteLog(
            id: "legacy-1",
            userID: "user-1",
            placeID: "place-1",
            rating: "solid",
            createdAt: fixedDate(),
            updatedAt: fixedDate()
        )

        try engine.mergeRemoteLogs([remote], remotePlaces: [])

        let logs = try context.fetch(FetchDescriptor<Log>())
        #expect(logs.count == 1)
        #expect(logs[0].rating == .okay)
    }
}
