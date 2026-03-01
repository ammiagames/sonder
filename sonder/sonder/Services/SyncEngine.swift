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
import os

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
    let tripSortOrder: Int?
    let visitedAt: Date
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
        case tripSortOrder = "trip_sort_order"
        case visitedAt = "visited_at"
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
        tripSortOrder: Int? = nil,
        visitedAt: Date = Date(),
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
        self.tripSortOrder = tripSortOrder
        self.visitedAt = visitedAt
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
        tripSortOrder = try container.decodeIfPresent(Int.self, forKey: .tripSortOrder)
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        visitedAt = try container.decodeIfPresent(Date.self, forKey: .visitedAt) ?? decodedCreatedAt
        createdAt = decodedCreatedAt
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
        try container.encodeIfPresent(tripSortOrder, forKey: .tripSortOrder)
        try container.encode(visitedAt, forKey: .visitedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

@MainActor
@Observable
final class SyncEngine {
    private let logger = Logger(subsystem: "com.sonder.app", category: "SyncEngine")
    private(set) var isSyncing = false
    @ObservationIgnored var lastSyncDate: Date?
    private(set) var pendingCount = 0
    var isOnline = true

    /// Log IDs deleted locally but not yet confirmed deleted on Supabase.
    /// `mergeRemoteLogs` skips these so pull sync doesn't resurrect them.
    /// Persisted to UserDefaults so deletions survive app crashes.
    @ObservationIgnored var pendingDeletions: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "sonder.sync.pendingDeletions") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "sonder.sync.pendingDeletions") }
    }

    /// When true, another sync will run immediately after the current one finishes.
    private var needsResync = false

    /// Cursor for incremental log pulls — only fetch logs updated after this timestamp.
    @ObservationIgnored private var lastPullLogUpdatedAt: Date? {
        get { UserDefaults.standard.object(forKey: "sonder.sync.lastPullLogUpdatedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "sonder.sync.lastPullLogUpdatedAt") }
    }

    /// Cursor for incremental trip pulls — only fetch trips updated after this timestamp.
    @ObservationIgnored private var lastPullTripUpdatedAt: Date? {
        get { UserDefaults.standard.object(forKey: "sonder.sync.lastPullTripUpdatedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "sonder.sync.lastPullTripUpdatedAt") }
    }

    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client
    @ObservationIgnored private nonisolated(unsafe) var syncTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var networkMonitor = NWPathMonitor()
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
        syncTask?.cancel()
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
        logger.info("Network status changed: \(isConnected ? "online" : "offline")")
        isOnline = isConnected
    }

    // MARK: - Public API

    /// Sync all pending logs to Supabase and pull remote changes
    func syncNow() async {
        logger.info("[SyncNow] called — isSyncing=\(self.isSyncing), isOnline=\(self.isOnline)")
        guard !isSyncing else {
            // A sync is already running — schedule a follow-up so new
            // pending items (e.g. a just-created log) aren't left waiting
            // for the next periodic cycle.
            needsResync = true
            logger.info("[SyncNow] already syncing — queued resync")
            return
        }
        guard isOnline else {
            logger.info("Offline - skipping sync")
            await updatePendingCount()
            return
        }

        // Check for valid Supabase session (local Keychain check, no network)
        guard let session = supabase.auth.currentSession else {
            logger.info("[SyncNow] No Supabase session - skipping sync")
            return
        }
        let userID = session.user.id.uuidString

        isSyncing = true

        // Push: sync local changes to remote (independent so one failure doesn't block the other)
        do {
            try await syncPendingTrips()
        } catch {
            logger.error("Push trips error: \(error.localizedDescription)")
        }

        do {
            try await syncPendingLogs()
        } catch {
            logger.error("Push logs error: \(error.localizedDescription)")
        }

        // Retry any remote deletions that failed previously (e.g. offline)
        await syncPendingDeletions()

        // Pull: each pull runs independently so one failure doesn't block the others
        do {
            try await pullRemoteTrips(for: userID)
        } catch {
            logger.error("Pull trips error: \(error.localizedDescription)")
        }

        do {
            try await pullRemoteLogs(for: userID)
        } catch {
            logger.error("Pull logs error: \(error.localizedDescription)")
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
        lastPullLogUpdatedAt = nil
        lastPullTripUpdatedAt = nil
        await syncNow()
    }

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        syncTask = Task {
            // Sync immediately on start (don't wait 30s for first pull)
            await syncNow()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))

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


    func resumePeriodicSync() {
        if syncTask == nil {
            startPeriodicSync()
        }
    }

    // MARK: - Log Sync

    private func syncPendingLogs() async throws {
        let synced = SyncStatus.synced
        let pendingDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.syncStatus != synced }
        )
        let pendingLogs = try modelContext.fetch(pendingDescriptor)
        logger.info("[SyncLogs] Found \(pendingLogs.count) pending/failed logs")

        for log in pendingLogs {
            // Skip logs that still have photos uploading in the background
            if log.photoURLs.contains(where: { $0.hasPrefix("pending-upload:") }) {
                logger.info("[SyncLogs] Skipping log \(log.id) — pending photo upload")
                continue
            }

            do {
                logger.info("[SyncLogs] Uploading log \(log.id) for place \(log.placeID), status=\(log.syncStatus.rawValue)")
                try await uploadLog(log)
                log.syncStatus = .synced
                log.updatedAt = Date()
                logger.info("[SyncLogs] ✓ Log \(log.id) synced successfully")
            } catch {
                log.syncStatus = .failed
                logger.error("[SyncLogs] ✗ Failed to sync log \(log.id): \(error)")
            }
        }

        try modelContext.save()
    }

    private func uploadLog(_ log: Log) async throws {
        // First ensure place exists in Supabase
        try await syncPlace(placeID: log.placeID)

        // If the log has a trip, ensure the trip exists in Supabase first.
        // If the trip can't be synced, upload the log without the trip reference
        // to avoid a permanent foreign key failure on the trip_activity trigger.
        var tripIDForUpload = log.tripID
        if let tripID = log.tripID {
            do {
                try await syncTrip(tripID: tripID)
            } catch {
                logger.warning("Trip \(tripID) failed to sync, uploading log without trip reference: \(error.localizedDescription)")
                tripIDForUpload = nil
            }
        }

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
            let trip_sort_order: Int?
            let visited_at: Date
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
            trip_id: tripIDForUpload,
            trip_sort_order: log.tripSortOrder,
            visited_at: log.visitedAt,
            created_at: log.createdAt,
            updated_at: log.updatedAt
        )

        // Then upload the log
        try await supabase
            .from("logs")
            .upsert(uploadData)
            .execute()
    }

    /// Ensure a specific trip exists in Supabase before uploading a log that references it.
    private func syncTrip(tripID: String) async throws {
        let tripIDCopy = tripID
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in
                trip.id == tripIDCopy
            }
        )

        guard let trip = try modelContext.fetch(descriptor).first else {
            throw SyncError.invalidData
        }

        try await supabase
            .from("trips")
            .upsert(trip)
            .execute()

        trip.syncStatus = .synced
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

    private func syncPendingTrips() async throws {
        // Only push dirty trips owned by the current user (collaborator trips are
        // managed by their owner and would be rejected by RLS anyway).
        guard let session = supabase.auth.currentSession else { return }
        let currentUserID = session.user.id.uuidString

        let pendingStatus = SyncStatus.pending
        let dirtyTrips = try modelContext.fetch(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.createdBy == currentUserID && $0.syncStatus == pendingStatus }
        ))

        for trip in dirtyTrips {
            do {
                try await supabase
                    .from("trips")
                    .upsert(trip)
                    .execute()
                trip.syncStatus = SyncStatus.synced
            } catch {
                logger.warning("Failed to sync trip '\(trip.name)' (\(trip.id)): \(error.localizedDescription)")
            }
        }

        if !dirtyTrips.isEmpty {
            try modelContext.save()
        }
    }

    // MARK: - Pull Sync

    private func pullRemoteTrips(for userID: String) async throws {
        let isIncremental = lastPullTripUpdatedAt != nil

        // Fetch trips created by the user
        var ownedQuery = supabase
            .from("trips")
            .select()
            .eq("created_by", value: userID)

        if let cursor = lastPullTripUpdatedAt {
            let bufferDate = cursor.addingTimeInterval(-1) // 1s buffer for clock skew
            ownedQuery = ownedQuery.gt("updated_at", value: bufferDate)
        }

        let ownedTrips: [Trip] = try await ownedQuery.execute().value
        logger.info("Pull trips: \(ownedTrips.count) owned\(isIncremental ? " (incremental)" : " (full)")")

        var allRemoteTrips = ownedTrips

        // Also fetch trips where user is a collaborator (best-effort)
        var collabQuery = supabase
            .from("trips")
            .select()
            .contains("collaborator_ids", value: [userID])

        if let cursor = lastPullTripUpdatedAt {
            let bufferDate = cursor.addingTimeInterval(-1)
            collabQuery = collabQuery.gt("updated_at", value: bufferDate)
        }

        if let collabTrips: [Trip] = try? await collabQuery.execute().value {
            let ownedIDs = Set(allRemoteTrips.map(\.id))
            let newCollabs = collabTrips.filter { !ownedIDs.contains($0.id) }
            allRemoteTrips += newCollabs
            logger.info("Pull trips: \(newCollabs.count) as collaborator")
        }

        if !allRemoteTrips.isEmpty {
            try mergeRemoteTrips(allRemoteTrips)
            logger.info("Pull trips: merged \(allRemoteTrips.count) total")

            // Advance cursor to the latest updatedAt from this batch
            let maxUpdatedAt = allRemoteTrips.map(\.updatedAt).max()
            if let maxDate = maxUpdatedAt {
                if lastPullTripUpdatedAt.map({ maxDate > $0 }) ?? true {
                    lastPullTripUpdatedAt = maxDate
                }
            }
        }
    }

    /// Merge remote trips into local SwiftData store.
    /// - Remote trips not found locally are inserted.
    /// - Existing local trips are updated if the remote `updatedAt` is newer.
    func mergeRemoteTrips(_ remoteTrips: [Trip]) throws {
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
                // Update if remote is newer and local isn't dirty
                if remote.updatedAt > local.updatedAt && local.syncStatus != .pending {
                    local.name = remote.name
                    local.tripDescription = remote.tripDescription
                    local.coverPhotoURL = remote.coverPhotoURL
                    local.startDate = remote.startDate
                    local.endDate = remote.endDate
                    local.collaboratorIDs = remote.collaboratorIDs
                    local.updatedAt = remote.updatedAt
                    local.syncStatus = .synced
                }
            } else {
                // New trip from server — mark as synced and insert directly
                remote.syncStatus = .synced
                modelContext.insert(remote)
            }
        }

        try modelContext.save()
    }

    private func pullRemoteLogs(for userID: String) async throws {
        let isIncremental = lastPullLogUpdatedAt != nil

        var query = supabase
            .from("logs")
            .select()
            .eq("user_id", value: userID)

        if let cursor = lastPullLogUpdatedAt {
            let bufferDate = cursor.addingTimeInterval(-1) // 1s buffer for clock skew
            query = query.gt("updated_at", value: bufferDate)
        }

        let remoteLogs: [RemoteLog] = try await query.execute().value
        logger.info("Pull logs: \(remoteLogs.count)\(isIncremental ? " (incremental)" : " (full)")")

        guard !remoteLogs.isEmpty else { return }

        // Find place IDs we don't have locally — single bulk fetch instead of N queries
        let remotePlaceIDs = Set(remoteLogs.map(\.placeID))
        let allLocalPlaces = try modelContext.fetch(FetchDescriptor<Place>())
        let localPlaceIDs = Set(allLocalPlaces.map(\.id)).intersection(remotePlaceIDs)
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

        // Advance cursor to the latest updatedAt from this batch
        let maxUpdatedAt = remoteLogs.map(\.updatedAt).max()
        if let maxDate = maxUpdatedAt {
            if lastPullLogUpdatedAt.map({ maxDate > $0 }) ?? true {
                lastPullLogUpdatedAt = maxDate
            }
        }
    }

    /// Merge remote logs into local SwiftData store.
    /// - Remote logs not found locally are inserted as `.synced`.
    /// - Local logs with `.pending` or `.failed` status are never overwritten (preserve unsynced changes).
    /// - Local `.synced` logs are updated only if the remote `updatedAt` is newer (server wins).
    /// - For small batches (≤50, i.e. incremental sync), uses per-ID lookups instead of fetching all local logs.
    func mergeRemoteLogs(_ remoteLogs: [RemoteLog], remotePlaces: [Place]) throws {
        // Insert missing places
        for place in remotePlaces {
            modelContext.insert(place)
        }

        if remoteLogs.count <= 50 {
            // Incremental path: individual lookups avoid loading all local logs into memory
            try mergeRemoteLogsIncremental(remoteLogs)
        } else {
            // Full sync path: dictionary-based approach with deduplication
            try mergeRemoteLogsFull(remoteLogs)
        }

        try modelContext.save()
    }

    /// Incremental merge: look up each remote log individually by ID.
    /// Efficient for small batches — avoids fetching all local logs.
    private func mergeRemoteLogsIncremental(_ remoteLogs: [RemoteLog]) throws {
        for remote in remoteLogs {
            let remoteID = remote.id.lowercased()
            let remoteTripID = (remote.tripID?.trimmingCharacters(in: .whitespaces).isEmpty == true) ? nil : remote.tripID

            if pendingDeletions.contains(remoteID) { continue }

            // Look up this specific log by ID
            let rid = remote.id
            let descriptor = FetchDescriptor<Log>(predicate: #Predicate { $0.id == rid })
            let local = try modelContext.fetch(descriptor).first

            if let local {
                switch local.syncStatus {
                case .pending, .failed:
                    continue
                case .synced:
                    if remote.updatedAt > local.updatedAt {
                        local.rating = Rating(rawValue: remote.rating) ?? local.rating
                        local.photoURLs = remote.photoURLs
                        local.note = remote.note
                        local.tags = remote.tags
                        local.tripID = remoteTripID
                        local.tripSortOrder = remote.tripSortOrder
                        local.visitedAt = remote.visitedAt
                        local.updatedAt = remote.updatedAt
                    }
                }
            } else {
                let log = Log(
                    id: remote.id,
                    userID: remote.userID,
                    placeID: remote.placeID,
                    rating: Rating(rawValue: remote.rating) ?? .okay,
                    photoURLs: remote.photoURLs,
                    note: remote.note,
                    tags: remote.tags,
                    tripID: remoteTripID,
                    tripSortOrder: remote.tripSortOrder,
                    visitedAt: remote.visitedAt,
                    syncStatus: .synced,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt
                )
                modelContext.insert(log)
            }
        }
    }

    /// Full merge: fetch all local logs and build a dictionary for O(1) lookups.
    /// Also deduplicates local logs from prior UUID case-mismatch bugs.
    private func mergeRemoteLogsFull(_ remoteLogs: [RemoteLog]) throws {
        let localLogs = try modelContext.fetch(FetchDescriptor<Log>())
        var localLogsByID: [String: Log] = [:]
        var duplicatesToRemove: [Log] = []
        for log in localLogs {
            let key = log.id.lowercased()
            if let existing = localLogsByID[key] {
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
        for dup in duplicatesToRemove {
            modelContext.delete(dup)
        }

        for remote in remoteLogs {
            let remoteID = remote.id.lowercased()
            let remoteTripID = (remote.tripID?.trimmingCharacters(in: .whitespaces).isEmpty == true) ? nil : remote.tripID

            if pendingDeletions.contains(remoteID) { continue }

            if let local = localLogsByID[remoteID] {
                switch local.syncStatus {
                case .pending, .failed:
                    continue
                case .synced:
                    if remote.updatedAt > local.updatedAt {
                        local.rating = Rating(rawValue: remote.rating) ?? local.rating
                        local.photoURLs = remote.photoURLs
                        local.note = remote.note
                        local.tags = remote.tags
                        local.tripID = remoteTripID
                        local.tripSortOrder = remote.tripSortOrder
                        local.visitedAt = remote.visitedAt
                        local.updatedAt = remote.updatedAt
                    }
                }
            } else {
                let log = Log(
                    id: remote.id,
                    userID: remote.userID,
                    placeID: remote.placeID,
                    rating: Rating(rawValue: remote.rating) ?? .okay,
                    photoURLs: remote.photoURLs,
                    note: remote.note,
                    tags: remote.tags,
                    tripID: remoteTripID,
                    tripSortOrder: remote.tripSortOrder,
                    visitedAt: remote.visitedAt,
                    syncStatus: .synced,
                    createdAt: remote.createdAt,
                    updatedAt: remote.updatedAt
                )
                modelContext.insert(log)
            }
        }
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
            do { try modelContext.save() } catch { logger.error("[Sync] SwiftData save failed: \(error.localizedDescription)") }
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
            logger.error("Failed to delete log \(logID) from Supabase: \(error.localizedDescription)")
            // Stays in pendingDeletions for retry on next sync
        }
    }

    /// Bulk-delete multiple logs from both local SwiftData and Supabase.
    /// Performs a single context save and a single Supabase `.in()` delete for efficiency.
    func bulkDeleteLogs(ids logIDs: [String]) async {
        guard !logIDs.isEmpty else { return }

        // Track all IDs as pending deletions so pull sync won't resurrect them
        for id in logIDs {
            pendingDeletions.insert(id.lowercased())
        }

        // Batch fetch and delete locally
        let idsToDelete = Set(logIDs)
        let descriptor = FetchDescriptor<Log>()
        if let allLogs = try? modelContext.fetch(descriptor) {
            for log in allLogs where idsToDelete.contains(log.id) {
                _ = log.photoURLs
                _ = log.tags
                modelContext.delete(log)
            }
            do { try modelContext.save() } catch {
                logger.error("[Sync] SwiftData bulk save failed: \(error.localizedDescription)")
            }
        }

        // Single Supabase batch delete
        do {
            try await supabase
                .from("logs")
                .delete()
                .in("id", values: logIDs)
                .execute()
            for id in logIDs {
                pendingDeletions.remove(id.lowercased())
            }
        } catch {
            logger.error("Failed to bulk delete logs from Supabase: \(error.localizedDescription)")
            // Stay in pendingDeletions for retry on next sync
        }
    }

    /// Push a log deletion to Supabase only (local delete already done by caller).
    /// Tracks the ID in pendingDeletions for offline retry.
    func pushLogDeletion(id logID: String) async {
        pendingDeletions.insert(logID.lowercased())

        do {
            try await supabase
                .from("logs")
                .delete()
                .eq("id", value: logID)
                .execute()
            pendingDeletions.remove(logID.lowercased())
        } catch {
            logger.error("Failed to delete log \(logID) from Supabase: \(error.localizedDescription)")
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
                logger.warning("Retry delete failed for \(logID): \(error.localizedDescription)")
            }
        }
        pendingDeletions.subtract(resolved)
    }

    // MARK: - Photo Upload Helpers

    /// Replaces pending-upload placeholder URLs with real uploaded URLs.
    /// Called from background upload completion closures so they don't need
    /// to capture a view's ModelContext. Returns the updated photoURLs,
    /// or nil if the log was not found.
    @discardableResult
    func replacePendingPhotoURLs(logID: String, uploadResults: [String: String]) -> [String]? {
        let idToFind = logID
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { log in log.id == idToFind }
        )
        guard let log = try? modelContext.fetch(descriptor).first else { return nil }
        log.photoURLs = log.photoURLs.compactMap { url in
            if url.hasPrefix("pending-upload:") {
                let placeholderID = String(url.dropFirst("pending-upload:".count))
                return uploadResults[placeholderID]
            }
            return url
        }
        log.updatedAt = Date()
        do { try modelContext.save() } catch { logger.error("[Sync] SwiftData save failed: \(error.localizedDescription)") }
        needsResync = true
        return log.photoURLs
    }

    /// Updates a trip's cover photo URL after background upload completes.
    /// Called from background upload closures so they don't need to capture
    /// a view's ModelContext.
    func updateTripCoverPhoto(tripID: String, url: String) {
        let idToFind = tripID
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in trip.id == idToFind }
        )
        guard let trip = try? modelContext.fetch(descriptor).first else { return }
        trip.coverPhotoURL = url
        trip.updatedAt = Date()
        trip.syncStatus = .pending
        do { try modelContext.save() } catch { logger.error("[Sync] SwiftData save failed: \(error.localizedDescription)") }
        needsResync = true
    }

    // MARK: - Helpers

    func updatePendingCount() async {
        let synced = SyncStatus.synced
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.syncStatus != synced }
        )
        if let pendingLogs = try? modelContext.fetch(descriptor) {
            pendingCount = pendingLogs.filter {
                !$0.photoURLs.contains(where: { $0.hasPrefix("pending-upload:") })
            }.count
        }
    }

    /// Get failed logs for retry UI
    func getFailedLogs() -> [Log] {
        let failed = SyncStatus.failed
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.syncStatus == failed }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Get all logs that contribute to the pending badge (pending or failed, excluding active photo uploads)
    func getStuckLogs() -> [Log] {
        let synced = SyncStatus.synced
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.syncStatus != synced }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            !$0.photoURLs.contains(where: { $0.hasPrefix("pending-upload:") })
        }
    }

    /// Force-mark all stuck logs as synced, clearing the pending badge.
    /// Use when a log is permanently stuck and the user wants to dismiss it.
    func dismissStuckLogs() {
        for log in getStuckLogs() {
            log.syncStatus = .synced
        }
        do { try modelContext.save() } catch { logger.error("[Sync] SwiftData save failed: \(error.localizedDescription)") }
        pendingCount = 0
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
