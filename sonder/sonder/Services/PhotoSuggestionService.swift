//
//  PhotoSuggestionService.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import Foundation
import Photos
import UIKit
import CoreLocation

/// Suggests photos from the user's library that were taken near a place's coordinates.
@Observable
@MainActor
final class PhotoSuggestionService {
    var suggestions: [PHAsset] = []
    var isLoading = false

    enum AuthorizationLevel {
        case notDetermined
        case full
        case limited
        case denied
    }

    private(set) var authorizationLevel: AuthorizationLevel = .notDetermined

    var photoIndexService: PhotoIndexService?

    private let cachingManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 200, height: 200) // 2x for 100pt display
    private let radiusMeters: CLLocationDistance = 200
    private let maxSuggestions = 5

    private var enumerationTask: Task<[PHAsset], Never>?
    private var libraryObserver: LibraryChangeObserver?
    private var debounceTask: Task<Void, Never>?

    // Callback for observer-triggered re-fetches — set by the view
    var onLibraryChange: (() async -> Void)?

    // MARK: - Authorization

    /// Non-prompting check — reads current status without showing a dialog.
    func checkCurrentAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationLevel = mapStatus(status)
    }

    func requestAuthorizationIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            authorizationLevel = mapStatus(status)
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            authorizationLevel = mapStatus(newStatus)
        default:
            authorizationLevel = .denied
        }
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> AuthorizationLevel {
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: - Trip Context

    struct TripContext {
        let logCoordinates: [CLLocationCoordinate2D]
    }

    // MARK: - Fetch Suggestions

    func fetchSuggestions(
        near coordinate: CLLocationCoordinate2D,
        tripContext: TripContext? = nil
    ) async {
        guard authorizationLevel == .full || authorizationLevel == .limited else { return }

        // Cancel any in-flight enumeration
        enumerationTask?.cancel()

        let placeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let allLocations = buildSearchLocations(primary: placeLocation, tripContext: tripContext)

        isLoading = true

        // Fast path: use spatial index if available
        if let indexService = photoIndexService,
           indexService.hasBuiltIndex,
           !indexService.isBuilding {
            let identifiers = indexService.query(near: allLocations, radiusMeters: radiusMeters)

            if !identifiers.isEmpty {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                var assets: [PHAsset] = []
                fetchResult.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }

                let sorted = assets.sorted { a, b in
                    let distA = minDistance(of: a, to: placeLocation)
                    let distB = minDistance(of: b, to: placeLocation)
                    return distA < distB
                }
                suggestions = Array(sorted.prefix(maxSuggestions))
            } else {
                suggestions = []
            }

            isLoading = false
            return
        }

        // Fallback: full enumeration (first launch while index builds)
        let radius = radiusMeters
        let max = maxSuggestions

        let task = Task.detached { [allLocations, radius, max] () -> [PHAsset] in
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

            var seen = Set<String>()
            var candidates: [PHAsset] = []

            assets.enumerateObjects { asset, _, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                guard let assetLocation = asset.location else { return }
                for location in allLocations {
                    if assetLocation.distance(from: location) <= radius {
                        if seen.insert(asset.localIdentifier).inserted {
                            candidates.append(asset)
                        }
                        break
                    }
                }
                if candidates.count >= max {
                    stop.pointee = true
                }
            }
            return candidates
        }

        enumerationTask = task
        let results = await task.value

        guard !task.isCancelled else { return }

        let sorted = results.sorted { a, b in
            let distA = minDistance(of: a, to: placeLocation)
            let distB = minDistance(of: b, to: placeLocation)
            return distA < distB
        }

        suggestions = Array(sorted.prefix(maxSuggestions))
        isLoading = false
    }

    private func buildSearchLocations(primary: CLLocation, tripContext: TripContext?) -> [CLLocation] {
        var locations = [primary]
        if let coords = tripContext?.logCoordinates {
            locations += coords.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        }
        return locations
    }

    private func minDistance(of asset: PHAsset, to target: CLLocation) -> CLLocationDistance {
        guard let loc = asset.location else { return .greatestFiniteMagnitude }
        return loc.distance(from: target)
    }

    // MARK: - Library Change Observer

    func startObservingLibrary() {
        guard libraryObserver == nil else { return }
        let observer = LibraryChangeObserver { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleLibraryChange()
            }
        }
        libraryObserver = observer
        PHPhotoLibrary.shared().register(observer)
    }

    func stopObservingLibrary() {
        if let observer = libraryObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
            libraryObserver = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func handleLibraryChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.onLibraryChange?()
        }
    }

    // MARK: - Image Loading

    func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            cachingManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            cachingManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Cleanup

    func clearSuggestions() {
        enumerationTask?.cancel()
        suggestions = []
        isLoading = false
    }
}

// MARK: - PHPhotoLibraryChangeObserver

/// Separate NSObject subclass because @Observable can't inherit from NSObject.
private final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
