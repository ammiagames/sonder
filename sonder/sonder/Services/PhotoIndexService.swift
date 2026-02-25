//
//  PhotoIndexService.swift
//  sonder
//
//  Created by Michael Song on 2/18/26.
//

import Foundation
import Photos
import CoreLocation
import SwiftData

@Observable
@MainActor
final class PhotoIndexService {
    var hasBuiltIndex = false
    private(set) var isBuilding = false

    private let modelContainer: ModelContainer
    private var storedFetchResult: PHFetchResult<PHAsset>?
    private nonisolated(unsafe) var libraryObserver: IndexLibraryChangeObserver?
    private nonisolated(unsafe) var buildTask: Task<Void, Never>?
    private nonisolated(unsafe) var libraryChangeTask: Task<Void, Never>?
    private var lastIncrementalRefreshAt: Date?

    private struct IndexedPhotoCandidate: Sendable {
        let localIdentifier: String
        let latitude: Double
        let longitude: Double
    }

    /// Sendable snapshot of a PHAsset change for passing into detached tasks.
    /// PHAsset itself is NOT Sendable — we must extract data on the main actor first.
    private struct AssetChange: Sendable {
        let localIdentifier: String
        let latitude: Double?
        let longitude: Double?
        var hasLocation: Bool { latitude != nil && longitude != nil }
    }

    private enum IncrementalRefresh {
        static let minInterval: TimeInterval = 20
        static let recentAssetLimit = 400
        static let saveBatchSize = 100
    }

    private enum Defaults {
        static let builtKey = "sonder.photoIndex.built"
        static let accessLevelKey = "sonder.photoIndex.accessLevel"
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    deinit {
        if let observer = libraryObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        }
        buildTask?.cancel()
        libraryChangeTask?.cancel()
    }

    // MARK: - Build

    func buildIndexIfNeeded(accessLevel: String) {
        let previousLevel = UserDefaults.standard.string(forKey: Defaults.accessLevelKey)
        let wasBuilt = UserDefaults.standard.bool(forKey: Defaults.builtKey)

        if wasBuilt && previousLevel == accessLevel {
            // Index exists and access level unchanged — hydrate fetch result and start observer
            hasBuiltIndex = true
            hydrateFetchResult()
            startObserver()
            return
        }

        // Access level changed or never built — full rebuild
        if previousLevel != nil && previousLevel != accessLevel {
            handleAccessLevelChange(newLevel: accessLevel)
        } else {
            buildFullIndex(accessLevel: accessLevel)
        }
    }

