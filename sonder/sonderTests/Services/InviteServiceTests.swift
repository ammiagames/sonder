import Testing
import Foundation
@testable import sonder

@MainActor
struct InviteServiceTests {

    // MARK: - Initial State

    @Test func initialStateIsEmpty() {
        let service = InviteService()
        #expect(service.inviteCount == 0)
        #expect(service.invitedPhoneHashes.isEmpty)
        #expect(!service.hasMetRequirement)
    }

    @Test func hasMetRequirementFalseUnder3() {
        let service = InviteService()
        service.inviteCount = 2
        #expect(!service.hasMetRequirement)
    }

    @Test func hasMetRequirementTrueAt3() {
        let service = InviteService()
        service.inviteCount = 3
        #expect(service.hasMetRequirement)
    }

    @Test func hasMetRequirementTrueAbove3() {
        let service = InviteService()
        service.inviteCount = 5
        #expect(service.hasMetRequirement)
    }

    // MARK: - isAlreadyInvited

    @Test func isAlreadyInvitedReturnsFalseForNewNumber() {
        let service = InviteService()
        #expect(!service.isAlreadyInvited(phoneNumber: "+12125551234"))
    }

    @Test func isAlreadyInvitedReturnsTrueForKnownHash() {
        let service = InviteService()
        let hash = ContactsService.sha256Hash("+12125551234")
        service.invitedPhoneHashes.insert(hash)
        #expect(service.isAlreadyInvited(phoneNumber: "+12125551234"))
    }

    @Test func isAlreadyInvitedNormalizesBeforeHashing() {
        let service = InviteService()
        // Insert the normalized hash
        let hash = ContactsService.sha256Hash("+12125551234")
        service.invitedPhoneHashes.insert(hash)
        // Pass unnormalized — should still match
        #expect(service.isAlreadyInvited(phoneNumber: "(212) 555-1234"))
    }

    @Test func isAlreadyInvitedReturnsFalseForEmptyInput() {
        let service = InviteService()
        #expect(!service.isAlreadyInvited(phoneNumber: ""))
    }

    @Test func isAlreadyInvitedReturnsFalseForInvalidInput() {
        let service = InviteService()
        #expect(!service.isAlreadyInvited(phoneNumber: "123"))
    }

    // MARK: - recordInvite validation (offline — no Supabase)

    @Test func recordInviteThrowsForEmptyPhone() async {
        let service = InviteService()
        do {
            _ = try await service.recordInvite(phoneNumber: "", userID: "test-user")
            Issue.record("Expected InviteError.invalidPhoneNumber")
        } catch let error as InviteError {
            #expect(error == .invalidPhoneNumber)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func recordInviteThrowsForTooShortPhone() async {
        let service = InviteService()
        do {
            _ = try await service.recordInvite(phoneNumber: "123", userID: "test-user")
            Issue.record("Expected InviteError.invalidPhoneNumber")
        } catch let error as InviteError {
            #expect(error == .invalidPhoneNumber)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func recordInviteThrowsForAlreadyInvited() async {
        let service = InviteService()
        let hash = ContactsService.sha256Hash("+12125551234")
        service.invitedPhoneHashes.insert(hash)

        do {
            _ = try await service.recordInvite(phoneNumber: "+12125551234", userID: "test-user")
            Issue.record("Expected InviteError.alreadyInvited")
        } catch let error as InviteError {
            #expect(error == .alreadyInvited)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - InviteError Tests

@MainActor
struct InviteErrorTests {

    @Test func errorDescriptions() {
        #expect(InviteError.invalidPhoneNumber.errorDescription != nil)
        #expect(InviteError.alreadyInvited.errorDescription != nil)
    }

    @Test func errorsAreEquatable() {
        #expect(InviteError.invalidPhoneNumber == InviteError.invalidPhoneNumber)
        #expect(InviteError.alreadyInvited == InviteError.alreadyInvited)
        #expect(InviteError.invalidPhoneNumber != InviteError.alreadyInvited)
    }
}
