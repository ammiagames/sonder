//
//  ContactsService.swift
//  sonder
//

import Foundation
import Contacts
import CryptoKit
import Supabase
import os

@MainActor
@Observable
final class ContactsService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "ContactsService")

    // MARK: - Types

    struct ContactMatch: Identifiable {
        var id: String { user.id }
        let user: User
        let contactName: String
    }

    struct UnmatchedContact: Identifiable {
        let id: UUID
        let name: String
        let phoneNumber: String
    }

    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case denied
    }

    // MARK: - State

    private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    var matchedUsers: [ContactMatch] = []
    var unmatchedContacts: [UnmatchedContact] = []
    var isLoading = false

    private let contactStore = CNContactStore()
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Authorization

    func checkCurrentStatus() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            authorizationStatus = .authorized
        case .denied, .restricted:
            authorizationStatus = .denied
        case .notDetermined:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            authorizationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            logger.error("Contacts access request failed: \(error.localizedDescription)")
            authorizationStatus = .denied
            return false
        }
    }

    // MARK: - Contact Matching

    func findContactsOnSonder(excludeUserID: String) async {
        // Check cache
        if let lastFetch = lastFetchTime, Date().timeIntervalSince(lastFetch) < cacheDuration,
           !matchedUsers.isEmpty || !unmatchedContacts.isEmpty {
            return
        }

        guard authorizationStatus == .authorized else { return }

        isLoading = true
        defer { isLoading = false }

        // 1. Fetch device contacts
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        var deviceContacts: [(name: String, phones: [String])] = []

        do {
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            try contactStore.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let phones = contact.phoneNumbers.map { $0.value.stringValue }
                if !phones.isEmpty && !name.isEmpty {
                    deviceContacts.append((name: name, phones: phones))
                }
            }
        } catch {
            logger.error("Failed to fetch contacts: \(error.localizedDescription)")
            return
        }

        // 2. Normalize and hash all phone numbers
        var hashToContact: [String: (name: String, phone: String)] = [:]
        for contact in deviceContacts {
            for phone in contact.phones {
                let normalized = ContactsService.normalizePhoneNumber(phone)
                guard !normalized.isEmpty else { continue }
                let hash = ContactsService.sha256Hash(normalized)
                hashToContact[hash] = (name: contact.name, phone: normalized)
            }
        }

        guard !hashToContact.isEmpty else {
            matchedUsers = []
            unmatchedContacts = []
            lastFetchTime = Date()
            return
        }

        // 3. Send hashes to Supabase RPC in batches
        let allHashes = Array(hashToContact.keys)
        var matchedUserResults: [User] = []

        let batchSize = 1000
        for batchStart in stride(from: 0, to: allHashes.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allHashes.count)
            let batch = Array(allHashes[batchStart..<batchEnd])

            do {
                let users: [User] = try await SupabaseConfig.client
                    .rpc("match_phone_hashes", params: ["hashes": batch])
                    .execute()
                    .value
                matchedUserResults.append(contentsOf: users)
            } catch {
                logger.error("RPC match_phone_hashes failed: \(error.localizedDescription)")
            }
        }

        // 4. Separate into matched vs unmatched
        let matchedHashSet = Set(matchedUserResults.compactMap { $0.phoneNumberHash })

        var matched: [ContactMatch] = []
        for user in matchedUserResults where user.id != excludeUserID {
            if let hash = user.phoneNumberHash, let contact = hashToContact[hash] {
                matched.append(ContactMatch(user: user, contactName: contact.name))
            }
        }

        var unmatched: [UnmatchedContact] = []
        for (hash, contact) in hashToContact where !matchedHashSet.contains(hash) {
            unmatched.append(UnmatchedContact(
                id: UUID(),
                name: contact.name,
                phoneNumber: contact.phone
            ))
        }

        // Sort: matched by contact name, unmatched by contact name
        matchedUsers = matched.sorted { $0.contactName.localizedCaseInsensitiveCompare($1.contactName) == .orderedAscending }
        unmatchedContacts = unmatched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastFetchTime = Date()
    }

    // MARK: - Pure Utilities

    /// Normalize a raw phone number to E.164 format.
    /// For US numbers (10 digits): prepends +1. For 11-digit starting with 1: prepends +.
    /// Already has + prefix: strip non-digits after +.
    nonisolated static func normalizePhoneNumber(_ raw: String) -> String {
        // If it starts with +, keep the + and strip everything else to digits
        if raw.hasPrefix("+") {
            let digits = raw.dropFirst().filter(\.isNumber)
            guard digits.count >= 10 else { return "" }
            return "+" + digits
        }

        // Strip all non-digit characters
        let digits = raw.filter(\.isNumber)

        switch digits.count {
        case 10:
            // US number without country code
            return "+1" + digits
        case 11 where digits.hasPrefix("1"):
            // US number with leading 1
            return "+" + digits
        case let count where count >= 10:
            // Assume international with country code
            return "+" + digits
        default:
            // Too short to be a valid number
            return ""
        }
    }

    /// SHA256 hash a string, returning a 64-character lowercase hex string.
    nonisolated static func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
