//
//  HeatmapShowcaseView.swift
//  sonder
//
//  Displays all 7 heatmap variations side-by-side with sample data
//  for visual comparison. Accessible from ProfileView during iteration.
//

import SwiftUI

struct HeatmapShowcaseView: View {
    private let sampleData = HeatmapShowcaseView.generateSampleData()

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.lg) {

                // Current (baseline)
                section(title: "Current", subtitle: "Original GitHub-style grid") {
                    CalendarHeatmapView(data: sampleData)
                }

                // 1. Isometric 3D
                section(title: "1. Isometric 3D", subtitle: "Cells rise as 3D columns based on activity") {
                    HeatmapIsometricView(data: sampleData)
                }

                // 2. Seasonal Flow
                section(title: "2. Seasonal Flow", subtitle: "Colors shift by season across the calendar") {
                    HeatmapSeasonalView(data: sampleData)
                }

                // 3. Dot Garden
                section(title: "3. Dot Garden", subtitle: "Circles bloom larger with more activity") {
                    HeatmapDotGardenView(data: sampleData)
                }

                // 4. Streak Glow
                section(title: "4. Streak Glow", subtitle: "Glowing threads connect consecutive active days") {
                    HeatmapStreakGlowView(data: sampleData)
                }

                // 5. Interactive
                section(title: "5. Interactive", subtitle: "Wave animation, today pulse, tap for details") {
                    HeatmapInteractiveView(data: sampleData)
                }

                // 6. Radial Rings
                section(title: "6. Radial Rings", subtitle: "Concentric month rings, inner = oldest") {
                    HeatmapRadialView(data: sampleData)
                }

                // 7. Heat Aura
                section(title: "7. Heat Aura", subtitle: "Warm glow radiates from active cells") {
                    HeatmapAuraView(data: sampleData)
                }
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .navigationTitle("Heatmap Variations")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section Helper

    private func section<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text(title)
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            Text(subtitle)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)

            content()
        }
    }

    // MARK: - Sample Data Generation

    /// Generates 6 months of realistic-looking activity data
    /// with streaks, quiet periods, and busy weekends.
    static func generateSampleData() -> CalendarHeatmapData {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .month, value: -6, to: endDate)!

        // Use a seeded-style approach for deterministic data
        // (based on day-of-year so it looks the same each render)
        var entries: [(date: Date, count: Int)] = []
        var current = startDate

        while current <= endDate {
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: current) ?? 1
            let weekday = calendar.component(.weekday, from: current)
            let weekOfYear = calendar.component(.weekOfYear, from: current)

            // Create patterns:
            // - Weekends slightly more active
            // - Every few weeks have a "travel burst" (high activity)
            // - Some weeks are quiet
            let isWeekend = weekday == 1 || weekday == 7
            let isTravelWeek = weekOfYear % 5 == 0 || weekOfYear % 5 == 1
            let isQuietWeek = weekOfYear % 7 == 3

            let hash = (dayOfYear * 7 + weekday * 13 + weekOfYear * 3) % 100

            var count = 0
            if isQuietWeek {
                // Mostly empty
                if hash < 10 { count = 1 }
            } else if isTravelWeek {
                // Very active
                if hash < 60 { count = Int((hash % 4) + 1) }
                if hash < 30 { count = min(count + 2, 5) }
            } else {
                // Normal activity
                let threshold = isWeekend ? 40 : 25
                if hash < threshold {
                    count = max(1, (hash % 3) + 1)
                }
            }

            if count > 0 {
                entries.append((date: calendar.startOfDay(for: current), count: count))
            }

            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        return CalendarHeatmapData(entries: entries, startDate: startDate, endDate: endDate)
    }
}

#Preview {
    NavigationStack {
        HeatmapShowcaseView()
    }
}
