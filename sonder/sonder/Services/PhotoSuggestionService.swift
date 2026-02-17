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
    var isAuthorized = false

    private let cachingManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 200, height: 200) // 2x for 100pt display
    private let radiusMeters: CLLocationDistance = 200
    private let dayWindow: TimeInterval = 3 * 24 * 60 * 60 // ±3 days
    private let fallbackWindow: TimeInterval = 90 * 24 * 60 * 60 // 90 days back
    private let maxSuggestions = 5

    // MARK: - Authorization

    func requestAuthorizationIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            isAuthorized = true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            isAuthorized = newStatus == .authorized || newStatus == .limited
        default:
            isAuthorized = false
        }
    }

    // MARK: - Trip Context

    struct TripContext {
        let startDate: Date?
        let endDate: Date?
        let logCoordinates: [CLLocationCoordinate2D] // other logs in the trip
    }

    // MARK: - Fetch Suggestions

    func fetchSuggestions(
        near coordinate: CLLocationCoordinate2D,
        visitedAt: Date,
        tripContext: TripContext? = nil
    ) async {
        guard isAuthorized else { return }

        let placeLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let allLocations = buildSearchLocations(primary: placeLocation, tripContext: tripContext)
        let dateRange = buildDateRange(visitedAt: visitedAt, tripContext: tripContext)

        // First try: narrow date range
        var results = findNearbyPhotos(locations: allLocations, from: dateRange.narrow.start, to: dateRange.narrow.end)

        // Fallback: widen date range if no results
        if results.isEmpty {
            results = findNearbyPhotos(locations: allLocations, from: dateRange.wide.start, to: dateRange.wide.end)
        }

        // Sort: closest to the primary place first
        results.sort { a, b in
            let distA = minDistance(of: a, to: placeLocation)
            let distB = minDistance(of: b, to: placeLocation)
            return distA < distB
        }

        suggestions = Array(results.prefix(maxSuggestions))
    }

    private func buildSearchLocations(primary: CLLocation, tripContext: TripContext?) -> [CLLocation] {
        var locations = [primary]
        if let coords = tripContext?.logCoordinates {
            locations += coords.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        }
        return locations
    }

    private func buildDateRange(visitedAt: Date, tripContext: TripContext?) -> (narrow: (start: Date, end: Date), wide: (start: Date, end: Date)) {
        let narrowStart: Date
        let narrowEnd: Date
        let wideStart: Date
        let wideEnd: Date

        if let trip = tripContext, let tripStart = trip.startDate, let tripEnd = trip.endDate {
            // Use trip date range as the narrow window
            narrowStart = tripStart.addingTimeInterval(-dayWindow)
            narrowEnd = tripEnd.addingTimeInterval(dayWindow)
            wideStart = tripStart.addingTimeInterval(-fallbackWindow)
            wideEnd = tripEnd.addingTimeInterval(dayWindow)
        } else {
            narrowStart = visitedAt.addingTimeInterval(-dayWindow)
            narrowEnd = visitedAt.addingTimeInterval(dayWindow)
            wideStart = visitedAt.addingTimeInterval(-fallbackWindow)
            wideEnd = visitedAt
        }

        return (narrow: (narrowStart, narrowEnd), wide: (wideStart, wideEnd))
    }

    private func minDistance(of asset: PHAsset, to target: CLLocation) -> CLLocationDistance {
        guard let loc = asset.location else { return .greatestFiniteMagnitude }
        return loc.distance(from: target)
    }

    private func findNearbyPhotos(locations: [CLLocation], from startDate: Date, to endDate: Date) -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var seen = Set<String>()
        var candidates: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            guard let assetLocation = asset.location else { return }
            for location in locations {
                if assetLocation.distance(from: location) <= self.radiusMeters {
                    if seen.insert(asset.localIdentifier).inserted {
                        candidates.append(asset)
                    }
                    break
                }
            }
        }
        return candidates
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
        suggestions = []
    }
}
