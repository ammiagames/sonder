//
//  BulkImportModels.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import Foundation
import CoreLocation

// MARK: - Photo Metadata

/// Metadata extracted from a PHAsset for clustering.
/// Pure value type — not persisted.
struct PhotoMetadata: Identifiable, Sendable {
    let id: String // PHAsset localIdentifier
    let coordinate: CLLocationCoordinate2D?
    let creationDate: Date?
}

// MARK: - Photo Cluster

/// A group of photos clustered by proximity and date.
struct PhotoCluster: Identifiable {
    let id: UUID
    var photoMetadata: [PhotoMetadata]
    var centroid: CLLocationCoordinate2D?
    var date: Date?
    var suggestedPlaces: [NearbyPlace]
    var confirmedPlace: Place?
    var rating: Rating?

    init(
        id: UUID = UUID(),
        photoMetadata: [PhotoMetadata],
        centroid: CLLocationCoordinate2D? = nil,
        date: Date? = nil,
        suggestedPlaces: [NearbyPlace] = [],
        confirmedPlace: Place? = nil,
        rating: Rating? = nil
    ) {
        self.id = id
        self.photoMetadata = photoMetadata
        self.centroid = centroid
        self.date = date
        self.suggestedPlaces = suggestedPlaces
        self.confirmedPlace = confirmedPlace
        self.rating = rating
    }
}

// MARK: - Bulk Import State

/// Flow state for the bulk import process.
enum BulkImportState: Equatable {
    case selecting
    case extracting(progress: Double)
    case clustering
    case resolving(progress: Double)
    case reviewing
    case saving(progress: Double)
    case complete(logCount: Int)
    case failed(String)

    var displayText: String {
        switch self {
        case .selecting: return "Select Photos"
        case .extracting: return "Extracting locations..."
        case .clustering: return "Grouping photos..."
        case .resolving: return "Finding places..."
        case .reviewing: return "Review"
        case .saving: return "Creating logs..."
        case .complete(let count): return "Created \(count) logs"
        case .failed(let message): return message
        }
    }

    var progress: Double? {
        switch self {
        case .extracting(let p), .resolving(let p), .saving(let p): return p
        default: return nil
        }
    }
}
