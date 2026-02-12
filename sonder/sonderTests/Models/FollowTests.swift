import Testing
import Foundation
@testable import sonder

struct FollowTests {

    @Test func initStoresValues() {
        let date = fixedDate()
        let follow = Follow(followerID: "u1", followingID: "u2", createdAt: date)

        #expect(follow.followerID == "u1")
        #expect(follow.followingID == "u2")
        #expect(follow.createdAt == date)
    }

    @Test func encodeThenDecode() throws {
        let follow = TestData.follow(followerID: "u1", followingID: "u2")

        let data = try makeEncoder().encode(follow)
        let decoded = try makeDecoder().decode(Follow.self, from: data)

        #expect(decoded.followerID == "u1")
        #expect(decoded.followingID == "u2")
    }

    @Test func encodeProducesSnakeCaseKeys() throws {
        let follow = TestData.follow()
        let data = try makeEncoder().encode(follow)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["follower_id"] != nil)
        #expect(json["following_id"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["followerID"] == nil)
        #expect(json["followingID"] == nil)
    }
}
