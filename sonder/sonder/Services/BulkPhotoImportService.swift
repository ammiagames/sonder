//
//  BulkPhotoImportService.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import Foundation
import Photos
import PhotosUI
import SwiftUI
import SwiftData
import CoreLocation
import os

/// Orchestrates the bulk photo import flow: extract metadata → cluster → resolve places → create logs.
/// Instantiated per-import session (not a long-lived environment service).
@Observable
@MainActor
final class BulkPhotoImportService {

    // MARK: - Observable State

    /// Current flow state. Internal setter for testability.
    internal(set) var state: BulkImportState = .selecting
    internal(set) var clusters: [PhotoCluster] = []
    internal(set) var unlocatedPhotos: [PhotoMetadata] = []
    internal(set) var createdLogCount: Int = 0

    // MARK: - Dependencies (injected)

    private let googlePlacesService: GooglePlacesService
    private let placesCacheService: PlacesCacheService
    private let photoService: PhotoService
    private let photoSuggestionService: PhotoSuggestionService
    private let syncEngine: SyncEngine
    private let modelContext: ModelContext

    private let logger = Logger(subsystem: "com.sonder", category: "BulkPhotoImport")

    init(
        googlePlacesService: GooglePlacesService,
        placesCacheService: PlacesCacheService,
        photoService: PhotoService,
        photoSuggestionService: PhotoSuggestionService,
        syncEngine: SyncEngine,
        modelContext: ModelContext
    ) {
        self.googlePlacesService = googlePlacesService
        self.placesCacheService = placesCacheService
        self.photoService = photoService
        self.photoSuggestionService = photoSuggestionService
        self.syncEngine = syncEngine
        self.modelContext = modelContext
    }

    // MARK: - Process Selected Photos

