//
//  SyncEngine.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData
import Supabase

@MainActor
@Observable
final class SyncEngine {
    var isSyncing = false
    var lastSyncDate: Date?
    var pendingCount = 0
    
    private let modelContext: ModelContext
    private let supabase = SupabaseConfig.client
    private var syncTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        startPeriodicSync()
    }
    
    // MARK: - Public API
    
    /// Sync all pending logs to Supabase
    func syncNow() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            try await syncPendingLogs()
            try await syncPendingTrips()
            lastSyncDate = Date()
            await updatePendingCount()
        } catch {
            print("Sync error: \(error)")
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
        
        // Then upload the log
        try await supabase
            .from("logs")
            .upsert(log)
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
        
        // Check if place already exists in Supabase
        do {
            let _: Place = try await supabase
                .from("places")
                .select()
                .eq("id", value: placeID)
                .single()
                .execute()
                .value
            // Place already exists, no need to upload
        } catch {
            // Place doesn't exist, upload it
            try await supabase
                .from("places")
                .insert(place)
                .execute()
        }
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
    
    private func updatePendingCount() async {
        let descriptor = FetchDescriptor<Log>()
        if let allLogs = try? modelContext.fetch(descriptor) {
            pendingCount = allLogs.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }.count
        }
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
