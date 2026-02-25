//
//  ImportModels.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import Foundation
import CoreLocation

// MARK: - Imported Place Entry

/// A place parsed from an import file, before resolution via Google Places API.
/// Pure value type — not persisted.
struct ImportedPlaceEntry: Identifiable, Sendable {
    let id: UUID
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D?
    let sourceURL: String?
    let sourceListName: String?
    let dateAdded: Date?

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil,
        sourceURL: String? = nil,
        sourceListName: String? = nil,
        dateAdded: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.sourceURL = sourceURL
        self.sourceListName = sourceListName
        self.dateAdded = dateAdded
    }
}

// MARK: - Place Resolution Result

/// Outcome of resolving a single ImportedPlaceEntry via Google Places API.
enum PlaceResolutionResult: Sendable {
    case resolved(PlaceDetails)
    case skipped       // Already in Want to Go
    case failed(String) // Error message
}

// MARK: - Import Job

/// Observable state for an in-progress import operation.
@MainActor
@Observable
final class ImportJob: Identifiable {
    let id = UUID()
    let entries: [ImportedPlaceEntry]

    var totalCount: Int { entries.count }
    private(set) var resolvedCount: Int = 0
    private(set) var failedCount: Int = 0
    private(set) var skippedCount: Int = 0
    private(set) var results: [UUID: PlaceResolutionResult] = [:]

    /// The entry currently being resolved (for progress display).
    private(set) var currentEntryName: String?

    var processedCount: Int { resolvedCount + failedCount + skippedCount }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    init(entries: [ImportedPlaceEntry]) {
        self.entries = entries
    }

    func markResolved(entryID: UUID, result: PlaceResolutionResult) {
        results[entryID] = result
        switch result {
        case .resolved: resolvedCount += 1
        case .skipped: skippedCount += 1
        case .failed: failedCount += 1
        }
    }

    func setCurrentEntry(_ name: String?) {
        currentEntryName = name
    }
}

// MARK: - Import Summary

/// Final result after an import completes.
struct ImportSummary: Sendable {
    let totalAttempted: Int
    let successCount: Int
    let failedCount: Int
    let skippedCount: Int
    let listName: String?
}

// MARK: - Import Source

/// The source platform for an import.
enum ImportSource: String, CaseIterable, Identifiable {
    case googleMaps = "Google Maps"

    var id: String { rawValue }

    var iconSystemName: String {
        switch self {
        case .googleMaps: return "map"
        }
    }

    var description: String {
        switch self {
        case .googleMaps: return "Import your saved places via Google Takeout"
        }
    }
}
