import Testing
import Foundation
@testable import sonder

struct TripInvitationTests {

    @Test func initDefaults() {
        let invitation = TripInvitation(
            tripID: "trip-1",
            inviterID: "u1",
            inviteeID: "u2"
        )

        #expect(!invitation.id.isEmpty)
        #expect(invitation.status == .pending)
    }

    @Test func invitationStatusRawValues() {
        #expect(InvitationStatus.pending.rawValue == "pending")
        #expect(InvitationStatus.accepted.rawValue == "accepted")
        #expect(InvitationStatus.declined.rawValue == "declined")
    }

    @Test func invitationStatusCaseIterable() {
        #expect(InvitationStatus.allCases.count == 3)
    }

    @Test func encodeThenDecode() throws {
        let invitation = TestData.tripInvitation(
            id: "inv-1",
            tripID: "trip-1",
            inviterID: "u1",
            inviteeID: "u2",
            status: .accepted
        )

        let data = try makeEncoder().encode(invitation)
        let decoded = try makeDecoder().decode(TripInvitation.self, from: data)

        #expect(decoded.id == "inv-1")
        #expect(decoded.tripID == "trip-1")
        #expect(decoded.inviterID == "u1")
        #expect(decoded.inviteeID == "u2")
        #expect(decoded.status == .accepted)
    }

    @Test func withDetailsIdDelegation() {
        let invitation = TestData.tripInvitation(id: "inv-99")
        let trip = TestData.trip()
        let inviter = TestData.user()

        let details = TripInvitationWithDetails(
            invitation: invitation,
            trip: trip,
            inviter: inviter
        )

        #expect(details.id == "inv-99")
    }
}
