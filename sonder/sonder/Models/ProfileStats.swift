//
//  ProfileStats.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import Foundation
import SwiftUI

// MARK: - ProfileStats (Container)

struct ProfileStats {
    let tasteDNA: TasteDNA
    let archetype: ExplorerArchetype
    let categoryBreakdown: [CategoryStat]
    let ratingDistribution: RatingDistribution
    let calendarHeatmap: CalendarHeatmapData
    let streak: StreakData
    let dayOfWeek: DayOfWeekPattern
    let bookends: Bookends?
    let totalLogs: Int
}

// MARK: - Taste DNA

struct TasteDNA {
    let food: Double       // 0...1
    let coffee: Double
    let nightlife: Double
    let outdoors: Double
    let shopping: Double
    let attractions: Double

    var axes: [(label: String, icon: String, value: Double)] {
        [
            ("Food", "fork.knife", food),
            ("Coffee", "cup.and.saucer", coffee),
            ("Nightlife", "moon.stars", nightlife),
            ("Outdoors", "leaf", outdoors),
            ("Shopping", "bag", shopping),
            ("Attractions", "building.columns", attractions),
        ]
    }

    var isEmpty: Bool {
        food == 0 && coffee == 0 && nightlife == 0 && outdoors == 0 && shopping == 0 && attractions == 0
    }

    static let zero = TasteDNA(food: 0, coffee: 0, nightlife: 0, outdoors: 0, shopping: 0, attractions: 0)
}

// MARK: - Explorer Archetype

enum ExplorerArchetype: String, CaseIterable {
    case foodie
    case cultureVulture
    case nightOwl
    case wanderer
    case photographer
    case completionist
    case curator
    case explorer // default

    var displayName: String {
        switch self {
        case .foodie: return "Foodie"
        case .cultureVulture: return "Culture Vulture"
        case .nightOwl: return "Night Owl"
        case .wanderer: return "Wanderer"
        case .photographer: return "Photographer"
        case .completionist: return "Completionist"
        case .curator: return "Curator"
        case .explorer: return "Explorer"
        }
    }

    var icon: String {
        switch self {
        case .foodie: return "fork.knife"
        case .cultureVulture: return "building.columns"
        case .nightOwl: return "moon.stars"
        case .wanderer: return "figure.walk"
        case .photographer: return "camera"
        case .completionist: return "checkmark.seal"
        case .curator: return "text.quote"
        case .explorer: return "safari"
        }
    }

    var description: String {
        switch self {
        case .foodie: return "You live to eat — restaurants are your compass"
        case .cultureVulture: return "Museums, galleries, landmarks — you soak it all in"
        case .nightOwl: return "Bars, clubs, and late nights are your thing"
        case .wanderer: return "Always exploring new cities and neighborhoods"
        case .photographer: return "You capture every moment with photos"
        case .completionist: return "Detailed notes and tags on everything you visit"
        case .curator: return "Your logs read like a travel guide"
        case .explorer: return "A curious soul discovering the world one place at a time"
        }
    }
}

// MARK: - Category Stat

struct CategoryStat: Identifiable {
    let id = UUID()
    let category: String
    let icon: String
    let count: Int
    let percentage: Double
    let color: Color
}

// MARK: - Rating Distribution

struct RatingDistribution {
    let skipCount: Int
    let solidCount: Int
    let mustSeeCount: Int

    var total: Int { skipCount + solidCount + mustSeeCount }

    var skipPercentage: Double {
        total == 0 ? 0 : Double(skipCount) / Double(total)
    }
    var solidPercentage: Double {
        total == 0 ? 0 : Double(solidCount) / Double(total)
    }
    var mustSeePercentage: Double {
        total == 0 ? 0 : Double(mustSeeCount) / Double(total)
    }

    let philosophy: String
}

// MARK: - Calendar Heatmap Data

struct CalendarHeatmapData {
    let entries: [(date: Date, count: Int)]
    let startDate: Date
    let endDate: Date
}

// MARK: - Streak Data

struct StreakData {
    let currentStreak: Int
    let longestStreak: Int
    let longestStreakStartDate: Date?
}

// MARK: - Day of Week Pattern

struct DayOfWeekPattern {
    let counts: [Int] // 7 elements: Sun=0...Sat=6
    let peakDay: String
    let peakPercentage: Double
    let isWeekdayExplorer: Bool
}

// MARK: - Bookends

struct Bookends {
    let firstPlaceName: String
    let firstCity: String?
    let firstDate: Date
    let latestPlaceName: String
    let latestCity: String?
    let latestDate: Date
    let daysBetween: Int
}

