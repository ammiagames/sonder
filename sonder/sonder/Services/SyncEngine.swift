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

@MainActor
@Observable
final class SyncEngine {
    var isSyncing = false
    var lastSyncDate: Date?
    var pendingCount = 0
    var isOnline = true

    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client
    private var syncTask: Task<Void, Never>?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sonder.networkMonitor")

    /// Photo service for coordinating photo uploads
    var photoService: PhotoService?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        startNetworkMonitoring()
        startPeriodicSync()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasOffline = !self.isOnline
                let nowOnline = path.status == .satisfied

                print("Network status changed: \(nowOnline ? "online" : "offline")")

                self.isOnline = nowOnline

                // Trigger sync when coming back online
                if wasOffline && nowOnline {
                    print("Back online - triggering sync")
                    await self.syncNow()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Public API

    /// Sync all pending logs to Supabase
    func syncNow() async {
        guard !isSyncing else { return }
        guard isOnline else {
            print("Offline - skipping sync")
            return
        }

        // Check for valid Supabase session (skip sync in debug mode)
        do {
            _ = try await supabase.auth.session
        } catch {
            print("No Supabase session - skipping sync (debug mode)")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // First, process any pending photo uploads
            await processPendingPhotoUploads()

            // Sync trips BEFORE logs (logs have foreign key to trips)
            try await syncPendingTrips()
            try await syncPendingLogs()
            lastSyncDate = Date()
            await updatePendingCount()
        } catch {
            print("Sync error: \(error)")
        }
    }

    /// Force a sync even if already syncing (for user-triggered refresh)
    func forceSyncNow() async {
        isSyncing = false
        await syncNow()
    }

    // MARK: - Photo Upload Coordination

    private func processPendingPhotoUploads() async {
        guard let photoService = photoService else { return }

        if photoService.pendingUploadCount > 0 {
            photoService.processQueue()

            // Wait for queue to process (with timeout)
            for _ in 0..<30 {
                if photoService.pendingUploadCount == 0 { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Periodic Sync

    private func startPeriodicSync() {
        syncTask = Task {
            while !Task.isCancelled {
                // Sync every 30 seconds when app is active
                try? await Task.sleep(for: .seconds(30))
                await syncNow()
            }
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

    private func syncPendingLogs() async throws {
        let descriptor = FetchDescriptor<Log>()
        let allLogs = try modelContext.fetch(descriptor)
        let pendingLogs = allLogs.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }

        for log in pendingLogs {
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
            let photo_url: String?
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
            photo_url: log.photoURL,
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

    private func syncPendingTrips() async throws {
        let descriptor = FetchDescriptor<Trip>()
        let trips = try modelContext.fetch(descriptor)

        for trip in trips {
            do {
                try await supabase.database
                    .from("trips")
                    .upsert(trip)
                    .execute()
            } catch {
                print("Failed to sync trip \(trip.id): \(error)")
            }
        }
    }

    // MARK: - Helpers

    func updatePendingCount() async {
        let descriptor = FetchDescriptor<Log>()
        if let allLogs = try? modelContext.fetch(descriptor) {
            pendingCount = allLogs.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }.count
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