    /// Main entry point after user selects photos from PhotosPicker.
    /// Extracts GPS metadata, clusters by proximity+date, then resolves places via Google.
    func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            state = .selecting
            return
        }

        // Phase 1: Extract metadata from PHAssets
        state = .extracting(progress: 0)

        let identifiers = items.compactMap(\.itemIdentifier)
        guard !identifiers.isEmpty else {
            state = .failed("Could not read photo identifiers")
            return
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var allMetadata: [PhotoMetadata] = []

        fetchResult.enumerateObjects { asset, _, _ in
            let metadata = PhotoMetadata(
                id: asset.localIdentifier,
                coordinate: asset.location?.coordinate,
                creationDate: asset.creationDate
            )
            allMetadata.append(metadata)
        }

        // Update progress for extraction
        state = .extracting(progress: 1.0)

        guard !allMetadata.isEmpty else {
            state = .failed("No photo metadata could be extracted")
            return
        }

        // Phase 2: Cluster
        state = .clustering
        let result = PhotoClusteringService.cluster(photos: allMetadata)
        clusters = result.clusters
        unlocatedPhotos = result.unlocated

        guard !clusters.isEmpty else {
            if !unlocatedPhotos.isEmpty {
                state = .reviewing
            } else {
                state = .failed("No geotagged photos found")
            }
            return
        }

        // Phase 3: Resolve places via Google nearby search
        await resolvePlaces()

        state = .reviewing
    }

    // MARK: - Place Resolution

    private func resolvePlaces() async {
        let total = clusters.count
        guard total > 0 else { return }

        state = .resolving(progress: 0)

        // Throttle to 3 concurrent calls
        await withTaskGroup(of: (Int, [NearbyPlace]).self) { group in
            var pending = 0
            var nextIndex = 0
            var resolved = 0

            while nextIndex < total || pending > 0 {
                // Launch up to 3 concurrent tasks
                while pending < 3 && nextIndex < total {
                    let index = nextIndex
                    if let centroid = clusters[index].centroid {
                        group.addTask { [googlePlacesService] in
                            let places = await googlePlacesService.nearbySearch(location: centroid)
                            return (index, places)
                        }
                        pending += 1
                    } else {
                        // No centroid — skip resolution
                        resolved += 1
                        state = .resolving(progress: Double(resolved) / Double(total))
                    }
                    nextIndex += 1
                }

                // Wait for one result
                if pending > 0, let (index, places) = await group.next() {
                    pending -= 1
                    resolved += 1
                    clusters[index].suggestedPlaces = places
                    state = .resolving(progress: Double(resolved) / Double(total))
                }
            }
        }
    }

    /// Retry place resolution for clusters that have no suggestions yet.
    func retryPlaceResolution() async {
        await resolvePlaces()
        state = .reviewing
    }

    // MARK: - Review Mutations

    func updateRating(for clusterID: UUID, rating: Rating) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }
        clusters[index].rating = rating
    }

    func updatePlace(for clusterID: UUID, place: Place) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }
        clusters[index].confirmedPlace = place
    }

    func updateDate(for clusterID: UUID, date: Date) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }
        clusters[index].date = date
    }

    func removeCluster(_ clusterID: UUID) {
        clusters.removeAll { $0.id == clusterID }
    }

    /// Select a suggested place for a cluster (from the nearbySearch results).
    func selectSuggestedPlace(for clusterID: UUID, nearbyPlace: NearbyPlace) {
        guard let index = clusters.firstIndex(where: { $0.id == clusterID }) else { return }
        let place = placesCacheService.cachePlace(from: nearbyPlace)
        clusters[index].confirmedPlace = place
    }

    // MARK: - Validation

    /// Whether all clusters have the required fields to create logs.
    var canSave: Bool {
        let readyClusters = clusters.filter { cluster in
            (cluster.confirmedPlace != nil || !cluster.suggestedPlaces.isEmpty)
            && cluster.rating != nil
        }
        return !readyClusters.isEmpty
    }

    /// Number of clusters ready to become logs.
    var readyCount: Int {
        clusters.filter { cluster in
            (cluster.confirmedPlace != nil || !cluster.suggestedPlaces.isEmpty)
            && cluster.rating != nil
        }.count
    }

    // MARK: - Bulk Save

    /// Creates logs for all valid clusters. Mirrors the pattern from AddDetailsView.save().
    func saveAllLogs(userID: String, tripID: String?) async {
        let validClusters = clusters.filter { $0.rating != nil }
        guard !validClusters.isEmpty else { return }

        state = .saving(progress: 0)
        var savedCount = 0

        // Determine next tripSortOrder if assigning to a trip
        var nextSortOrder: Int = 0
        if let tripID {
            let descriptor = FetchDescriptor<Log>(
                predicate: #Predicate { $0.tripID == tripID }
            )
            let existingLogs = (try? modelContext.fetch(descriptor)) ?? []
            nextSortOrder = (existingLogs.compactMap(\.tripSortOrder).max() ?? -1) + 1
        }

        for (index, cluster) in validClusters.enumerated() {
            // Resolve place: confirmed > first suggested > skip
            let place: Place
            if let confirmed = cluster.confirmedPlace {
                place = confirmed
            } else if let first = cluster.suggestedPlaces.first {
                place = placesCacheService.cachePlace(from: first)
            } else {
                continue
            }

            guard let rating = cluster.rating else { continue }

            let logID = UUID().uuidString.lowercased()

            // Load full images for this cluster's photos
            let assetIDs = cluster.photoMetadata.map(\.id)
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
            var images: [UIImage] = []

            // Load images in batches to manage memory
            let batchSize = 5
            var assetIndex = 0
            while assetIndex < fetchResult.count {
                let end = min(assetIndex + batchSize, fetchResult.count)
                for i in assetIndex..<end {
                    let asset = fetchResult.object(at: i)
                    if let image = await photoSuggestionService.loadFullImage(for: asset) {
                        images.append(image)
                    }
                }
                assetIndex = end
            }

            // Queue photo uploads (returns placeholder URLs immediately)
            var photoURLs: [String] = []
            if !images.isEmpty {
                photoURLs = photoService.queueBatchUpload(
                    images: images,
                    for: userID,
                    logID: logID
                ) { [syncEngine] results in
                    syncEngine.replacePendingPhotoURLs(logID: logID, uploadResults: results)
                }
            }

            // Create log
            let log = Log(
                id: logID,
                userID: userID,
                placeID: place.id,
                rating: rating,
                photoURLs: photoURLs,
                tripID: tripID,
                tripSortOrder: tripID != nil ? nextSortOrder : nil,
                visitedAt: cluster.date ?? Date(),
                syncStatus: .pending
            )

            modelContext.insert(log)
            nextSortOrder += 1
            savedCount += 1
            state = .saving(progress: Double(index + 1) / Double(validClusters.count))
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save bulk import logs: \(error.localizedDescription)")
            state = .failed("Failed to save logs")
            return
        }

        createdLogCount = savedCount
        state = .complete(logCount: savedCount)

        // Trigger sync for logs without photos (those with photos sync after upload completes)
        Task {
            await syncEngine.syncNow()
        }
    }
}
