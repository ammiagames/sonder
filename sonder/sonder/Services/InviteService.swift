//
//  InviteService.swift
//  sonder
//

import Foundation
import Supabase
import os

@MainActor
@Observable
final class InviteService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "InviteService")
    private let supabase = SupabaseConfig.client

    /// Number of unique invites sent by the current user
    var inviteCount: Int = 0

    /// Local cache of invited phone hashes for dedup
    var invitedPhoneHashes: Set<String> = []

    /// True when 3+ unique invites have been sent
    var hasMetRequirement: Bool { inviteCount >= 3 }

    // MARK: - Load

    /// Load the current invite count from Supabase (and cache to UserDefaults).
    func loadInviteCount(for userID: String) async {
        // Instant UI from UserDefaults
        let cached = UserDefaults.standard.integer(forKey: "invite_count_\(userID)")
        if cached > 0 { inviteCount = cached }

        // Refresh from server
        do {
            struct InviteRow: Decodable {
                let invited_phone_hash: String
            }
            let rows: [InviteRow] = try await supabase
                .from("invites")
                .select("invited_phone_hash")
                .eq("inviter_id", value: userID)
                .execute()
                .value

            invitedPhoneHashes = Set(rows.map(\.invited_phone_hash))
            inviteCount = invitedPhoneHashes.count
            UserDefaults.standard.set(inviteCount, forKey: "invite_count_\(userID)")
        } catch {
            logger.error("Failed to load invite count: \(error.localizedDescription)")
        }
    }

    // MARK: - Record Invite

    /// Records an invite. Returns the new invite count.
    /// Throws if the phone was already invited (dedup).
    func recordInvite(phoneNumber: String, userID: String) async throws -> Int {
        let normalized = ContactsService.normalizePhoneNumber(phoneNumber)
        guard !normalized.isEmpty else {
            throw InviteError.invalidPhoneNumber
        }

        let phoneHash = ContactsService.sha256Hash(normalized)

        // Local dedup check
        if invitedPhoneHashes.contains(phoneHash) {
            throw InviteError.alreadyInvited
        }

        // Call Supabase RPC
        let newCount: Int = try await supabase
            .rpc("record_invite", params: ["p_inviter_id": userID, "p_phone_hash": phoneHash])
            .execute()
            .value

        // Update local state
        invitedPhoneHashes.insert(phoneHash)
        inviteCount = newCount
        UserDefaults.standard.set(newCount, forKey: "invite_count_\(userID)")

        logger.info("Invite recorded. Count: \(newCount)")
        return newCount
    }

    /// Check if a phone number has already been invited (local cache).
    func isAlreadyInvited(phoneNumber: String) -> Bool {
        let normalized = ContactsService.normalizePhoneNumber(phoneNumber)
        guard !normalized.isEmpty else { return false }
        let hash = ContactsService.sha256Hash(normalized)
        return invitedPhoneHashes.contains(hash)
    }
}


enum InviteError: LocalizedError {
    case invalidPhoneNumber
    case alreadyInvited

    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            return "Please enter a valid phone number"
        case .alreadyInvited:
            return "You already invited this person"
        }
    }
}
