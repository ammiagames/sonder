//
//  TagSuggestions.swift
//  sonder
//
//  Created by Codex on 2/21/26.
//

import Foundation

/// Canonical key for tag comparisons (trimmed, case-insensitive, diacritic-insensitive).
func normalizedTagKey(_ rawTag: String) -> String {
    rawTag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

/// Returns unique tags for a user in most-recently-used order.
/// Pass logs ordered from newest to oldest (e.g. `@Query(..., order: .reverse)`).
func recentTagsByUsage(logs: [Log], userID: String) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []

    for log in logs where log.userID == userID {
        for rawTag in log.tags {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedTagKey(tag)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(tag)
        }
    }

    return ordered
}

/// Merges recent and fallback tags, excluding selected tags and duplicates.
/// Recent tags are always prioritized, then fallback tags fill the remainder.
func prioritizedTagSuggestions(
    recentTags: [String],
    fallbackTags: [String],
    selectedTags: [String],
    limit: Int
) -> [String] {
    guard limit > 0 else { return [] }

    var seen = Set(selectedTags.map(normalizedTagKey))
    var ordered: [String] = []

    func appendIfNeeded(_ rawTag: String) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizedTagKey(tag)
        guard !key.isEmpty, !seen.contains(key) else { return }
        seen.insert(key)
        ordered.append(tag)
    }

    recentTags.forEach(appendIfNeeded)
    fallbackTags.forEach(appendIfNeeded)

    return Array(ordered.prefix(limit))
}
