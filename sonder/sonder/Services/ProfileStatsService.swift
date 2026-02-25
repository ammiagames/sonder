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

        let philosophy = ratingPhilosophy(
            total: logs.count,
            skipCount: skipCount,
            okayCount: okayCount,
            greatCount: greatCount,
            mustSeeCount: mustSeeCount
        )

        return RatingDistribution(
            skipCount: skipCount,
            okayCount: okayCount,
            greatCount: greatCount,
            mustSeeCount: mustSeeCount,
            philosophy: philosophy
        )
    }

    // MARK: - Rating Philosophy (Musings)

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func ratingPhilosophy(
        total: Int,
        skipCount: Int,
        okayCount: Int,
        greatCount: Int,
        mustSeeCount: Int
    ) -> String {
        guard total > 0 else {
            return "Start logging to discover your rating style"
        }

        let mustSeePct = Double(mustSeeCount) / Double(total)
        let skipPct = Double(skipCount) / Double(total)
        let okayPct = Double(okayCount) / Double(total)
        let greatPct = Double(greatCount) / Double(total)
        let positivePct = Double(greatCount + mustSeeCount) / Double(total)

        // ── Single log ──────────────────────────────────────────────
        if total == 1 {
            if mustSeeCount == 1 { return "First place logged and it's already a Must-See — the bar is set" }
            if greatCount == 1 { return "A great start — one place down, a world to go" }
            if okayCount == 1 { return "The journey of a thousand places begins with one honest review" }
            return "Starting with a Skip — at least you know what you don't like"
        }

        // ── Two logs ────────────────────────────────────────────────
        if total == 2 {
            if mustSeeCount == 2 { return "Two for two on Must-Sees — golden taste or golden luck?" }
            if skipCount == 2 { return "Two Skips — the hunt for something great is on" }
            if greatCount == 2 { return "Two Great ratings — building a solid foundation" }
            if okayCount == 2 { return "Two Okays — keeping it real from the start" }
            if mustSeeCount == 1 && skipCount == 1 { return "A Must-See and a Skip — you already contain multitudes" }
            if mustSeeCount == 1 && greatCount == 1 { return "Nothing but love so far — every place has earned it" }
            if mustSeeCount == 1 && okayCount == 1 { return "A Must-See and an Okay — when it hits, it really hits" }
            if skipCount == 1 && greatCount == 1 { return "A Great and a Skip — you already know what works for you" }
            if skipCount == 1 && okayCount == 1 { return "Still warming up — the best discoveries lie ahead" }
            if okayCount == 1 && greatCount == 1 { return "An Okay and a Great — your rating scale is taking shape" }
            return "Two places rated — your rating personality is forming"
        }

        // ── 3+ logs ─────────────────────────────────────────────────

        // All the same rating
        let ratingsUsed = [skipCount, okayCount, greatCount, mustSeeCount].filter { $0 > 0 }.count
        if ratingsUsed == 1 {
            if mustSeeCount == total { return "Everything's a Must-See — the world looks amazing through your eyes" }
            if greatCount == total { return "Steady at Great across the board — consistent and confident" }
            if okayCount == total { return "All Okay — you're an even-keeled, honest rater" }
            return "Nothing's hit the mark yet — your perfect place is still out there"
        }

        // Heavy must-see (>50%)
        if mustSeePct > 0.5 {
            if mustSeePct > 0.8 && total >= 5 { return "A Must-See machine — \(Int(mustSeePct * 100))% of your places get top marks" }
            if mustSeePct > 0.7 { return "You're generous — \(Int(mustSeePct * 100))% of your places are Must-See" }
            if total >= 15 { return "Must-See collector — with \(mustSeeCount) top-rated spots, you clearly know where to go" }
            if total >= 8 { return "An enthusiast at heart — over half your places earn the highest mark" }
            return "You see the best in places — your Must-Sees are stacking up"
        }

        // Heavy skip (>40%)
        if skipPct > 0.4 {
            if skipPct > 0.7 { return "The toughest critic around — your praise is rare and meaningful" }
            if total >= 15 { return "With \(skipCount) Skips out of \(total), you've seen plenty that didn't cut it — selective taste" }
            if total >= 8 { return "A tough critic — when you say Must-See, people should listen" }
            return "You have high standards — only the best make the cut"
        }

        // No must-sees at all
        if mustSeeCount == 0 && total >= 4 {
            if total >= 15 { return "\(total) places and still no Must-See — it'll hit different when it finally comes" }
            if total >= 10 { return "Still searching for that first Must-See — you'll know it when you find it" }
            if skipCount == 0 { return "No extremes yet — you're rating in the comfortable middle" }
            return "Saving your Must-See for something truly unforgettable"
        }

        // No skips at all
        if skipCount == 0 && total >= 4 {
            if total >= 15 { return "Not a single Skip in \(total) places — you have a serious gift for picking winners" }
            if total >= 10 { return "Zero Skips across \(total) ratings — you really know how to choose" }
            if mustSeePct > 0.3 { return "Skip-free and loving it — you find Must-Sees wherever you go" }
            return "Zero Skips so far — you really know how to choose your spots"
        }

        // Low must-see (<15%)
        if mustSeePct < 0.15 {
            if total >= 15 { return "Only \(mustSeeCount) Must-See out of \(total) — your top rating is truly exclusive" }
            if total >= 8 { return "Must-See is sacred to you — only the extraordinary qualifies" }
            return "A discerning palate — you save Must-See for the truly special"
        }

        // Mostly positive (>60%)
        if positivePct > 0.6 {
            if positivePct > 0.8 && total >= 5 { return "The eternal optimist — \(Int(positivePct * 100))% of your places are Great or Must-See" }
            if total >= 10 { return "Positivity runs through your ratings — the world looks good through your lens" }
            return "You find the good in most places — a true optimist"
        }

        // Heavy okay (>50%)
        if okayPct > 0.5 {
            if total >= 8 { return "Okay is your anchor — honest and grounded, never overselling" }
            return "You tell it like it is — not every place needs to blow your mind"
        }

        // Heavy great (>50%)
        if greatPct > 0.5 {
            if total >= 8 { return "Great is your sweet spot — solid taste, no hype needed" }
            return "Reliably Great — you know quality when you see it"
        }

        // Balanced rater (no single rating > 35%)
        let maxPct = max(mustSeePct, max(skipPct, max(okayPct, greatPct)))
        if maxPct <= 0.35 && total >= 6 {
            if total >= 15 { return "A true spectrum rater — \(total) places spread across every tier" }
            return "Perfectly balanced — you really use the full rating scale"
        }

        // Early journey (3–5 logs), no extreme distribution
        if total <= 5 {
            if mustSeeCount > 0 && skipCount > 0 {
                return "Your story is just getting started — you've already seen the highs and lows"
            }
            if skipCount == 0 { return "No Skips yet — you're picking good spots early on" }
            return "A handful of places rated — your story is taking shape"
        }

        // Seasoned rater
        if total >= 20 {
            return "\(total) places rated — your journal is becoming a proper guide"
        }

        // Mid-range fallback
        if total >= 10 {
            return "Your ratings tell the story of everywhere you've been"
        }

        // Default
        return "Every place tells a story in your journal"
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
