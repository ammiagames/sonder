import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct SocialServiceTests {

    private func makeSUT() throws -> (SocialService, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let service = SocialService(modelContext: context)
        return (service, context, container)
    }

    @Test func isFollowing_true() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive

        let follow = TestData.follow(followerID: "u1", followingID: "u2")
        context.insert(follow)
        try context.save()

        #expect(service.isFollowing(userID: "u2", currentUserID: "u1") == true)
    }

    @Test func isFollowing_false() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        #expect(service.isFollowing(userID: "u2", currentUserID: "u1") == false)
    }

    @Test func isFollowing_wrongDirection() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive

        let follow = TestData.follow(followerID: "u1", followingID: "u2")
        context.insert(follow)
        try context.save()

        #expect(service.isFollowing(userID: "u1", currentUserID: "u2") == false)
    }
}
