import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct WantToGoServiceTests {

    private func makeSUT() throws -> (WantToGoService, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let service = WantToGoService(modelContext: context)
        return (service, context, container)
    }

    @Test func isInWantToGo_empty() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == false)
    }

    @Test func isInWantToGo_found() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let item = TestData.wantToGo(userID: "u1", placeID: "p1")
        service.items = [item]

        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == true)
    }

    @Test func isInWantToGo_wrongUser() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let item = TestData.wantToGo(userID: "u1", placeID: "p1")
        service.items = [item]

        #expect(service.isInWantToGo(placeID: "p1", userID: "u2") == false)
    }

    @Test func getWantToGoList_filtersUser() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive

        context.insert(TestData.wantToGo(id: "w1", userID: "u1", placeID: "p1"))
        context.insert(TestData.wantToGo(id: "w2", userID: "u1", placeID: "p2"))
        context.insert(TestData.wantToGo(id: "w3", userID: "u2", placeID: "p3"))
        try context.save()

        let results = service.getWantToGoList(for: "u1")
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.userID == "u1" })
    }

    @Test func getWantToGoList_sorted() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive

        let older = fixedDate()
        let newer = older.addingTimeInterval(3600)

        context.insert(TestData.wantToGo(id: "w-old", userID: "u1", placeID: "p1", createdAt: older))
        context.insert(TestData.wantToGo(id: "w-new", userID: "u1", placeID: "p2", createdAt: newer))
        try context.save()

        let results = service.getWantToGoList(for: "u1")
        #expect(results.count == 2)
        #expect(results[0].id == "w-new")
        #expect(results[1].id == "w-old")
    }
}
