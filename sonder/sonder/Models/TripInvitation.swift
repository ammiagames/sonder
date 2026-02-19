//
//  TripInvitation.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import Foundation
import SwiftData

enum InvitationStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case declined
}

@Model
final class TripInvitation {
    #Index<TripInvitation>([\.tripID], [\.inviteeID])

    @Attribute(.unique) var id: String
    var tripID: String
    var inviterID: String
    var inviteeID: String
    var status: InvitationStatus
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        tripID: String,
        inviterID: String,
        inviteeID: String,
        status: InvitationStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tripID = tripID
        self.inviterID = inviterID
        self.inviteeID = inviteeID
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Codable for Supabase sync
extension TripInvitation: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case inviterID = "inviter_id"
        case inviteeID = "invitee_id"
        case status
        case createdAt = "created_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let tripID = try container.decode(String.self, forKey: .tripID)
        let inviterID = try container.decode(String.self, forKey: .inviterID)
        let inviteeID = try container.decode(String.self, forKey: .inviteeID)
        let statusString = try container.decode(String.self, forKey: .status)
        let status = InvitationStatus(rawValue: statusString) ?? .pending
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        self.init(
            id: id,
            tripID: tripID,
            inviterID: inviterID,
            inviteeID: inviteeID,
            status: status,
            createdAt: createdAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tripID, forKey: .tripID)
        try container.encode(inviterID, forKey: .inviterID)
        try container.encode(inviteeID, forKey: .inviteeID)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Invitation with details for UI
struct TripInvitationWithDetails: Identifiable {
    let invitation: TripInvitation
    let trip: Trip
    let inviter: User

    var id: String { invitation.id }
}
