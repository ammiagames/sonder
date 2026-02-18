//
//  JournalShared.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI

// MARK: - Card Frame Preference Key

/// Preference key for collecting rendered card positions in the masonry grid.
/// Each card reports its frame (keyed by chronological index) so the trail overlay can draw connecting lines.
struct CardFramePreference: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Trip Sorting

/// Sorts trips in reverse chronological order: by start date if available, otherwise by creation date.
func sortTripsReverseChronological(_ trips: [Trip]) -> [Trip] {
    trips.sorted { a, b in
        let aDate = a.startDate ?? a.createdAt
        let bDate = b.startDate ?? b.createdAt
        return aDate > bDate
    }
}

// MARK: - Masonry Column Assignment

struct MasonryColumnAssignment {
    let trip: Trip
    let index: Int
    let column: Int
}

/// Assigns trips to left (0) or right (1) columns using a greedy shortest-column algorithm.
/// Preserves the input order (index 0 = first trip displayed at top).
func assignMasonryColumns(trips: [Trip], spacing: CGFloat = 10, estimateHeight: (Trip) -> CGFloat) -> [MasonryColumnAssignment] {
    var leftHeight: CGFloat = 0
    var rightHeight: CGFloat = 0
    var result: [MasonryColumnAssignment] = []

    for (index, trip) in trips.enumerated() {
        let h = estimateHeight(trip)
        if leftHeight <= rightHeight {
            result.append(MasonryColumnAssignment(trip: trip, index: index, column: 0))
            leftHeight += h + spacing
        } else {
            result.append(MasonryColumnAssignment(trip: trip, index: index, column: 1))
            rightHeight += h + spacing
        }
    }
    return result
}
