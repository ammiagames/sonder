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

    // MARK: - Reactivity: items array drives bookmark visibility

    @Test func isInWantToGo_reactsToItemsArrayChanges() throws {
        let (service, _, container) = try makeSUT()
        _ = container

        // Initially empty — not bookmarked
        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == false)

        // Simulate adding a bookmark (as addToWantToGo does via refreshItems)
        service.items = [TestData.wantToGo(userID: "u1", placeID: "p1")]
        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == true)

        // Simulate removing the bookmark
        service.items = []
        // With empty items, falls back to DB check — which is also empty
        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == false)
    }

    // MARK: - Auto-remove on log

    @Test func removeLocalBookmark_removesFromDBAndItems() throws {
        let (service, context, container) = try makeSUT()
        _ = container

        // Insert a bookmark into SwiftData and the items cache
        let bookmark = TestData.wantToGo(id: "w1", userID: "u1", placeID: "p1")
        context.insert(bookmark)
        try context.save()
        service.items = [bookmark]

        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == true)

        // Simulate logging the place — should remove the bookmark
        service.removeLocalBookmark(placeID: "p1", userID: "u1")

        // Verify removed from items array
        #expect(service.isInWantToGo(placeID: "p1", userID: "u1") == false)

        // Verify removed from SwiftData
        let results = service.getWantToGoList(for: "u1")
        #expect(results.isEmpty)
    }

    @Test func removeLocalBookmark_noOpWhenNotBookmarked() throws {
        let (service, context, container) = try makeSUT()
        _ = container

        // Insert a bookmark for a different place
        let bookmark = TestData.wantToGo(id: "w1", userID: "u1", placeID: "p2")
        context.insert(bookmark)
        try context.save()
        service.items = [bookmark]

        // Try to remove a bookmark for p1 (not bookmarked)
        service.removeLocalBookmark(placeID: "p1", userID: "u1")

        // p2 bookmark should still exist
        #expect(service.isInWantToGo(placeID: "p2", userID: "u1") == true)
        #expect(service.getWantToGoList(for: "u1").count == 1)
    }

    @Test func placeIDs_derivedFromItems() throws {
        let (service, _, container) = try makeSUT()
        _ = container

        service.items = [
            TestData.wantToGo(userID: "u1", placeID: "p1"),
            TestData.wantToGo(userID: "u1", placeID: "p2"),
            TestData.wantToGo(userID: "u1", placeID: "p3"),
        ]

        let placeIDs = Set(service.items.map(\.placeID))
        #expect(placeIDs == Set(["p1", "p2", "p3"]))

        // After removing one
        service.items.removeAll { $0.placeID == "p2" }
        let updatedPlaceIDs = Set(service.items.map(\.placeID))
        #expect(updatedPlaceIDs == Set(["p1", "p3"]))
        #expect(!updatedPlaceIDs.contains("p2"))
    }
}
