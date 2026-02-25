//
//  PlaceImportService.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import Foundation
import CoreLocation
import os

/// Orchestrates importing places from external files into the Want to Go list.
///
/// Flow: Parse file → resolve each entry via Google Places API → save to WantToGo + cache.
/// Rate-limited (200ms between API calls) to avoid Google Places quota issues.
@MainActor
@Observable
final class PlaceImportService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "PlaceImportService")

    private let googlePlacesService: GooglePlacesService
    private let wantToGoService: WantToGoService
    private let savedListsService: SavedListsService
    private let placesCacheService: PlacesCacheService

    /// The currently running import job (nil when idle).
    private(set) var activeJob: ImportJob?

    /// Whether an import is in progress.
    var isImporting: Bool { activeJob != nil }

    /// Result of the last completed import.
    private(set) var lastSummary: ImportSummary?

    /// Error from the last file parse attempt.
    private(set) var parseError: String?

    func setParseError(_ message: String?) {
        parseError = message
    }

    /// Minimum delay between Google Places API calls (rate limiting).
    private static let apiDelayMs: UInt64 = 200

    /// Maximum distance (meters) for a resolved place to be considered a match.
    private static let maxMatchDistanceMeters: Double = 500

    init(
        googlePlacesService: GooglePlacesService,
        wantToGoService: WantToGoService,
        savedListsService: SavedListsService,
        placesCacheService: PlacesCacheService
    ) {
        self.googlePlacesService = googlePlacesService
        self.wantToGoService = wantToGoService
        self.savedListsService = savedListsService
        self.placesCacheService = placesCacheService
    }

    // MARK: - Parse File

    /// Parse a file and return entries without importing them (for preview).
    func parseFile(url: URL) -> [ImportedPlaceEntry] {
        parseError = nil
        // Security-scoped access for files from the document picker
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let entries = try GoogleTakeoutParser.parse(fileURL: url)
            if entries.isEmpty {
                parseError = "No places found in this file."
            }
            return entries
        } catch {
            parseError = error.localizedDescription
            logger.error("Parse failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Import

    /// Import entries into the Want to Go list, resolving each via Google Places API.
    ///
    /// - Parameters:
    ///   - entries: Parsed place entries to import.
    ///   - userID: The current user's ID.
    ///   - targetListID: Optional list ID to add places to. If nil, places are added without a list.
    /// - Returns: Summary of the import results.
    @discardableResult
    func importEntries(
        _ entries: [ImportedPlaceEntry],
        userID: String,
        targetListID: String?
    ) async -> ImportSummary {
        let job = ImportJob(entries: entries)
        activeJob = job

        for entry in entries {
            guard !Task.isCancelled else { break }

            job.setCurrentEntry(entry.name)

            // Check if already saved (by name match against cached places)
            if let placeID = findCachedPlaceID(for: entry),
               wantToGoService.isInWantToGo(placeID: placeID, userID: userID) {
                job.markResolved(entryID: entry.id, result: .skipped)
                continue
            }

            // Resolve via Google Places API
            let result = await resolvePlace(entry)
            job.markResolved(entryID: entry.id, result: result)

            // Save resolved places
            if case .resolved(let details) = result {
                await saveResolvedPlace(details, userID: userID, listID: targetListID)
            }

            // Rate limit
            try? await Task.sleep(nanoseconds: Self.apiDelayMs * 1_000_000)
        }

        let summary = ImportSummary(
            totalAttempted: job.totalCount,
            successCount: job.resolvedCount,
            failedCount: job.failedCount,
            skippedCount: job.skippedCount,
            listName: nil
        )

        lastSummary = summary
        activeJob = nil
        return summary
    }

    // MARK: - Resolution

    /// Resolve a single entry to a PlaceDetails via Google Places API.
    func resolvePlace(_ entry: ImportedPlaceEntry) async -> PlaceResolutionResult {
        // Strategy 1: Extract Place ID from Google Maps URL
        if let urlString = entry.sourceURL,
           let extractedID = GoogleTakeoutParser.extractPlaceID(from: urlString) {
            // CID-based IDs aren't directly usable with getPlaceDetails,
            // but ChIJ-style IDs are
            if !extractedID.hasPrefix("cid:") {
                if let details = await googlePlacesService.getPlaceDetails(placeId: extractedID) {
                    return .resolved(details)
                }
            }
        }

        // Strategy 2: Name + coordinates → autocomplete with location bias + distance verify
        if let coord = entry.coordinate {
            let predictions = await googlePlacesService.autocomplete(
                query: entry.name,
                location: coord
            )
            if let bestMatch = predictions.first {
                if let details = await googlePlacesService.getPlaceDetails(placeId: bestMatch.placeId) {
                    // Verify distance
                    let resolvedLocation = CLLocation(latitude: details.latitude, longitude: details.longitude)
                    let sourceLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let distance = resolvedLocation.distance(from: sourceLocation)

                    if distance <= Self.maxMatchDistanceMeters {
                        return .resolved(details)
                    } else {
                        logger.info("Distance mismatch for '\(entry.name)': \(Int(distance))m > \(Int(Self.maxMatchDistanceMeters))m")
                    }
                }
            }
        }

        // Strategy 3: Name only → autocomplete without location (least reliable)
        let predictions = await googlePlacesService.autocomplete(query: entry.name)
        if let bestMatch = predictions.first {
            if let details = await googlePlacesService.getPlaceDetails(placeId: bestMatch.placeId) {
                return .resolved(details)
            }
        }

        return .failed("Could not find '\(entry.name)' on Google Maps")
    }

    // MARK: - Save

    /// Save a resolved place to WantToGo and cache it.
    func saveResolvedPlace(
        _ details: PlaceDetails,
        userID: String,
        listID: String?
    ) async {
        // Cache the place in SwiftData
        _ = placesCacheService.cachePlace(from: details)

        // Add to Want to Go (dedup is built-in)
        do {
            try await wantToGoService.addToWantToGo(
                placeID: details.placeId,
                userID: userID,
                placeName: details.name,
                placeAddress: details.formattedAddress,
                photoReference: details.photoReference,
                listID: listID
            )
        } catch {
            logger.error("Failed to save WantToGo for \(details.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Try to find a cached place matching the entry by name (fuzzy).
    private func findCachedPlaceID(for entry: ImportedPlaceEntry) -> String? {
        let results = placesCacheService.searchCachedPlaces(query: entry.name)
        // Exact name match only for dedup
        return results.first(where: {
            $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
        })?.id
    }
}
