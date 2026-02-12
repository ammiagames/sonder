import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct TripServiceLogicTests {

    private func makeSUT() throws -> (TripService, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let service = TripService(modelContext: context)
        return (service, context, container)
    }

    // MARK: - canEdit

    @Test func canEdit_owner() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(createdBy: "owner-1")
        #expect(service.canEdit(trip: trip, userID: "owner-1") == true)
    }

    @Test func canEdit_collaborator() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(collaboratorIDs: ["collab-1"], createdBy: "owner-1")
        #expect(service.canEdit(trip: trip, userID: "collab-1") == false)
    }

    @Test func canEdit_stranger() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(createdBy: "owner-1")
        #expect(service.canEdit(trip: trip, userID: "stranger") == false)
    }

    // MARK: - isCollaborator

    @Test func isCollaborator_inList() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(collaboratorIDs: ["u2", "u3"], createdBy: "u1")
        #expect(service.isCollaborator(trip: trip, userID: "u2") == true)
    }

    @Test func isCollaborator_owner() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(collaboratorIDs: ["u2"], createdBy: "u1")
        #expect(service.isCollaborator(trip: trip, userID: "u1") == false)
    }

    @Test func isCollaborator_stranger() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(collaboratorIDs: ["u2"], createdBy: "u1")
        #expect(service.isCollaborator(trip: trip, userID: "stranger") == false)
    }

    // MARK: - hasAccess

    @Test func hasAccess_owner() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(createdBy: "u1")
        #expect(service.hasAccess(trip: trip, userID: "u1") == true)
    }

    @Test func hasAccess_collaborator() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(collaboratorIDs: ["u2"], createdBy: "u1")
        #expect(service.hasAccess(trip: trip, userID: "u2") == true)
    }

    @Test func hasAccess_stranger() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let trip = TestData.trip(createdBy: "u1")
        #expect(service.hasAccess(trip: trip, userID: "stranger") == false)
    }

    // MARK: - getLogsForTrip

    @Test func getLogsForTrip_matching() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive

        let log1 = TestData.log(id: "log-1", tripID: "trip-1")
        let log2 = TestData.log(id: "log-2", tripID: "trip-1")
        let log3 = TestData.log(id: "log-3", tripID: "trip-2")

        context.insert(log1)
        context.insert(log2)
        context.insert(log3)
        try context.save()

        let results = service.getLogsForTrip("trip-1")
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.tripID == "trip-1" })
    }

    @Test func getLogsForTrip_sorted() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive

        let older = fixedDate()
        let newer = older.addingTimeInterval(3600)

        let log1 = TestData.log(id: "log-old", tripID: "trip-1", createdAt: older)
        let log2 = TestData.log(id: "log-new", tripID: "trip-1", createdAt: newer)

        context.insert(log1)
        context.insert(log2)
        try context.save()

        let results = service.getLogsForTrip("trip-1")
        #expect(results.count == 2)
        #expect(results[0].id == "log-new")
        #expect(results[1].id == "log-old")
    }

    @Test func getLogsForTrip_empty() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        let results = service.getLogsForTrip("nonexistent")
        #expect(results.isEmpty)
    }
}
