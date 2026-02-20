import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct LogSnapshotTests {

    // MARK: - Init from Log

    @Test func initFromLog_capturesAllFields() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let log = TestData.log(
            id: "log-1",
            userID: "u1",
            placeID: "p1",
            rating: .mustSee,
            photoURLs: ["https://example.com/photo.jpg"],
            note: "Amazing place!",
            tags: ["food", "dinner"],
            createdAt: fixedDate()
        )
        context.insert(log)
        try context.save()

        let snapshot = LogSnapshot(from: log)

        #expect(snapshot.id == "log-1")
        #expect(snapshot.rating == .mustSee)
        #expect(snapshot.photoURL == "https://example.com/photo.jpg")
        #expect(snapshot.note == "Amazing place!")
        #expect(snapshot.tags == ["food", "dinner"])
        #expect(snapshot.createdAt == fixedDate())
    }

    @Test func initFromLog_nilOptionals() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let log = TestData.log(
            id: "log-2",
            rating: .skip,
            photoURLs: [],
            note: nil,
            tags: []
        )
        context.insert(log)
        try context.save()

        let snapshot = LogSnapshot(from: log)

        #expect(snapshot.id == "log-2")
        #expect(snapshot.rating == .skip)
        #expect(snapshot.photoURL == nil)
        #expect(snapshot.note == nil)
        #expect(snapshot.tags.isEmpty)
    }

    // MARK: - Equality

    @Test func equality_sameValues() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let log = TestData.log(id: "log-1", rating: .okay, note: "Great")
        context.insert(log)
        try context.save()

        let snap1 = LogSnapshot(from: log)
        let snap2 = LogSnapshot(from: log)

        #expect(snap1 == snap2)
    }

    @Test func equality_differentRatings() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let log1 = TestData.log(id: "log-1", rating: .okay)
        let log2 = TestData.log(id: "log-2", rating: .mustSee)
        context.insert(log1)
        context.insert(log2)
        try context.save()

        let snap1 = LogSnapshot(from: log1)
        let snap2 = LogSnapshot(from: log2)

        #expect(snap1 != snap2)
    }

    // MARK: - Snapshot survives model deletion

    @Test func snapshot_survivesLogDeletion() throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let log = TestData.log(
            id: "log-del",
            rating: .mustSee,
            photoURLs: ["https://example.com/del.jpg"],
            note: "Will be deleted"
        )
        context.insert(log)
        try context.save()

        // Take snapshot BEFORE deletion
        let snapshot = LogSnapshot(from: log)

        // Delete the log
        context.delete(log)
        try context.save()

        // Snapshot retains all values — no crash, no fault
        #expect(snapshot.id == "log-del")
        #expect(snapshot.rating == .mustSee)
        #expect(snapshot.photoURL == "https://example.com/del.jpg")
        #expect(snapshot.note == "Will be deleted")
    }
}
