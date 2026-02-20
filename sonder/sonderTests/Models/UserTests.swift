import Testing
import Foundation
@testable import sonder

struct UserTests {

    @Test func initWithAllParameters() {
        let date = fixedDate()
        let user = TestData.user(
            id: "u-1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: "https://example.com/avatar.jpg",
            bio: "Hello world",
            isPublic: false,
            createdAt: date,
            updatedAt: date
        )

        #expect(user.id == "u-1")
        #expect(user.username == "alice")
        #expect(user.email == "alice@example.com")
        #expect(user.avatarURL == "https://example.com/avatar.jpg")
        #expect(user.bio == "Hello world")
        #expect(user.isPublic == false)
        #expect(user.createdAt == date)
        #expect(user.updatedAt == date)
    }

    @Test func initDefaults() {
        let user = User(id: "u-2", username: "bob")

        #expect(user.email == nil)
        #expect(user.bio == nil)
        #expect(user.avatarURL == nil)
        #expect(user.isPublic == true)
    }

    @Test func encodeThenDecode() throws {
        let user = TestData.user(
            avatarURL: "https://example.com/pic.jpg",
            bio: "My bio"
        )

        let data = try makeEncoder().encode(user)
        let decoded = try makeDecoder().decode(User.self, from: data)

        #expect(decoded.id == user.id)
        #expect(decoded.username == user.username)
        #expect(decoded.email == user.email)
        #expect(decoded.avatarURL == user.avatarURL)
        #expect(decoded.bio == user.bio)
        #expect(decoded.isPublic == user.isPublic)
    }

    @Test func encodeProducesSnakeCaseKeys() throws {
        let user = TestData.user(avatarURL: "https://example.com/pic.jpg")
        let data = try makeEncoder().encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["avatar_url"] != nil)
        #expect(json["is_public"] != nil)
        #expect(json["created_at"] != nil)
        #expect(json["updated_at"] != nil)
        // Should NOT have camelCase keys
        #expect(json["avatarURL"] == nil)
        #expect(json["isPublic"] == nil)
    }

    @Test func decodeFromSnakeCaseJSON() throws {
        let json = """
        {
            "id": "u-3",
            "username": "charlie",
            "email": "charlie@example.com",
            "avatar_url": "https://example.com/avatar.jpg",
            "bio": "Hey",
            "is_public": false,
            "created_at": "2025-01-15T12:00:00Z",
            "updated_at": "2025-01-15T12:00:00Z"
        }
        """.data(using: .utf8)!

        let user = try makeDecoder().decode(User.self, from: json)

        #expect(user.id == "u-3")
        #expect(user.username == "charlie")
        #expect(user.email == "charlie@example.com")
        #expect(user.avatarURL == "https://example.com/avatar.jpg")
        #expect(user.bio == "Hey")
        #expect(user.isPublic == false)
    }

    @Test func decodeMissingOptionalFields() throws {
        let json = """
        {
            "id": "u-4",
            "username": "dave"
        }
        """.data(using: .utf8)!

        let user = try makeDecoder().decode(User.self, from: json)

        #expect(user.id == "u-4")
        #expect(user.username == "dave")
        #expect(user.email == nil)
        #expect(user.avatarURL == nil)
        #expect(user.bio == nil)
        #expect(user.isPublic == false) // default when missing from JSON
        #expect(user.phoneNumber == nil)
        #expect(user.phoneNumberHash == nil)
    }

    @Test func encodeDecodePhoneFields() throws {
        let user = TestData.user(
            phoneNumber: "+12125551234",
            phoneNumberHash: "a1b2c3d4e5f6"
        )

        let data = try makeEncoder().encode(user)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["phone_number"] as? String == "+12125551234")
        #expect(json["phone_number_hash"] as? String == "a1b2c3d4e5f6")

        let decoded = try makeDecoder().decode(User.self, from: data)
        #expect(decoded.phoneNumber == "+12125551234")
        #expect(decoded.phoneNumberHash == "a1b2c3d4e5f6")
    }

    @Test func decodePhoneFieldsFromJSON() throws {
        let json = """
        {
            "id": "u-5",
            "username": "eve",
            "phone_number": "+14155559876",
            "phone_number_hash": "abc123def456"
        }
        """.data(using: .utf8)!

        let user = try makeDecoder().decode(User.self, from: json)
        #expect(user.phoneNumber == "+14155559876")
        #expect(user.phoneNumberHash == "abc123def456")
    }
}
