//
//  SyncEngine.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData
import Supabase
import Network

/// Plain Codable struct for decoding logs from Supabase (avoids @Model decode issues)
struct RemoteLog: Codable {
    let id: String
    let userID: String
    let placeID: String
    let rating: String
    let photoURLs: [String]
    let note: String?
    let tags: [String]
    let tripID: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case placeID = "place_id"
        case rating
        case photoURLs = "photo_urls"
        case photoURL = "photo_url" // Legacy key for decoder fallback
        case note
        case tags
        case tripID = "trip_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        userID: String,
        placeID: String,
        rating: String,
        photoURLs: [String] = [],
        note: String? = nil,
        tags: [String] = [],
        tripID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.placeID = placeID
        self.rating = rating
        self.photoURLs = photoURLs
        self.note = note
        self.tags = tags
        self.tripID = tripID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userID = try container.decode(String.self, forKey: .userID)
        placeID = try container.decode(String.self, forKey: .placeID)
        rating = try container.decode(String.self, forKey: .rating)

        // Try new format first, fall back to old single-photo for migration
        if let urls = try container.decodeIfPresent([String].self, forKey: .photoURLs) {
            photoURLs = urls
        } else if let single = try container.decodeIfPresent(String.self, forKey: .photoURL) {
            photoURLs = [single]
        } else {
            photoURLs = []
        }

