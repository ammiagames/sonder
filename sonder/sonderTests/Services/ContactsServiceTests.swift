import Testing
import Foundation
@testable import sonder

@MainActor
struct ContactsServiceTests {

    // MARK: - normalizePhoneNumber

    @Test func normalizeUS10Digit() {
        let result = ContactsService.normalizePhoneNumber("(212) 555-1234")
        #expect(result == "+12125551234")
    }

    @Test func normalizeUS11DigitWithLeading1() {
        let result = ContactsService.normalizePhoneNumber("1-212-555-1234")
        #expect(result == "+12125551234")
    }

    @Test func normalizeAlreadyE164() {
        let result = ContactsService.normalizePhoneNumber("+12125551234")
        #expect(result == "+12125551234")
    }

    @Test func normalizeInternational() {
        let result = ContactsService.normalizePhoneNumber("+44 20 7946 0958")
        #expect(result == "+442079460958")
    }

    @Test func normalizeTooShort() {
        let result = ContactsService.normalizePhoneNumber("555-1234")
        #expect(result == "")
    }

    @Test func normalizeEmptyString() {
        let result = ContactsService.normalizePhoneNumber("")
        #expect(result == "")
    }

    // MARK: - sha256Hash

    @Test func sha256HashDeterministic() {
        let hash1 = ContactsService.sha256Hash("+12125551234")
        let hash2 = ContactsService.sha256Hash("+12125551234")
        #expect(hash1 == hash2)
    }

    @Test func sha256HashIs64CharHex() {
        let hash = ContactsService.sha256Hash("+12125551234")
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test func sha256HashDifferentInputsDifferentOutputs() {
        let hash1 = ContactsService.sha256Hash("+12125551234")
        let hash2 = ContactsService.sha256Hash("+14155559876")
        #expect(hash1 != hash2)
    }

    @Test func sha256HashKnownValue() {
        // SHA256 of "hello" is well-known
        let hash = ContactsService.sha256Hash("hello")
        #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
