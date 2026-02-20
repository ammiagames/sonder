//
//  TripService.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import Foundation
import SwiftData
import Supabase
import os

@MainActor
@Observable
final class TripService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "TripService")
    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - CRUD Operations

    /// Create a new trip
    func createTrip(
        name: String,
        description: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        coverPhotoURL: String? = nil,
        createdBy: String
    ) async throws -> Trip {
        let trip = Trip(
            name: name,
            tripDescription: description,
            coverPhotoURL: coverPhotoURL,
            startDate: startDate,
            endDate: endDate,
            collaboratorIDs: [],
            createdBy: createdBy,
            syncStatus: .pending
        )

        // Save locally first so the trip is never lost
        modelContext.insert(trip)
        try modelContext.save()

        // Then sync to Supabase (SyncEngine will retry if this fails)
        do {
            try await supabase
                .from("trips")
                .upsert(trip)
                .execute()
            trip.syncStatus = .synced
            try? modelContext.save()
        } catch {
            logger.warning("Trip created locally, Supabase sync will retry: \(error.localizedDescription)")
        }

        return trip
    }

    /// Update an existing trip
    func updateTrip(_ trip: Trip) async throws {
        trip.updatedAt = Date()
        trip.syncStatus = .pending

        // Save locally first
        try modelContext.save()

        // Then sync to Supabase (SyncEngine will retry if this fails)
        do {
            try await supabase
                .from("trips")
                .upsert(trip)
                .execute()
            trip.syncStatus = .synced
            try? modelContext.save()
        } catch {
            logger.warning("Trip updated locally, Supabase sync will retry: \(error.localizedDescription)")
        }
    }

    /// Delete a trip
    func deleteTrip(_ trip: Trip) async throws {
        // First, unassign all logs from this trip
        let tripID = trip.id
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { log in
                log.tripID == tripID
            }
        )

        let logs = try modelContext.fetch(descriptor)
        for log in logs {
            log.tripID = nil
            log.updatedAt = Date()
        }

        // Delete from Supabase
        try await supabase
            .from("trips")
            .delete()
            .eq("id", value: trip.id)
            .execute()

        // Delete locally
        modelContext.delete(trip)
        try modelContext.save()
    }

    /// Delete a trip and all its logs
    func deleteTripAndLogs(_ trip: Trip, syncEngine: SyncEngine) async throws {
        let tripID = trip.id
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { log in
                log.tripID == tripID
            }
        )

        let logs = try modelContext.fetch(descriptor)
        for log in logs {
            await syncEngine.deleteLog(id: log.id)
        }

        // Delete trip from Supabase
        try await supabase
            .from("trips")
            .delete()
            .eq("id", value: trip.id)
            .execute()

        // Delete locally
        modelContext.delete(trip)
        try modelContext.save()
    }

    // MARK: - Fetch Operations

    /// Fetch all trips for a user (owned + collaborating)
    func fetchTrips(for userID: String) async throws -> [Trip] {
        // Fetch from Supabase
        let trips: [Trip] = try await supabase
            .from("trips")
            .select()
            .or("created_by.eq.\(userID),collaborator_ids.cs.{\(userID)}")
            .order("created_at", ascending: false)
            .execute()
            .value

        // Update local cache
        for trip in trips {
            // Check if exists locally
            let tripID = trip.id
            let descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { t in t.id == tripID }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                // Update existing
                existing.name = trip.name
                existing.tripDescription = trip.tripDescription
                existing.coverPhotoURL = trip.coverPhotoURL
                existing.startDate = trip.startDate
                existing.endDate = trip.endDate
                existing.collaboratorIDs = trip.collaboratorIDs
                existing.updatedAt = trip.updatedAt
            } else {
                // Insert new
                modelContext.insert(trip)
            }
        }

        try modelContext.save()
        return trips
    }

    /// Fetch a single trip by ID
    func fetchTrip(id: String) async throws -> Trip? {
        let trips: [Trip] = try await supabase
            .from("trips")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        return trips.first
    }

    /// Get logs for a trip
    func getLogsForTrip(_ tripID: String) -> [Log] {
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { log in
                log.tripID == tripID
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Invitation Management

    /// Send an invitation to a user to join a trip
    func sendInvitation(to userID: String, for trip: Trip, from inviterID: String) async throws {
        // Check if already a collaborator
        guard !trip.collaboratorIDs.contains(userID) else { return }
        guard trip.createdBy != userID else { return } // Can't invite owner

        // Check for existing pending invitation
        let existingInvitations: [TripInvitation] = try await supabase
            .from("trip_invitations")
            .select()
            .eq("trip_id", value: trip.id)
            .eq("invitee_id", value: userID)
            .eq("status", value: "pending")
            .execute()
            .value

        guard existingInvitations.isEmpty else { return } // Already invited

        // Create invitation
        let invitation = TripInvitation(
            tripID: trip.id,
            inviterID: inviterID,
            inviteeID: userID
        )

        // Save to Supabase
        try await supabase
            .from("trip_invitations")
            .insert(invitation)
            .execute()

        // Save locally
        modelContext.insert(invitation)
        try modelContext.save()
    }

    /// Fetch pending invitations for a user (as invitee)
    func fetchPendingInvitations(for userID: String) async throws -> [TripInvitation] {
        let invitations: [TripInvitation] = try await supabase
            .from("trip_invitations")
            .select()
            .eq("invitee_id", value: userID)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value

        return invitations
    }

    /// Fetch pending invitations for a trip (as owner viewing who's invited)
    func fetchPendingInvitationsForTrip(_ tripID: String) async throws -> [TripInvitation] {
        let invitations: [TripInvitation] = try await supabase
            .from("trip_invitations")
            .select()
            .eq("trip_id", value: tripID)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value

        return invitations
    }

    /// Fetch pending invitations with trip and inviter details
    func fetchPendingInvitationsWithDetails(for userID: String, socialService: SocialService) async throws -> [TripInvitationWithDetails] {
        let invitations = try await fetchPendingInvitations(for: userID)

        var results: [TripInvitationWithDetails] = []

        for invitation in invitations {
            // Fetch trip
            guard let trip = try await fetchTrip(id: invitation.tripID) else { continue }

            // Fetch inviter
            guard let inviter = try await socialService.getUser(id: invitation.inviterID) else { continue }

            results.append(TripInvitationWithDetails(
                invitation: invitation,
                trip: trip,
                inviter: inviter
            ))
        }

        return results
    }

    /// Accept an invitation
    func acceptInvitation(_ invitation: TripInvitation) async throws {
        // Update invitation status
        struct StatusUpdate: Codable {
            let status: String
        }

        try await supabase
            .from("trip_invitations")
            .update(StatusUpdate(status: "accepted"))
            .eq("id", value: invitation.id)
            .execute()

        // Add user to trip collaborators
        guard let trip = try await fetchTrip(id: invitation.tripID) else { return }

        try await addCollaborator(userID: invitation.inviteeID, to: trip)

        // Update local invitation
        invitation.status = .accepted
        try modelContext.save()
    }

    /// Decline an invitation
    func declineInvitation(_ invitation: TripInvitation) async throws {
        struct StatusUpdate: Codable {
            let status: String
        }

        try await supabase
            .from("trip_invitations")
            .update(StatusUpdate(status: "declined"))
            .eq("id", value: invitation.id)
            .execute()

        // Update local invitation
        invitation.status = .declined
        try modelContext.save()
    }

    /// Get count of pending invitations for a user
    func getPendingInvitationCount(for userID: String) async throws -> Int {
        let invitations = try await fetchPendingInvitations(for: userID)
        return invitations.count
    }

    // MARK: - Collaborator Management

    /// Add a user as collaborator (internal - called after invitation accepted)
    private func addCollaborator(userID: String, to trip: Trip) async throws {
        guard !trip.collaboratorIDs.contains(userID) else { return }

        trip.collaboratorIDs.append(userID)
        trip.updatedAt = Date()
        trip.syncStatus = .pending

        // Sync to Supabase
        struct CollaboratorUpdate: Codable {
            let collaborator_ids: [String]
            let updated_at: Date
        }

        try await supabase
            .from("trips")
            .update(CollaboratorUpdate(collaborator_ids: trip.collaboratorIDs, updated_at: trip.updatedAt))
            .eq("id", value: trip.id)
            .execute()

        // Update local trip
        let tripID = trip.id
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { t in t.id == tripID }
        )

        if let localTrip = try modelContext.fetch(descriptor).first {
            localTrip.collaboratorIDs = trip.collaboratorIDs
            localTrip.updatedAt = trip.updatedAt
        } else {
            modelContext.insert(trip)
        }

        try modelContext.save()
    }

    /// Remove a collaborator from a trip
    func removeCollaborator(userID: String, from trip: Trip) async throws {
        trip.collaboratorIDs.removeAll { $0 == userID }
        trip.updatedAt = Date()
        trip.syncStatus = .pending

        try modelContext.save()

        // Sync to Supabase
        struct CollaboratorUpdate: Codable {
            let collaborator_ids: [String]
            let updated_at: Date
        }

        try await supabase
            .from("trips")
            .update(CollaboratorUpdate(collaborator_ids: trip.collaboratorIDs, updated_at: trip.updatedAt))
            .eq("id", value: trip.id)
            .execute()
    }

    /// Leave a trip (for collaborators)
    func leaveTrip(_ trip: Trip, userID: String) async throws {
        try await removeCollaborator(userID: userID, from: trip)
    }

    // MARK: - Log Association

    /// Associate a log with a trip
    func associateLog(_ log: Log, with trip: Trip?) async throws {
        log.tripID = trip?.id
        log.updatedAt = Date()

        try modelContext.save()

        // Sync to Supabase
        struct LogTripUpdate: Codable {
            let trip_id: String?
            let updated_at: Date
        }

        try await supabase
            .from("logs")
            .update(LogTripUpdate(trip_id: trip?.id, updated_at: log.updatedAt))
            .eq("id", value: log.id)
            .execute()
    }

    /// Associate multiple orphaned logs with a trip in batch
    func associateLogs(ids logIDs: Set<String>, with trip: Trip) async throws {
        let allLogs = try modelContext.fetch(FetchDescriptor<Log>())
        let allTripIDs = Set(try modelContext.fetch(FetchDescriptor<Trip>()).map(\.id))
        let logsToAssign = allLogs.filter {
            logIDs.contains($0.id) && ($0.tripID.map { !allTripIDs.contains($0) } ?? true)
        }

        for log in logsToAssign {
            log.tripID = trip.id
            log.updatedAt = Date()
        }
        try modelContext.save()

        // Sync each to Supabase
        struct LogTripUpdate: Codable {
            let trip_id: String?
            let updated_at: Date
        }

        for log in logsToAssign {
            do {
                try await supabase
                    .from("logs")
                    .update(LogTripUpdate(trip_id: trip.id, updated_at: log.updatedAt))
                    .eq("id", value: log.id)
                    .execute()
            } catch {
                log.syncStatus = .pending
                logger.warning("Log \(log.id) trip association will retry: \(error.localizedDescription)")
            }
        }

        try modelContext.save()
    }

    // MARK: - Helpers

    /// Check if user can edit trip (owner only)
    func canEdit(trip: Trip, userID: String) -> Bool {
        trip.createdBy == userID
    }

    /// Check if user is a collaborator
    func isCollaborator(trip: Trip, userID: String) -> Bool {
        trip.collaboratorIDs.contains(userID)
    }

    /// Check if user has access to trip
    func hasAccess(trip: Trip, userID: String) -> Bool {
        trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
    }
}