        note = try container.decodeIfPresent(String.self, forKey: .note)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        tripID = try container.decodeIfPresent(String.self, forKey: .tripID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(placeID, forKey: .placeID)
        try container.encode(rating, forKey: .rating)
        try container.encode(photoURLs, forKey: .photoURLs)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(tripID, forKey: .tripID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Plain Codable struct for decoding trips from Supabase (avoids @Model decode issues)
struct RemoteTrip: Codable {
    let id: String
    let name: String
    let tripDescription: String?
    let coverPhotoURL: String?
    let startDate: Date?
    let endDate: Date?
    let collaboratorIDs: [String]
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case tripDescription = "description"
        case coverPhotoURL = "cover_photo_url"
        case startDate = "start_date"
        case endDate = "end_date"
        case collaboratorIDs = "collaborator_ids"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String,
        name: String,
        tripDescription: String? = nil,
        coverPhotoURL: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        collaboratorIDs: [String] = [],
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tripDescription = tripDescription
        self.coverPhotoURL = coverPhotoURL
        self.startDate = startDate
        self.endDate = endDate
        self.collaboratorIDs = collaboratorIDs
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tripDescription = try container.decodeIfPresent(String.self, forKey: .tripDescription)
        coverPhotoURL = try container.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        collaboratorIDs = try container.decodeIfPresent([String].self, forKey: .collaboratorIDs) ?? []
        createdBy = try container.decode(String.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

@MainActor
@Observable
final class SyncEngine {
    var isSyncing = false
    var lastSyncDate: Date?
    var pendingCount = 0
    var isOnline = true

    /// Log IDs deleted locally but not yet confirmed deleted on Supabase.
    /// `mergeRemoteLogs` skips these so pull sync doesn't resurrect them.
    var pendingDeletions: Set<String> = []

    /// When true, another sync will run immediately after the current one finishes.
    private var needsResync = false

    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client
    private var syncTask: Task<Void, Never>?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sonder.networkMonitor")

    init(modelContext: ModelContext, startAutomatically: Bool = true) {
        self.modelContext = modelContext
        if startAutomatically {
            startNetworkMonitoring()
            startPeriodicSync()
        }
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            // Evaluate status on callback queue BEFORE async dispatch
            let isConnected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.handleNetworkChange(isConnected: isConnected)
                if wasOffline && isConnected {
                    await self.syncNow()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    /// Update online status. Exposed for testability and connectivity probes.
    func handleNetworkChange(isConnected: Bool) {
        guard isOnline != isConnected else { return }
        print("Network status changed: \(isConnected ? "online" : "offline")")
        isOnline = isConnected
    }

    // MARK: - Public API

    /// Sync all pending logs to Supabase and pull remote changes
    func syncNow() async {
        guard !isSyncing else {
            // A sync is already running — schedule a follow-up so new
            // pending items (e.g. a just-created log) aren't left waiting
            // for the next periodic cycle.
            needsResync = true
            return
        }
        guard isOnline else {
            print("Offline - skipping sync")
            return
        }

        // Check for valid Supabase session
        let userID: String
        do {
            let session = try await supabase.auth.session
            userID = session.user.id.uuidString
        } catch {
            print("No Supabase session - skipping sync (debug mode)")
            return
        }

        isSyncing = true

        do {
            // First, process any pending photo uploads
            await processPendingPhotoUploads()

            // Push: sync local changes to remote
            // Track failed trip IDs so we can skip logs referencing them
            // (avoids trip_activity foreign key violations)
            let failedTripIDs = try await syncPendingTrips()
            try await syncPendingLogs(skippingTripIDs: failedTripIDs)
        } catch {
            print("Push sync error: \(error)")
        }

        // Retry any remote deletions that failed previously (e.g. offline)
        await syncPendingDeletions()

        // Pull: each pull runs independently so one failure doesn't block the others
        do {
            try await pullRemoteTrips(for: userID)
        } catch {
            print("Pull trips error: \(error)")
        }

        do {
            try await pullRemoteLogs(for: userID)
        } catch {
            print("Pull logs error: \(error)")
        }

        lastSyncDate = Date()
        await updatePendingCount()

        // Clear isSyncing BEFORE the resync check so the recursive call
        // can pass the `guard !isSyncing` gate.
        isSyncing = false

        // If someone called syncNow() while we were busy, run again
        // to pick up any items created during the previous sync.
        if needsResync {
            needsResync = false
            await syncNow()
        }
    }

    /// Force a sync even if already syncing (for user-triggered refresh)
    func forceSyncNow() async {
        isSyncing = false
        await syncNow()
    }

    // MARK: - Photo Upload Coordination

    /// Batch uploads are self-managed by PhotoService; nothing to do here.
    private func processPendingPhotoUploads() async { }

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        syncTask = Task {
            // Sync immediately on start (don't wait 30s for first pull)
            await syncNow()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))

                // When offline, probe to recover from stale NWPathMonitor state
                // (the callback may not fire reliably, e.g. in the simulator)
                if !isOnline {
                    await probeConnectivity()
                }

                await syncNow()
            }
        }
    }

    /// Probe network connectivity by making a lightweight HEAD request.
    /// Handles cases where NWPathMonitor doesn't fire on reconnection.
    private func probeConnectivity() async {
        var request = URLRequest(url: SupabaseConfig.projectURL, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode > 0 {
                handleNetworkChange(isConnected: true)
            }
        } catch {
            // Still offline
        }
    }

    func stopPeriodicSync() {
        syncTask?.cancel()
        syncTask = nil
    }

    func resumePeriodicSync() {
        if syncTask == nil {
            startPeriodicSync()
        }
    }

    // MARK: - Log Sync

    private func syncPendingLogs(skippingTripIDs failedTripIDs: Set<String> = []) async throws {
        let descriptor = FetchDescriptor<Log>()
        let allLogs = try modelContext.fetch(descriptor)
        let pendingLogs = allLogs.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }

        for log in pendingLogs {
            // Skip logs that still have photos uploading in the background
            if log.photoURLs.contains(where: { $0.hasPrefix("pending-upload:") }) { continue }

            // Skip logs whose trip hasn't synced yet (prevents foreign key violations)
            if let tripID = log.tripID, failedTripIDs.contains(tripID) {
                print("Skipping log \(log.id) — trip \(tripID) hasn't synced yet")
                continue
            }

            do {
                try await uploadLog(log)
                log.syncStatus = .synced
                log.updatedAt = Date()
            } catch {
                log.syncStatus = .failed
                print("Failed to sync log \(log.id): \(error)")
            }
        }

        try modelContext.save()
    }

    private func uploadLog(_ log: Log) async throws {
        // First ensure place exists in Supabase
        try await syncPlace(placeID: log.placeID)

        // Prepare log data for upload (excluding local-only fields)
        struct LogUpload: Codable {
            let id: String
            let user_id: String
            let place_id: String
            let rating: String
            let photo_urls: [String]
            let note: String?
            let tags: [String]
            let trip_id: String?
            let created_at: Date
            let updated_at: Date
        }

        let uploadData = LogUpload(
            id: log.id,
            user_id: log.userID,
            place_id: log.placeID,
            rating: log.rating.rawValue,
            photo_urls: log.photoURLs,
            note: log.note,
            tags: log.tags,
            trip_id: log.tripID,
            created_at: log.createdAt,
            updated_at: log.updatedAt
        )

        // Then upload the log
        try await supabase
            .from("logs")
            .upsert(uploadData)
            .execute()
    }

    private func syncPlace(placeID: String) async throws {
        let placeIDCopy = placeID
        let descriptor = FetchDescriptor<Place>(
            predicate: #Predicate { place in
                place.id == placeIDCopy
            }
        )

        guard let place = try modelContext.fetch(descriptor).first else {
            throw SyncError.missingPlace
        }

        // Upsert place (insert or update if exists)
        try await supabase
            .from("places")
            .upsert(place)
            .execute()
    }

    // MARK: - Trip Sync

    /// Returns the set of trip IDs that failed to sync.
    @discardableResult
    private func syncPendingTrips() async throws -> Set<String> {
        // Only push trips owned by the current user (collaborator trips are
        // managed by their owner and would be rejected by RLS anyway).
        let session = try await supabase.auth.session
        let currentUserID = session.user.id.uuidString

        let descriptor = FetchDescriptor<Trip>()
        let trips = try modelContext.fetch(descriptor)
        let ownedTrips = trips.filter { $0.createdBy == currentUserID }

        var failedTripIDs: Set<String> = []
        for trip in ownedTrips {
            do {
                try await supabase.database
                    .from("trips")
                    .upsert(trip)
                    .execute()
            } catch {
                failedTripIDs.insert(trip.id)
                print("⚠️ Failed to sync trip '\(trip.name)' (\(trip.id)): \(error)")
            }
        }
        return failedTripIDs
    }

    // MARK: - Pull Sync

    private func pullRemoteTrips(for userID: String) async throws {
        // Fetch trips created by the user
        let ownedTrips: [RemoteTrip] = try await supabase
            .from("trips")
            .select()
            .eq("created_by", value: userID)
            .execute()
            .value
        print("Pull trips: \(ownedTrips.count) owned by \(userID)")

        var allRemoteTrips = ownedTrips

        // Also fetch trips where user is a collaborator (best-effort)
        if let collabTrips: [RemoteTrip] = try? await supabase
            .from("trips")
            .select()
            .contains("collaborator_ids", value: [userID])
            .execute()
            .value
        {
            let ownedIDs = Set(allRemoteTrips.map(\.id))
            let newCollabs = collabTrips.filter { !ownedIDs.contains($0.id) }
            allRemoteTrips += newCollabs
            print("Pull trips: \(newCollabs.count) as collaborator")
        }

        if !allRemoteTrips.isEmpty {
            try mergeRemoteTrips(allRemoteTrips)
            print("Pull trips: merged \(allRemoteTrips.count) total")
        }
    }

    /// Merge remote trips into local SwiftData store.
    /// - Remote trips not found locally are inserted.
    /// - Existing local trips are updated if the remote `updatedAt` is newer.
    func mergeRemoteTrips(_ remoteTrips: [RemoteTrip]) throws {
        let localTrips = try modelContext.fetch(FetchDescriptor<Trip>())
        var localTripsByID: [String: Trip] = [:]
        for trip in localTrips {
            let key = trip.id.lowercased()
            if let existing = localTripsByID[key] {
                // Duplicate — keep newest, remove stale
                if trip.updatedAt > existing.updatedAt {
                    modelContext.delete(existing)
                    localTripsByID[key] = trip
                } else {
                    modelContext.delete(trip)
                }
            } else {
                localTripsByID[key] = trip
            }
        }

        for remote in remoteTrips {
            if let local = localTripsByID[remote.id.lowercased()] {
                // Update if remote is newer
                if remote.updatedAt > local.updatedAt {
                    local.name = remote.name
                    local.tripDescription = remote.tripDescription
                    local.coverPhotoURL = remote.coverPhotoURL
                    local.startDate = remote.startDate
                    local.endDate = remote.endDate
                    local.collaboratorIDs = remote.collaboratorIDs
                    local.updatedAt = remote.updatedAt
                }
            } else {
                // New trip from server
                let trip = Trip(
                    id: remote.id,
                    name: remote.name,
                    tripDescription: remote.tripDescription,
                    coverPhotoURL: remote.coverPhotoURL,
                    startDate: remote.startDate,
                    endDate: remote.endDate,
                    collaboratorIDs: remote.collaboratorIDs,
                    createdBy: remote.createdBy,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt
                )
                modelContext.insert(trip)
            }
        }

        try modelContext.save()
    }

    private func pullRemoteLogs(for userID: String) async throws {
        let remoteLogs: [RemoteLog] = try await supabase
            .from("logs")
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value

        guard !remoteLogs.isEmpty else { return }

        // Find place IDs we don't have locally
        let remotePlaceIDs = Set(remoteLogs.map(\.placeID))
        let localPlaces = try modelContext.fetch(FetchDescriptor<Place>())
        let localPlaceIDs = Set(localPlaces.map(\.id))
        let missingPlaceIDs = remotePlaceIDs.subtracting(localPlaceIDs)

        // Fetch missing places from Supabase
        var fetchedPlaces: [Place] = []
        if !missingPlaceIDs.isEmpty {
            fetchedPlaces = try await supabase
                .from("places")
                .select()
                .in("id", values: Array(missingPlaceIDs))
                .execute()
                .value
        }

        try mergeRemoteLogs(remoteLogs, remotePlaces: fetchedPlaces)
    }

    /// Merge remote logs into local SwiftData store.
    /// - Remote logs not found locally are inserted as `.synced`.
    /// - Local logs with `.pending` or `.failed` status are never overwritten (preserve unsynced changes).
    /// - Local `.synced` logs are updated only if the remote `updatedAt` is newer (server wins).
    func mergeRemoteLogs(_ remoteLogs: [RemoteLog], remotePlaces: [Place]) throws {
        // Insert missing places
        for place in remotePlaces {
            modelContext.insert(place)
        }

        // Build local log lookup (lowercased keys to handle UUID case mismatch
        // between Swift's uppercase UUID().uuidString and PostgreSQL's lowercase uuid type).
        // Use reduce to handle existing duplicates gracefully — keep the newest version.
        let localLogs = try modelContext.fetch(FetchDescriptor<Log>())
        var localLogsByID: [String: Log] = [:]
        var duplicatesToRemove: [Log] = []
        for log in localLogs {
            let key = log.id.lowercased()
            if let existing = localLogsByID[key] {
                // Duplicate found — keep the one with latest updatedAt, remove the other
                if log.updatedAt > existing.updatedAt {
                    duplicatesToRemove.append(existing)
                    localLogsByID[key] = log
                } else {
                    duplicatesToRemove.append(log)
                }
            } else {
                localLogsByID[key] = log
            }
        }
        // Clean up any existing duplicates from prior UUID case-mismatch bug
        for dup in duplicatesToRemove {
            modelContext.delete(dup)
        }

        for remote in remoteLogs {
            let remoteID = remote.id.lowercased()

            // Skip logs that were deleted locally but not yet confirmed on Supabase
            if pendingDeletions.contains(remoteID) { continue }

            if let local = localLogsByID[remoteID] {
                switch local.syncStatus {
                case .pending, .failed:
                    // Preserve unsynced local changes
                    continue
                case .synced:
                    // Server wins if newer
                    if remote.updatedAt > local.updatedAt {
                        local.rating = Rating(rawValue: remote.rating) ?? local.rating
                        local.photoURLs = remote.photoURLs
                        local.note = remote.note
                        local.tags = remote.tags
                        local.tripID = remote.tripID
                        local.updatedAt = remote.updatedAt
                    }
                }
            } else {
                // New log from server
                let log = Log(
                    id: remote.id,
                    userID: remote.userID,
                    placeID: remote.placeID,
                    rating: Rating(rawValue: remote.rating) ?? .solid,
                    photoURLs: remote.photoURLs,
                    note: remote.note,
                    tags: remote.tags,
                    tripID: remote.tripID,
                    syncStatus: .synced,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt
                )
                modelContext.insert(log)
            }
        }

        try modelContext.save()
    }

    // MARK: - Delete Sync

    /// Delete a log from both local SwiftData and Supabase.
    /// Accepts a log ID so callers don't need to hold a live model reference
    /// (avoids stale-object issues when called after a navigation pop).
    /// Handles offline gracefully: the local delete is immediate, the remote
    /// delete is retried on subsequent syncs, and pull sync won't re-insert it.
    func deleteLog(id logID: String) async {
        pendingDeletions.insert(logID.lowercased())

        // Fetch fresh from context to avoid stale model references
        let idToDelete = logID
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { log in
                log.id == idToDelete
            }
        )
        if let log = try? modelContext.fetch(descriptor).first {
            // Resolve lazy attribute faults before deletion to prevent
            // "detached backing data" crashes in observing views.
            _ = log.photoURLs
            _ = log.tags
            modelContext.delete(log)
            try? modelContext.save()
        }

        // Then delete from Supabase
        do {
            try await supabase
                .from("logs")
                .delete()
                .eq("id", value: logID)
                .execute()
            pendingDeletions.remove(logID.lowercased())
        } catch {
            print("Failed to delete log \(logID) from Supabase: \(error)")
            // Stays in pendingDeletions for retry on next sync
        }
    }

