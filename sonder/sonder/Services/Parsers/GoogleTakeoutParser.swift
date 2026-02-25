//
//  GoogleTakeoutParser.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import Foundation
import CoreLocation
import os

/// Parses Google Takeout export files into `ImportedPlaceEntry` arrays.
///
/// Supported formats:
/// - **GeoJSON** (`Saved Places.json`): Starred/favorited places with coordinates
/// - **CSV** (per-list files like `Want to Go.csv`): Custom list exports with URLs but no coordinates
enum GoogleTakeoutParser {

    private static let logger = Logger(subsystem: "com.sonder.app", category: "GoogleTakeoutParser")

    // MARK: - Public API

    /// Parse a file at the given URL, auto-detecting format from extension.
    /// The caller must have security-scoped access to the URL (via `.fileImporter`).
    static func parse(fileURL: URL) throws -> [ImportedPlaceEntry] {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "json":
            return try parseGeoJSON(fileURL: fileURL)
        case "csv":
            return try parseCSV(fileURL: fileURL)
        default:
            throw ImportParseError.unsupportedFileType(ext)
        }
    }

    // MARK: - GeoJSON Parsing

    /// Parse a Google Takeout GeoJSON file (e.g. `Saved Places.json`).
    static func parseGeoJSON(fileURL: URL) throws -> [ImportedPlaceEntry] {
        let data = try Data(contentsOf: fileURL)
        return try parseGeoJSON(data: data)
    }

    /// Parse GeoJSON data directly (for testing).
    static func parseGeoJSON(data: Data) throws -> [ImportedPlaceEntry] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportParseError.invalidFormat("Not a valid JSON object")
        }

        guard let features = json["features"] as? [[String: Any]] else {
            throw ImportParseError.invalidFormat("Missing 'features' array — is this a Google Takeout GeoJSON file?")
        }

        var entries: [ImportedPlaceEntry] = []

        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let title = properties["Title"] as? String,
                  !title.isEmpty else {
                continue
            }

            // Extract coordinate from geometry (GeoJSON uses [lng, lat])
            var coordinate: CLLocationCoordinate2D?
            if let geometry = feature["geometry"] as? [String: Any],
               let coords = geometry["coordinates"] as? [Double],
               coords.count >= 2 {
                let lng = coords[0]
                let lat = coords[1]
                if lat != 0 || lng != 0 {
                    coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }

            // Fallback: try Location in properties
            if coordinate == nil,
               let location = properties["Location"] as? [String: Any] {
                if let latStr = location["Latitude"] as? String,
                   let lngStr = location["Longitude"] as? String,
                   let lat = Double(latStr),
                   let lng = Double(lngStr),
                   (lat != 0 || lng != 0) {
                    coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }

            let sourceURL = properties["Google Maps URL"] as? String
            let address = properties["Address"] as? String

            // Parse date if available
            var dateAdded: Date?
            if let dateStr = properties["Published"] as? String {
                dateAdded = Self.parseDate(dateStr)
            }

            entries.append(ImportedPlaceEntry(
                name: title,
                address: address,
                coordinate: coordinate,
                sourceURL: sourceURL,
                dateAdded: dateAdded
            ))
        }

        if entries.isEmpty && !features.isEmpty {
            logger.warning("Parsed \(features.count) features but extracted 0 entries — check file format")
        }

        return entries
    }

    // MARK: - CSV Parsing

    /// Parse a Google Takeout CSV list file (e.g. `Want to Go.csv`).
    static func parseCSV(fileURL: URL) throws -> [ImportedPlaceEntry] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let listName = fileURL.deletingPathExtension().lastPathComponent
        return try parseCSV(content: content, listName: listName)
    }

    /// Parse CSV content directly (for testing).
    static func parseCSV(content: String, listName: String? = nil) throws -> [ImportedPlaceEntry] {
        let lines = content.components(separatedBy: .newlines)
        guard let headerLine = lines.first, !headerLine.isEmpty else {
            throw ImportParseError.invalidFormat("Empty CSV file")
        }

        let headers = parseCSVRow(headerLine)
        guard let titleIndex = headers.firstIndex(where: { $0.caseInsensitiveCompare("Title") == .orderedSame }) else {
            throw ImportParseError.invalidFormat("CSV missing 'Title' column — is this a Google Takeout file?")
        }

        let urlIndex = headers.firstIndex(where: { $0.caseInsensitiveCompare("URL") == .orderedSame })
        let noteIndex = headers.firstIndex(where: { $0.caseInsensitiveCompare("Note") == .orderedSame })
        let addressIndex = headers.firstIndex(where: { $0.caseInsensitiveCompare("Address") == .orderedSame })

        var entries: [ImportedPlaceEntry] = []

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let fields = parseCSVRow(trimmed)
            guard titleIndex < fields.count else { continue }

            let title = fields[titleIndex]
            guard !title.isEmpty else { continue }

            let url = urlIndex.flatMap { $0 < fields.count ? fields[$0] : nil }
            let address = addressIndex.flatMap { $0 < fields.count ? fields[$0] : nil }
            let note = noteIndex.flatMap { $0 < fields.count ? fields[$0] : nil }

            entries.append(ImportedPlaceEntry(
                name: title,
                address: address?.isEmpty == true ? nil : address,
                sourceURL: url?.isEmpty == true ? nil : url,
                sourceListName: listName ?? note
            ))
        }

        return entries
    }

    // MARK: - URL Parsing

    /// Extract a Google Place ID from a Google Maps URL.
    /// Handles formats:
    /// - `https://maps.google.com/?cid=12345` → CID (not a Place ID, but useful for lookup)
    /// - `https://www.google.com/maps/place/.../data=!...!1s0x...:0x...!...` → CID from hex
    /// - URLs containing `/place/ChIJ.../` → Place ID
    static func extractPlaceID(from urlString: String) -> String? {
        // Pattern 1: ChIJ-style Place IDs in URL path
        if let range = urlString.range(of: "ChIJ[A-Za-z0-9_-]+", options: .regularExpression) {
            return String(urlString[range])
        }

        // Pattern 2: ?cid= parameter
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let cid = components.queryItems?.first(where: { $0.name == "cid" })?.value {
            return "cid:\(cid)"
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Parse a single CSV row, handling quoted fields with commas.
    private static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in row {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))

        return fields
    }

    /// Try common date formats from Google Takeout exports.
    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - Errors

enum ImportParseError: LocalizedError {
    case unsupportedFileType(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext). Please select a .json or .csv file from Google Takeout."
        case .invalidFormat(let detail):
            return "This doesn't look like a Google Takeout file. \(detail)"
        }
    }
}
