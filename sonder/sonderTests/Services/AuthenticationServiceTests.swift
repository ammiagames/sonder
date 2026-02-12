import Testing
import Foundation
@testable import sonder

@Suite(.serialized)
@MainActor
struct AuthenticationServiceTests {

    @Test func generateUsername_basic() {
        let service = AuthenticationService()
        let username = service.generateUsername(from: "alice@example.com")
        #expect(username == "alice")
    }

    @Test func generateUsername_specialChars() {
        let service = AuthenticationService()
        let username = service.generateUsername(from: "alice.bob+test@example.com")
        #expect(username == "alicebobtest")
    }

    @Test func generateUsername_uppercase() {
        let service = AuthenticationService()
        let username = service.generateUsername(from: "Alice@example.com")
        #expect(username == "alice")
    }

    @Test func generateUsername_noAtSign() {
        let service = AuthenticationService()
        let username = service.generateUsername(from: "noemail")
        #expect(username == "noemail")
    }
}
