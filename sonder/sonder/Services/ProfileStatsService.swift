//
//  ProfileStatsService.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import Foundation
import SwiftUI

/// Pure computation service for profile personalization stats.
/// Takes arrays of Log and Place — no SwiftData dependency.
enum ProfileStatsService {

    // MARK: - Main Entry Point

    static func compute(logs: [Log], places: [Place]) -> ProfileStats {
        let placeMap = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })

        let tasteDNA = computeTasteDNA(logs: logs, placeMap: placeMap)
        let archetype = classifyArchetype(tasteDNA: tasteDNA, logs: logs, placeMap: placeMap)
        let categoryBreakdown = computeCategoryBreakdown(logs: logs, placeMap: placeMap)
        let ratingDistribution = computeRatingDistribution(logs: logs)

        return ProfileStats(
            tasteDNA: tasteDNA,
            archetype: archetype,
            categoryBreakdown: categoryBreakdown,
            ratingDistribution: ratingDistribution,
            totalLogs: logs.count
        )
    }

    // MARK: - Taste DNA

    static func computeTasteDNA(logs: [Log], placeMap: [String: Place]) -> TasteDNA {
        guard !logs.isEmpty else { return .zero }

        var scores: [ExploreMapFilter.CategoryFilter: Double] = [:]
        for category in ExploreMapFilter.CategoryFilter.allCases {
            scores[category] = 0
        }

        for log in logs {
            guard let place = placeMap[log.placeID] else { continue }
            let placeTypes = Set(place.types)
            let weight = ratingWeight(log.rating)

            for category in ExploreMapFilter.CategoryFilter.allCases {
                if !placeTypes.isDisjoint(with: category.placeTypes) {
                    scores[category, default: 0] += weight
                }
            }
        }

        let maxScore = scores.values.max() ?? 0
        guard maxScore > 0 else { return .zero }

        return TasteDNA(
            food: scores[.food, default: 0] / maxScore,
            coffee: scores[.coffee, default: 0] / maxScore,
            nightlife: scores[.nightlife, default: 0] / maxScore,
            outdoors: scores[.outdoors, default: 0] / maxScore,
            shopping: scores[.shopping, default: 0] / maxScore,
            attractions: scores[.attractions, default: 0] / maxScore
        )
    }

    // MARK: - Archetype Classification

    static func classifyArchetype(tasteDNA: TasteDNA, logs: [Log], placeMap: [String: Place]) -> ExplorerArchetype {
        guard !logs.isEmpty else { return .explorer }

        // Check dominant category (>60%)
        let axes = [
            (ExplorerArchetype.foodie, tasteDNA.food),
            (.cultureVulture, tasteDNA.attractions),
            (.nightOwl, tasteDNA.nightlife),
        ]

        for (archetype, value) in axes {
            if value > 0.6 {
                return archetype
            }
        }

        // High city count + low revisits → Wanderer
        let uniquePlaceIDs = Set(logs.map { $0.placeID })
        let cities = Set(logs.compactMap { placeMap[$0.placeID] }.compactMap { extractCity(from: $0.address) })
        let revisitRatio = logs.count > 0 ? Double(uniquePlaceIDs.count) / Double(logs.count) : 0

        if cities.count >= 3 && revisitRatio > 0.8 {
            return .wanderer
        }

        // High notes/tags ratio → Curator
        let logsWithNotes = logs.filter { $0.note != nil && !($0.note?.isEmpty ?? true) }.count
        let logsWithTags = logs.filter { !$0.tags.isEmpty }.count
        let detailRatio = Double(logsWithNotes + logsWithTags) / Double(logs.count * 2)

        if detailRatio > 0.5 {
            return .curator
        }

        return .explorer
    }

    // MARK: - Category Breakdown

    static func computeCategoryBreakdown(logs: [Log], placeMap: [String: Place]) -> [CategoryStat] {
        guard !logs.isEmpty else { return [] }

        var counts: [ExploreMapFilter.CategoryFilter: Int] = [:]
        var categorizedCount = 0

        for log in logs {
            guard let place = placeMap[log.placeID] else { continue }
            let placeTypes = Set(place.types)

            for category in ExploreMapFilter.CategoryFilter.allCases {
                if !placeTypes.isDisjoint(with: category.placeTypes) {
                    counts[category, default: 0] += 1
                    categorizedCount += 1
                    break // Count each log in at most one category (primary)
                }
            }
        }

        guard categorizedCount > 0 else { return [] }

        return ExploreMapFilter.CategoryFilter.allCases.compactMap { category in
            let count = counts[category, default: 0]
            guard count > 0 else { return nil }
            return CategoryStat(
                category: category.label,
                icon: category.icon,
                count: count,
                percentage: Double(count) / Double(categorizedCount),
                color: category.color
            )
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Rating Distribution

    static func computeRatingDistribution(logs: [Log]) -> RatingDistribution {
        var skipCount = 0
        var okayCount = 0
        var greatCount = 0
        var mustSeeCount = 0
        for log in logs {
            switch log.rating {
            case .skip: skipCount += 1
            case .okay: okayCount += 1
            case .great: greatCount += 1
            case .mustSee: mustSeeCount += 1
            }
        }
        let total = logs.count

        let philosophy: String
        if total == 0 {
            philosophy = "Start logging to discover your rating style"
        } else {
            let mustSeePct = Double(mustSeeCount) / Double(total)
            let skipPct = Double(skipCount) / Double(total)
            let positivePct = Double(greatCount + mustSeeCount) / Double(total)

            if mustSeePct > 0.5 {
                philosophy = "You're generous — \(Int(mustSeePct * 100))% of your places are Must-See"
            } else if skipPct > 0.4 {
                philosophy = "You have high standards — only the best make the cut"
            } else if mustSeePct < 0.15 && total >= 3 {
                philosophy = "A discerning palate — you save Must-See for the truly special"
            } else if positivePct > 0.6 && total >= 3 {
                philosophy = "You find the good in most places — a true optimist"
            } else {
                philosophy = "Every place tells a story in your journal"
            }
        }

        return RatingDistribution(
            skipCount: skipCount,
            okayCount: okayCount,
            greatCount: greatCount,
            mustSeeCount: mustSeeCount,
            philosophy: philosophy
        )
    }

    // MARK: - Helpers

    static func ratingWeight(_ rating: Rating) -> Double {
        switch rating {
        case .skip: return 1.0
        case .okay: return 1.5
        case .great: return 2.5
        case .mustSee: return 3.0
        }
    }

    static func extractCity(from address: String) -> String? {
        let components = address.components(separatedBy: ", ")
        guard components.count >= 2 else { return nil }

        if components.count == 2 {
            return components[0].trimmingCharacters(in: .whitespaces)
        }

        // City is typically third-from-last: "Street, City, State ZIP, Country"
        let potentialCity = components[components.count - 3].trimmingCharacters(in: .whitespaces)

        // If it looks like a state abbreviation or contains numbers, try one earlier
        if potentialCity.count <= 2 || potentialCity.contains(where: { $0.isNumber }) {
            if components.count >= 4 {
                return components[components.count - 4].trimmingCharacters(in: .whitespaces)
            }
        }

        return potentialCity.isEmpty ? nil : potentialCity
    }

    static func extractCountry(from address: String) -> String? {
        let components = address.components(separatedBy: ", ")
        guard let last = components.last else { return nil }
        let trimmed = last.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 2 || trimmed.allSatisfy({ $0.isNumber }) {
            return components.count >= 2 ? components[components.count - 2] : nil
        }
        return trimmed
    }

}
