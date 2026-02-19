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
    private var libraryObserver: IndexLibraryChangeObserver?
    private var buildTask: Task<Void, Never>?

    private enum Defaults {
        static let builtKey = "sonder.photoIndex.built"
        static let accessLevelKey = "sonder.photoIndex.accessLevel"
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
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

    func buildFullIndex(accessLevel: String) {
        buildTask?.cancel()
        isBuilding = true

        let container = modelContainer

        buildTask = Task.detached { [weak self] in
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            // Delete all existing entries
            try? bgContext.delete(model: PhotoLocationIndex.self)
            try? bgContext.save()

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

            var batch: [PhotoLocationIndex] = []
            let batchSize = 1000

            assets.enumerateObjects { asset, index, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }

                guard let location = asset.location else { return }

                let entry = PhotoLocationIndex(
                    localIdentifier: asset.localIdentifier,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                batch.append(entry)

                if batch.count >= batchSize {
                    for item in batch {
                        bgContext.insert(item)
                    }
                    try? bgContext.save()
                    batch.removeAll(keepingCapacity: true)
                }
            }

            // Save remaining
            if !batch.isEmpty {
                for item in batch {
                    bgContext.insert(item)
                }
                try? bgContext.save()
            }

            guard !Task.isCancelled else { return }

            // Hand fetch result to main actor
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.storedFetchResult = assets
                self.isBuilding = false
                self.hasBuiltIndex = true
                UserDefaults.standard.set(true, forKey: Defaults.builtKey)
                UserDefaults.standard.set(accessLevel, forKey: Defaults.accessLevelKey)
                self.startObserver()
            }
        }
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
            }
        )
        descriptor.fetchLimit = 100

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

        let removed = details.removedObjects
        let inserted = details.insertedObjects
        let changed = details.changedObjects

        guard !removed.isEmpty || !inserted.isEmpty || !changed.isEmpty else { return }

        let container = modelContainer

        Task.detached { [removed, inserted, changed] in
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            // Remove deleted assets
            for asset in removed {
                let id = asset.localIdentifier
                let descriptor = FetchDescriptor<PhotoLocationIndex>(
                    predicate: #Predicate { $0.localIdentifier == id }
                )
                if let existing = try? bgContext.fetch(descriptor).first {
                    bgContext.delete(existing)
                }
            }

            // Insert new geotagged assets
            for asset in inserted {
                guard let location = asset.location else { continue }
                let entry = PhotoLocationIndex(
                    localIdentifier: asset.localIdentifier,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                bgContext.insert(entry)
            }

            // Update changed assets (location may have been added/removed)
            for asset in changed {
                let id = asset.localIdentifier
                let descriptor = FetchDescriptor<PhotoLocationIndex>(
                    predicate: #Predicate { $0.localIdentifier == id }
                )
                let existing = try? bgContext.fetch(descriptor).first

                if let location = asset.location {
                    if let existing {
                        existing.latitude = location.coordinate.latitude
                        existing.longitude = location.coordinate.longitude
                    } else {
                        let entry = PhotoLocationIndex(
                            localIdentifier: asset.localIdentifier,
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
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

            try? bgContext.save()
        }
    }

    // MARK: - Access Level Change

    func handleAccessLevelChange(newLevel: String) {
        buildFullIndex(accessLevel: newLevel)
    }

    // MARK: - Reset

    func resetIndex() {
        buildTask?.cancel()
        stopObserver()

        let container = modelContainer
        Task.detached {
            let bgContext = ModelContext(container)
            try? bgContext.delete(model: PhotoLocationIndex.self)
            try? bgContext.save()
        }

        storedFetchResult = nil
        hasBuiltIndex = false
        isBuilding = false
        UserDefaults.standard.removeObject(forKey: Defaults.builtKey)
        UserDefaults.standard.removeObject(forKey: Defaults.accessLevelKey)
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
