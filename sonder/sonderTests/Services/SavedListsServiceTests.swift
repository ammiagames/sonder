import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct SavedListsServiceTests {

    private func makeSUT() throws -> (SavedListsService, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let service = SavedListsService(modelContext: context)
        return (service, context, container)
    }

    @Test func getLocalLists_empty() throws {
        let (service, _, container) = try makeSUT()
        _ = container
        let lists = service.getLocalLists(for: "u1")
        #expect(lists.isEmpty)
    }

    @Test func getLocalLists_filtersUser() throws {
        let (service, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.savedList(id: "l1", userID: "u1", name: "List 1", isDefault: false))
        context.insert(TestData.savedList(id: "l2", userID: "u2", name: "List 2", isDefault: false))
        try context.save()

        let lists = service.getLocalLists(for: "u1")
        try #require(lists.count == 1)
        #expect(lists[0].id == "l1")
    }

    @Test func getLocalLists_sortedBySortOrder() throws {
        let (service, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.savedList(id: "l2", userID: "u1", name: "Second", isDefault: false, sortOrder: 1))
        context.insert(TestData.savedList(id: "l1", userID: "u1", name: "First", isDefault: false, sortOrder: 0))
        try context.save()

        let lists = service.getLocalLists(for: "u1")
        try #require(lists.count == 2)
        #expect(lists[0].id == "l1")
        #expect(lists[1].id == "l2")
    }

    @Test func getLocalLists_excludesDefaultLists() throws {
        let (service, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.savedList(id: "l1", userID: "u1", name: "Want to Go", isDefault: true))
        context.insert(TestData.savedList(id: "l2", userID: "u1", name: "Custom", isDefault: false))
        try context.save()

        let lists = service.getLocalLists(for: "u1")
        try #require(lists.count == 1)
        #expect(lists[0].id == "l2")
    }

    @Test func placeCount_countsCorrectly() throws {
        let (service, context, container) = try makeSUT()
        _ = container

        context.insert(TestData.wantToGo(id: "w1", userID: "u1", placeID: "p1", listID: "l1"))
        context.insert(TestData.wantToGo(id: "w2", userID: "u1", placeID: "p2", listID: "l1"))
        context.insert(TestData.wantToGo(id: "w3", userID: "u1", placeID: "p3", listID: "l2"))
        try context.save()

        #expect(service.placeCount(for: "l1", userID: "u1") == 2)
        #expect(service.placeCount(for: "l2", userID: "u1") == 1)
        #expect(service.placeCount(for: "l3", userID: "u1") == 0)
    }
}
