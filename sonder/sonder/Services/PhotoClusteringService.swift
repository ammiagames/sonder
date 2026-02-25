//
//  PhotoClusteringService.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import Foundation
import CoreLocation

/// Pure stateless clustering logic for grouping geotagged photos by proximity and date.
enum PhotoClusteringService {

    /// Groups photos into clusters where all members are within `radiusMeters` of the cluster
    /// centroid and on the same calendar day.
    ///
    /// Algorithm (greedy, O(n·k) where k = cluster count):
    /// 1. Sort photos by date
    /// 2. For each photo, find an existing cluster within `radiusMeters` on the same calendar day
    /// 3. If found → add to cluster, update centroid. If not → new cluster
    /// 4. Photos without GPS are returned separately
    ///
    /// - Parameters:
    ///   - photos: Photo metadata extracted from PHAssets
    ///   - radiusMeters: Maximum distance (in meters) to merge into an existing cluster. Default 200m.
    /// - Returns: Tuple of (located clusters, unlocated photo metadata)
    static func cluster(
        photos: [PhotoMetadata],
        radiusMeters: Double = 200
    ) -> (clusters: [PhotoCluster], unlocated: [PhotoMetadata]) {

        // Separate photos with and without GPS
        var located: [PhotoMetadata] = []
        var unlocated: [PhotoMetadata] = []

        for photo in photos {
            if photo.coordinate != nil {
                located.append(photo)
            } else {
                unlocated.append(photo)
            }
        }

        // Sort by date (nil dates go to the end)
        located.sort { a, b in
            guard let da = a.creationDate else { return false }
            guard let db = b.creationDate else { return true }
            return da < db
        }

        let calendar = Calendar.current
        var clusters: [MutableCluster] = []

        for photo in located {
            guard let coord = photo.coordinate else { continue }
            let photoLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

            // Try to find a matching cluster: same calendar day + within radius
            var bestIndex: Int?
            var bestDistance: Double = .infinity

            for (index, cluster) in clusters.enumerated() {
                // Check same calendar day
                if let photoDate = photo.creationDate, let clusterDate = cluster.representativeDate {
                    guard calendar.isDate(photoDate, inSameDayAs: clusterDate) else { continue }
                } else if photo.creationDate != nil || cluster.representativeDate != nil {
                    // One has a date and the other doesn't — skip
                    continue
                }

                let clusterLocation = CLLocation(latitude: cluster.centroidLat, longitude: cluster.centroidLon)
                let distance = photoLocation.distance(from: clusterLocation)

                if distance <= radiusMeters && distance < bestDistance {
                    bestIndex = index
                    bestDistance = distance
                }
            }

            if let index = bestIndex {
                clusters[index].add(photo)
            } else {
                clusters.append(MutableCluster(firstPhoto: photo))
            }
        }

        let result = clusters.map { $0.toPhotoCluster() }
        return (clusters: result, unlocated: unlocated)
    }
}

// MARK: - Internal Mutable Cluster

private struct MutableCluster {
    var photos: [PhotoMetadata]
    var centroidLat: Double
    var centroidLon: Double
    var representativeDate: Date?

    init(firstPhoto: PhotoMetadata) {
        self.photos = [firstPhoto]
        self.centroidLat = firstPhoto.coordinate?.latitude ?? 0
        self.centroidLon = firstPhoto.coordinate?.longitude ?? 0
        self.representativeDate = firstPhoto.creationDate
    }

    mutating func add(_ photo: PhotoMetadata) {
        let count = Double(photos.count)
        if let coord = photo.coordinate {
            // Running average for centroid
            centroidLat = (centroidLat * count + coord.latitude) / (count + 1)
            centroidLon = (centroidLon * count + coord.longitude) / (count + 1)
        }
        photos.append(photo)
        // Keep earliest date as representative
        if let photoDate = photo.creationDate {
            if let existing = representativeDate {
                if photoDate < existing { representativeDate = photoDate }
            } else {
                representativeDate = photoDate
            }
        }
    }

    func toPhotoCluster() -> PhotoCluster {
        PhotoCluster(
            photoMetadata: photos,
            centroid: CLLocationCoordinate2D(latitude: centroidLat, longitude: centroidLon),
            date: representativeDate
        )
    }
}