    /// Retry any pending remote deletions that failed (e.g. device was offline).
    private func syncPendingDeletions() async {
        guard !pendingDeletions.isEmpty else { return }

        var resolved: Set<String> = []
        for logID in pendingDeletions {
            do {
                try await supabase
                    .from("logs")
                    .delete()
                    .eq("id", value: logID)
                    .execute()
                resolved.insert(logID)
            } catch {
                print("Retry delete failed for \(logID): \(error)")
            }
        }
        pendingDeletions.subtract(resolved)
    }

    // MARK: - Helpers

    func updatePendingCount() async {
        let descriptor = FetchDescriptor<Log>()
        if let allLogs = try? modelContext.fetch(descriptor) {
            pendingCount = allLogs.filter {
                ($0.syncStatus == .pending || $0.syncStatus == .failed) &&
                !$0.photoURLs.contains(where: { $0.hasPrefix("pending-upload:") })
            }.count
        }
    }

    /// Get failed logs for retry UI
    func getFailedLogs() -> [Log] {
        let descriptor = FetchDescriptor<Log>()
        guard let allLogs = try? modelContext.fetch(descriptor) else { return [] }
        return allLogs.filter { $0.syncStatus == .failed }
    }

    /// Retry a specific failed log
    func retryLog(_ log: Log) async {
        log.syncStatus = .pending
        try? modelContext.save()
        await syncNow()
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case missingPlace
    case networkError
    case invalidData

    var errorDescription: String? {
        switch self {
        case .missingPlace:
            return "Place data not found locally"
        case .networkError:
            return "Network connection error"
        case .invalidData:
            return "Invalid data format"
        }
    }
}
