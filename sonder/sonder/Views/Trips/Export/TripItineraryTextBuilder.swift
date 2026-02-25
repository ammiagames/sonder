//
//  TripItineraryTextBuilder.swift
//  sonder
//
//  Pure function — builds a styled plain-text itinerary from TripExportData.
//  No UI dependency, fully testable.
//

import Foundation

enum TripItineraryTextBuilder {

    static func buildText(from data: TripExportData) -> String {
        var lines: [String] = []

        // Header line
        var header = "\u{1F9F3} \(data.tripName)"
        if let dateText = data.dateRangeText {
            header += "  \u{00B7}  \(dateText)"
        }
        header += "  \u{00B7}  \(data.placeCount) stops"
        lines.append(header)
        lines.append("")

        guard !data.stops.isEmpty else {
            return lines.joined(separator: "\n")
        }

        for (index, stop) in data.stops.enumerated() {
            let number = index + 1
            lines.append("\(number). \(stop.rating.emoji) \(stop.placeName)")

            if !stop.address.isEmpty {
                lines.append("   \u{1F4CD} \(stop.address)")
            }

            if let note = stop.note, !note.isEmpty {
                lines.append("   \u{201C}\(note)\u{201D}")
            }

            if !stop.tags.isEmpty {
                let tagLine = stop.tags.map { "#\($0)" }.joined(separator: " ")
                lines.append("   \(tagLine)")
            }

            if !stop.placeID.isEmpty {
                lines.append("   \u{1F5FA} https://www.google.com/maps/place/?q=place_id:\(stop.placeID)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
