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
        let calendarHeatmap = computeCalendarHeatmap(logs: logs)
        let streak = computeStreak(logs: logs)
        let dayOfWeek = computeDayOfWeekPattern(logs: logs)
        let bookends = computeBookends(logs: logs, placeMap: placeMap)
        let explorationStats = computeExplorationStats(logs: logs, placeMap: placeMap)

        return ProfileStats(
            tasteDNA: tasteDNA,
            archetype: archetype,
            categoryBreakdown: categoryBreakdown,
            ratingDistribution: ratingDistribution,
            calendarHeatmap: calendarHeatmap,
            streak: streak,
            dayOfWeek: dayOfWeek,
            bookends: bookends,
            explorationStats: explorationStats,
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

        let categoryColors: [ExploreMapFilter.CategoryFilter: Color] = [
            .food: SonderColors.terracotta,
            .coffee: SonderColors.sage,
            .nightlife: SonderColors.ochre,
            .outdoors: SonderColors.dustyRose,
            .shopping: SonderColors.warmBlue,
            .attractions: SonderColors.inkMuted,
        ]

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
                color: categoryColors[category] ?? SonderColors.inkMuted
            )
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: - Rating Distribution

    static func computeRatingDistribution(logs: [Log]) -> RatingDistribution {
        let skipCount = logs.filter { $0.rating == .skip }.count
        let solidCount = logs.filter { $0.rating == .solid }.count
        let mustSeeCount = logs.filter { $0.rating == .mustSee }.count
        let total = logs.count

        let philosophy: String
        if total == 0 {
            philosophy = "Start logging to discover your rating style"
        } else {
            let mustSeePct = Double(mustSeeCount) / Double(total)
            let skipPct = Double(skipCount) / Double(total)
            let solidPct = Double(solidCount) / Double(total)

            if mustSeePct > 0.6 {
                philosophy = "You're generous — \(Int(mustSeePct * 100))% of your places are Must-See"
            } else if skipPct > 0.4 {
                philosophy = "You have high standards — only the best make the cut"
            } else if mustSeePct < 0.15 && total >= 3 {
                philosophy = "A discerning palate — you save Must-See for the truly special"
            } else if abs(solidPct - mustSeePct) < 0.1 && abs(solidPct - skipPct) < 0.1 && total >= 3 {
                philosophy = "A balanced critic — you appreciate the full spectrum"
            } else if solidPct > 0.5 {
                philosophy = "You find the good in most places — a true optimist"
            } else {
                philosophy = "Every place tells a story in your journal"
            }
        }

        return RatingDistribution(
            skipCount: skipCount,
            solidCount: solidCount,
            mustSeeCount: mustSeeCount,
            philosophy: philosophy
        )
    }

    // MARK: - Calendar Heatmap

    static func computeCalendarHeatmap(logs: [Log]) -> CalendarHeatmapData {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .month, value: -6, to: endDate) ?? endDate

        guard !logs.isEmpty else {
            return CalendarHeatmapData(entries: [], startDate: startDate, endDate: endDate)
        }

        // Group logs by day
        var dayCounts: [Date: Int] = [:]
        for log in logs {
            let day = calendar.startOfDay(for: log.createdAt)
            if day >= startDate && day <= endDate {
                dayCounts[day, default: 0] += 1
            }
        }

        let entries = dayCounts
            .map { (date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }

        return CalendarHeatmapData(entries: entries, startDate: startDate, endDate: endDate)
    }

    // MARK: - Streak

    static func computeStreak(logs: [Log]) -> StreakData {
        guard !logs.isEmpty else {
            return StreakData(currentStreak: 0, longestStreak: 0, longestStreakStartDate: nil)
        }

        let calendar = Calendar.current
        let uniqueDays = Set(logs.map { calendar.startOfDay(for: $0.createdAt) })
        let sortedDays = uniqueDays.sorted()

        guard !sortedDays.isEmpty else {
            return StreakData(currentStreak: 0, longestStreak: 0, longestStreakStartDate: nil)
        }

        var currentStreak = 1
        var longestStreak = 1
        var longestStart = sortedDays[0]
        var streakStart = sortedDays[0]

        for i in 1..<sortedDays.count {
            let daysBetween = calendar.dateComponents([.day], from: sortedDays[i - 1], to: sortedDays[i]).day ?? 0
            if daysBetween == 1 {
                currentStreak += 1
                if currentStreak > longestStreak {
                    longestStreak = currentStreak
                    longestStart = streakStart
                }
            } else {
                currentStreak = 1
                streakStart = sortedDays[i]
            }
        }

        // Check if the current streak is still active (includes today or yesterday)
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastLogDay = sortedDays.last!

        let activeCurrentStreak: Int
        if lastLogDay == today || lastLogDay == yesterday {
            // Recalculate streak from the end
            activeCurrentStreak = computeCurrentStreakFromEnd(sortedDays: sortedDays, calendar: calendar)
        } else {
            activeCurrentStreak = 0
        }

        return StreakData(
            currentStreak: activeCurrentStreak,
            longestStreak: longestStreak,
            longestStreakStartDate: longestStart
        )
    }

    private static func computeCurrentStreakFromEnd(sortedDays: [Date], calendar: Calendar) -> Int {
        guard !sortedDays.isEmpty else { return 0 }

        var streak = 1
        for i in stride(from: sortedDays.count - 1, through: 1, by: -1) {
            let daysBetween = calendar.dateComponents([.day], from: sortedDays[i - 1], to: sortedDays[i]).day ?? 0
            if daysBetween == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - Day of Week Pattern

    static func computeDayOfWeekPattern(logs: [Log]) -> DayOfWeekPattern {
        let calendar = Calendar.current
        var counts = [Int](repeating: 0, count: 7)

        for log in logs {
            let weekday = calendar.component(.weekday, from: log.createdAt) - 1 // 0=Sun...6=Sat
            counts[weekday] += 1
        }

        let dayNames = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
        let maxCount = counts.max() ?? 0
        let peakIndex = counts.firstIndex(of: maxCount) ?? 0
        let total = counts.reduce(0, +)

        let weekdaySum = counts[1] + counts[2] + counts[3] + counts[4] + counts[5] // Mon-Fri
        let weekendSum = counts[0] + counts[6] // Sun+Sat
        let isWeekday = total > 0 ? Double(weekdaySum) / Double(total) > 0.7 : false

        return DayOfWeekPattern(
            counts: counts,
            peakDay: dayNames[peakIndex],
            peakPercentage: total > 0 ? Double(maxCount) / Double(total) : 0,
            isWeekdayExplorer: isWeekday
        )
    }

    // MARK: - Bookends

    static func computeBookends(logs: [Log], placeMap: [String: Place]) -> Bookends? {
        guard logs.count >= 2 else { return nil }

        let sorted = logs.sorted { $0.createdAt < $1.createdAt }
        guard let first = sorted.first, let latest = sorted.last,
              let firstPlace = placeMap[first.placeID],
              let latestPlace = placeMap[latest.placeID] else { return nil }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: first.createdAt, to: latest.createdAt).day ?? 0

        return Bookends(
            firstPlaceName: firstPlace.name,
            firstCity: extractCity(from: firstPlace.address),
            firstDate: first.createdAt,
            latestPlaceName: latestPlace.name,
            latestCity: extractCity(from: latestPlace.address),
            latestDate: latest.createdAt,
            daysBetween: days
        )
    }

    // MARK: - Exploration Stats

    static func computeExplorationStats(logs: [Log], placeMap: [String: Place]) -> ExplorationStats? {
        guard !logs.isEmpty else { return nil }

        // Pre-compute city for each place once
        var citiesForPlaces: [String: String] = [:]
        for (id, place) in placeMap {
            if let city = extractCity(from: place.address) {
                citiesForPlaces[id] = city
            }
        }

        let cumulativeDistance = computeCumulativeDistance(logs: logs, placeMap: placeMap)
        let cityPassportStamps = computeCityPassportStamps(logs: logs, citiesForPlaces: citiesForPlaces)
        let neighborhoodCoverage = computeNeighborhoodCoverage(logs: logs, placeMap: placeMap, citiesForPlaces: citiesForPlaces)
        let travelSparkline = computeTravelSparkline(logs: logs, placeMap: placeMap)
        let farthestFromHome = computeFarthestFromHome(logs: logs, placeMap: placeMap, citiesForPlaces: citiesForPlaces)
        let explorationScore = computeExplorationScore(logs: logs, placeMap: placeMap, citiesForPlaces: citiesForPlaces)

        return ExplorationStats(
            cumulativeDistance: cumulativeDistance,
            cityPassportStamps: cityPassportStamps,
            neighborhoodCoverage: neighborhoodCoverage,
            travelSparkline: travelSparkline,
            farthestFromHome: farthestFromHome,
            explorationScore: explorationScore
        )
    }

    // MARK: Cumulative Distance

    static func computeCumulativeDistance(logs: [Log], placeMap: [String: Place]) -> CumulativeDistance {
        let sorted = logs.sorted { $0.createdAt < $1.createdAt }
        var totalMiles = 0.0

        for i in 1..<sorted.count {
            guard let prev = placeMap[sorted[i - 1].placeID],
                  let curr = placeMap[sorted[i].placeID] else { continue }
            totalMiles += haversineDistance(lat1: prev.latitude, lng1: prev.longitude,
                                           lat2: curr.latitude, lng2: curr.longitude)
        }

        // Miles this month
        let calendar = Calendar.current
        let now = Date()
        let thisMonthLogs = sorted.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
        var milesThisMonth = 0.0

        if !thisMonthLogs.isEmpty {
            // Include leg from last pre-month log to first this-month log
            if let firstThisMonth = thisMonthLogs.first,
               let firstIdx = sorted.firstIndex(where: { $0.id == firstThisMonth.id }),
               firstIdx > 0 {
                let prevLog = sorted[firstIdx - 1]
                if let prevPlace = placeMap[prevLog.placeID],
                   let currPlace = placeMap[firstThisMonth.placeID] {
                    milesThisMonth += haversineDistance(lat1: prevPlace.latitude, lng1: prevPlace.longitude,
                                                       lat2: currPlace.latitude, lng2: currPlace.longitude)
                }
            }
            // Sum distances within this month
            for i in 1..<thisMonthLogs.count {
                guard let prev = placeMap[thisMonthLogs[i - 1].placeID],
                      let curr = placeMap[thisMonthLogs[i].placeID] else { continue }
                milesThisMonth += haversineDistance(lat1: prev.latitude, lng1: prev.longitude,
                                                   lat2: curr.latitude, lng2: curr.longitude)
            }
        }

        let loggedPlaceIDs = Set(logs.map { $0.placeID })
        let loggedPlaces = loggedPlaceIDs.compactMap { placeMap[$0] }
        let cities = Set(loggedPlaces.compactMap { extractCity(from: $0.address) })
        let countries = Set(loggedPlaces.compactMap { extractCountry(from: $0.address) })

        return CumulativeDistance(
            totalMiles: totalMiles,
            cityCount: cities.count,
            countryCount: countries.count,
            milesThisMonth: milesThisMonth
        )
    }

    // MARK: City Passport Stamps

    static func computeCityPassportStamps(logs: [Log], citiesForPlaces: [String: String]) -> [CityStamp] {
        var cityCounts: [String: Int] = [:]
        for log in logs {
            if let city = citiesForPlaces[log.placeID] {
                cityCounts[city, default: 0] += 1
            }
        }
        return cityCounts
            .map { CityStamp(id: $0.key, cityName: $0.key, logCount: $0.value) }
            .sorted { $0.logCount > $1.logCount }
    }

    // MARK: Neighborhood Coverage

    static func computeNeighborhoodCoverage(logs: [Log], placeMap: [String: Place], citiesForPlaces: [String: String]) -> NeighborhoodCoverage? {
        // Find top city by log count
        var cityLogCounts: [String: Int] = [:]
        for log in logs {
            if let city = citiesForPlaces[log.placeID] {
                cityLogCounts[city, default: 0] += 1
            }
        }
        guard let topCity = cityLogCounts.max(by: { $0.value < $1.value }),
              topCity.value >= 2 else { return nil }

        // Get places in top city
        let cityPlaceIDs = Set(logs.compactMap { log -> String? in
            citiesForPlaces[log.placeID] == topCity.key ? log.placeID : nil
        })

        // Bucket into 0.01° grid cells (~0.7mi)
        var zones = Set<String>()
        for placeID in cityPlaceIDs {
            guard let place = placeMap[placeID] else { continue }
            let gridLat = Int(floor(place.latitude / 0.01))
            let gridLng = Int(floor(place.longitude / 0.01))
            zones.insert("\(gridLat),\(gridLng)")
        }

        return NeighborhoodCoverage(
            cityName: topCity.key,
            uniqueZones: zones.count,
            totalLogsInCity: topCity.value
        )
    }

    // MARK: Travel Sparkline

    static func computeTravelSparkline(logs: [Log], placeMap: [String: Place]) -> TravelSparkline {
        let sorted = logs.sorted { $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else { return TravelSparkline(dataPoints: []) }

        var dataPoints: [(date: Date, cumulativeMiles: Double)] = []
        var cumulative = 0.0
        dataPoints.append((date: sorted[0].createdAt, cumulativeMiles: 0))

        for i in 1..<sorted.count {
            guard let prev = placeMap[sorted[i - 1].placeID],
                  let curr = placeMap[sorted[i].placeID] else {
                dataPoints.append((date: sorted[i].createdAt, cumulativeMiles: cumulative))
                continue
            }
            cumulative += haversineDistance(lat1: prev.latitude, lng1: prev.longitude,
                                           lat2: curr.latitude, lng2: curr.longitude)
            dataPoints.append((date: sorted[i].createdAt, cumulativeMiles: cumulative))
        }

        return TravelSparkline(dataPoints: dataPoints)
    }

    // MARK: Farthest From Home

    static func computeFarthestFromHome(logs: [Log], placeMap: [String: Place], citiesForPlaces: [String: String]) -> FarthestFromHome? {
        // Infer home = city with most logged places
        var cityPlaceSets: [String: Set<String>] = [:]
        for log in logs {
            if let city = citiesForPlaces[log.placeID] {
                cityPlaceSets[city, default: []].insert(log.placeID)
            }
        }
        guard cityPlaceSets.count >= 2 else { return nil }

        let homeCity = cityPlaceSets.max(by: { $0.value.count < $1.value.count })!

        // Compute centroid of home places
        let homePlaces = homeCity.value.compactMap { placeMap[$0] }
        guard !homePlaces.isEmpty else { return nil }
        let centerLat = homePlaces.map(\.latitude).reduce(0, +) / Double(homePlaces.count)
        let centerLng = homePlaces.map(\.longitude).reduce(0, +) / Double(homePlaces.count)

        // Find farthest non-home place
        let nonHomePlaceIDs = Set(logs.map(\.placeID)).subtracting(homeCity.value)
        var farthestPlace: Place?
        var farthestDist = 0.0

        for placeID in nonHomePlaceIDs {
            guard let place = placeMap[placeID] else { continue }
            let dist = haversineDistance(lat1: centerLat, lng1: centerLng,
                                        lat2: place.latitude, lng2: place.longitude)
            if dist > farthestDist {
                farthestDist = dist
                farthestPlace = place
            }
        }

        guard let place = farthestPlace else { return nil }

        return FarthestFromHome(
            homeCityName: homeCity.key,
            placeName: place.name,
            placeCity: extractCity(from: place.address),
            distanceMiles: farthestDist
        )
    }

    // MARK: Exploration Score

    static func computeExplorationScore(logs: [Log], placeMap: [String: Place], citiesForPlaces: [String: String]) -> ExplorationScore {
        let uniqueCities = Set(citiesForPlaces.values)
        let uniqueCountries = Set(placeMap.values.compactMap { extractCountry(from: $0.address) })

        // Unique categories from logged places
        var matchedCategories = Set<ExploreMapFilter.CategoryFilter>()
        let loggedPlaceIDs = Set(logs.map(\.placeID))
        for placeID in loggedPlaceIDs {
            guard let place = placeMap[placeID] else { continue }
            let placeTypes = Set(place.types)
            for category in ExploreMapFilter.CategoryFilter.allCases {
                if !placeTypes.isDisjoint(with: category.placeTypes) {
                    matchedCategories.insert(category)
                }
            }
        }

        let cityPoints = uniqueCities.count * 10
        let countryPoints = uniqueCountries.count * 50
        let logPoints = logs.count * 1
        let categoryPoints = matchedCategories.count * 5
        let score = cityPoints + countryPoints + logPoints + categoryPoints

        let level: String
        switch score {
        case 0..<50: level = "Newcomer"
        case 50..<150: level = "Local"
        case 150..<300: level = "Adventurer"
        case 300..<500: level = "Globetrotter"
        default: level = "World Explorer"
        }

        return ExplorationScore(
            score: score,
            level: level,
            cityPoints: cityPoints,
            countryPoints: countryPoints,
            logPoints: logPoints,
            categoryPoints: categoryPoints
        )
    }

    // MARK: - Helpers

    static func ratingWeight(_ rating: Rating) -> Double {
        switch rating {
        case .skip: return 1.0
        case .solid: return 2.0
        case .mustSee: return 3.0
        }
    }

    static func extractCity(from address: String) -> String? {
        let components = address.components(separatedBy: ", ")
        guard components.count >= 2 else { return nil }
        if components.count >= 3 {
            return components[components.count - 3]
        }
        return components[0]
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

    /// Haversine distance in miles between two coordinates
    static func haversineDistance(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let R = 3958.8 // Earth radius in miles
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }
}
