//
//  JournalShared.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI

// MARK: - Trail Style

enum TrailStyle: String, CaseIterable {
    case zigzag = "A"
    case spine = "B"
    case columns = "C"
}

// MARK: - Journal Segment

enum JournalSegment: String, CaseIterable {
    case trips = "Trips"
    case logs = "Logs"
}

// MARK: - Card Frame Preference Key

/// Preference key for collecting rendered card positions in the masonry grid.
/// Each card reports its frame (keyed by chronological index) so the trail overlay can draw connecting lines.
struct CardFramePreference: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