    // THREAD SAFETY: buildFullIndex runs photo enumeration and SwiftData writes
    // together in a single Task.detached block. The ModelContext is created at the
    // top and used synchronously throughout — no `await` between creation and final
    // save, so thread affinity is maintained. Do NOT add `await` calls between
    // context creation and the last `bgContext.save()`.
    func buildFullIndex(accessLevel: String) {
        buildTask?.cancel()
        isBuilding = true

        let container = modelContainer

        buildTask = Task.detached { [weak self] in
            // 1. Enumerate photos — collect Sendable candidates (no SwiftData here)
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

            var candidates: [IndexedPhotoCandidate] = []
            let batchThreshold = 1000

            assets.enumerateObjects { asset, _, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                guard let location = asset.location else { return }
                candidates.append(IndexedPhotoCandidate(
                    localIdentifier: asset.localIdentifier,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ))
            }

            guard !Task.isCancelled else { return }

            // 2. Batch-insert into SwiftData (single context, no await)
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            try? bgContext.delete(model: PhotoLocationIndex.self)
            try? bgContext.save()

            var batchCount = 0
            for candidate in candidates {
                let entry = PhotoLocationIndex(
                    localIdentifier: candidate.localIdentifier,
                    latitude: candidate.latitude,
                    longitude: candidate.longitude
                )
                bgContext.insert(entry)
                batchCount += 1

                if batchCount >= batchThreshold {
                    try? bgContext.save()
                    batchCount = 0
                }
            }

            if batchCount > 0 {
                try? bgContext.save()
            }

            // 3. Hand fetch result to main actor
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.storedFetchResult = assets
                self.isBuilding = false
                self.hasBuiltIndex = true
                self.lastIncrementalRefreshAt = Date()
                UserDefaults.standard.set(true, forKey: Defaults.builtKey)
                UserDefaults.standard.set(accessLevel, forKey: Defaults.accessLevelKey)
                self.startObserver()
            }
        }
    }

    /// Refreshes index entries for recent geotagged photos, useful when photos were added
    /// while the app was not running and no live library-change callbacks were received.
    func refreshRecentAssetsIfNeeded(force: Bool = false) async {
        guard hasBuiltIndex else { return }
        guard !isBuilding else { return }

        let now = Date()
        if !force,
           let last = lastIncrementalRefreshAt,
           now.timeIntervalSince(last) < IncrementalRefresh.minInterval {
            return
        }

        let candidates = fetchRecentGeotaggedAssetCandidates(limit: IncrementalRefresh.recentAssetLimit)
        lastIncrementalRefreshAt = now
        guard !candidates.isEmpty else { return }

        isBuilding = true
        let container = modelContainer
        let batchSize = IncrementalRefresh.saveBatchSize

        _ = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            var writesSinceSave = 0

            for candidate in candidates {
                if Task.isCancelled { break }

                let id = candidate.localIdentifier
                let descriptor = FetchDescriptor<PhotoLocationIndex>(
                    predicate: #Predicate { $0.localIdentifier == id }
                )
                let existing = try? bgContext.fetch(descriptor).first

                if let existing {
                    if existing.latitude != candidate.latitude || existing.longitude != candidate.longitude {
                        existing.latitude = candidate.latitude
                        existing.longitude = candidate.longitude
                        writesSinceSave += 1
                    }
                } else {
                    let entry = PhotoLocationIndex(
                        localIdentifier: candidate.localIdentifier,
                        latitude: candidate.latitude,
                        longitude: candidate.longitude
                    )
                    bgContext.insert(entry)
                    writesSinceSave += 1
                }

                if writesSinceSave >= batchSize {
                    try? bgContext.save()
                    writesSinceSave = 0
                }
            }

            if writesSinceSave > 0 {
                try? bgContext.save()
            }
        }.value

        isBuilding = false
    }

    // MARK: - Query

    func query(near locations: [CLLocation], radiusMeters: Double = 200) -> [String] {
        guard hasBuiltIndex else { return [] }

        let context = modelContainer.mainContext

        // Build a bounding box that encompasses all search locations + radius
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLng = Double.greatestFiniteMagnitude
        var maxLng = -Double.greatestFiniteMagnitude

        for location in locations {
            let lat = location.coordinate.latitude
            let lng = location.coordinate.longitude
            let latDelta = radiusMeters / 111_320.0
            let lngDelta = radiusMeters / (111_320.0 * cos(lat * .pi / 180.0))

            minLat = min(minLat, lat - latDelta)
            maxLat = max(maxLat, lat + latDelta)
            minLng = min(minLng, lng - lngDelta)
            maxLng = max(maxLng, lng + lngDelta)
        }

        var descriptor = FetchDescriptor<PhotoLocationIndex>(
            predicate: #Predicate {
                $0.latitude >= minLat && $0.latitude <= maxLat &&
                $0.longitude >= minLng && $0.longitude <= maxLng
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 250

        guard let candidates = try? context.fetch(descriptor) else { return [] }

        // Fine-filter by actual distance
        var result: [String] = []
        for candidate in candidates {
            let candidateLocation = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
            for searchLocation in locations {
                if candidateLocation.distance(from: searchLocation) <= radiusMeters {
                    result.append(candidate.localIdentifier)
                    break
                }
            }
        }

        return result
    }

    // MARK: - Library Change Observer

    private func startObserver() {
        guard libraryObserver == nil else { return }
        let observer = IndexLibraryChangeObserver { [weak self] change in
            Task { @MainActor [weak self] in
                self?.handleLibraryChange(change)
            }
        }
        libraryObserver = observer
        PHPhotoLibrary.shared().register(observer)
    }

    private func handleLibraryChange(_ change: PHChange) {
        guard let fetchResult = storedFetchResult,
              let details = change.changeDetails(for: fetchResult) else { return }

        storedFetchResult = details.fetchResultAfterChanges

        // Extract Sendable data from PHAsset objects on the main actor BEFORE
        // entering the detached task. PHAsset is NOT Sendable.
        let removedIDs: [String] = details.removedObjects.map(\.localIdentifier)
        let insertedChanges: [AssetChange] = details.insertedObjects.map { asset in
            AssetChange(
                localIdentifier: asset.localIdentifier,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude
            )
        }
        let updatedChanges: [AssetChange] = details.changedObjects.map { asset in
            AssetChange(
                localIdentifier: asset.localIdentifier,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude
            )
        }

        guard !removedIDs.isEmpty || !insertedChanges.isEmpty || !updatedChanges.isEmpty else { return }

        let container = modelContainer

        libraryChangeTask?.cancel()
        libraryChangeTask = Task.detached {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            // Remove deleted assets
            for id in removedIDs {
                guard !Task.isCancelled else { return }
                let descriptor = FetchDescriptor<PhotoLocationIndex>(
                    predicate: #Predicate { $0.localIdentifier == id }
                )
                if let existing = try? bgContext.fetch(descriptor).first {
                    bgContext.delete(existing)
                }
            }

            // Insert new geotagged assets
            for change in insertedChanges {
                guard !Task.isCancelled else { return }
                guard change.hasLocation, let lat = change.latitude, let lng = change.longitude else { continue }
                let entry = PhotoLocationIndex(
                    localIdentifier: change.localIdentifier,
                    latitude: lat,
                    longitude: lng
                )
                bgContext.insert(entry)
            }

            // Update changed assets (location may have been added/removed)
            for change in updatedChanges {
                guard !Task.isCancelled else { return }
                let id = change.localIdentifier
                let descriptor = FetchDescriptor<PhotoLocationIndex>(
                    predicate: #Predicate { $0.localIdentifier == id }
                )
                let existing = try? bgContext.fetch(descriptor).first

                if change.hasLocation, let lat = change.latitude, let lng = change.longitude {
                    if let existing {
                        existing.latitude = lat
                        existing.longitude = lng
                    } else {
                        let entry = PhotoLocationIndex(
                            localIdentifier: change.localIdentifier,
                            latitude: lat,
                            longitude: lng
                        )
                        bgContext.insert(entry)
                    }
                } else {
                    // Location removed — delete from index
                    if let existing {
                        bgContext.delete(existing)
                    }
                }
            }

            guard !Task.isCancelled else { return }
            try? bgContext.save()
        }
    }

    // MARK: - Access Level Change

    func handleAccessLevelChange(newLevel: String) {
        buildFullIndex(accessLevel: newLevel)
    }

    private func stopObserver() {
        if let observer = libraryObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
            libraryObserver = nil
        }
    }

    private func hydrateFetchResult() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        storedFetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    }

    private func fetchRecentGeotaggedAssetCandidates(limit: Int) -> [IndexedPhotoCandidate] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = limit

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var candidates: [IndexedPhotoCandidate] = []
        candidates.reserveCapacity(min(limit, assets.count))

        assets.enumerateObjects { asset, _, _ in
            guard let location = asset.location else { return }
            candidates.append(
                IndexedPhotoCandidate(
                    localIdentifier: asset.localIdentifier,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )
        }

        return candidates
    }
}

// MARK: - PHPhotoLibraryChangeObserver

private final class IndexLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: (PHChange) -> Void

    init(onChange: @escaping (PHChange) -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange(changeInstance)
    }
}
