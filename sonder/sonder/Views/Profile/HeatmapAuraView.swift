//
//  HeatmapAuraView.swift
//  sonder
//
//  Variation 7: Heat Aura / Bloom
//  Standard grid with gaussian blur glow behind active cells.
//  Active weeks look like they're radiating warmth.
//

import SwiftUI

struct HeatmapAuraView: View {
    let data: CalendarHeatmapData

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 2
    private let dayLabels = ["", "M", "", "W", "", "F", ""]

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Logging activity")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack {
                        // Aura glow layer (behind)
                        auraLayer

                        // Normal grid (on top)
                        HStack(alignment: .top, spacing: 0) {
                            // Day labels column
                            VStack(spacing: cellSpacing) {
                                Color.clear.frame(height: 12)
                                ForEach(0..<7, id: \.self) { day in
                                    Text(dayLabels[day])
                                        .font(.system(size: 8))
                                        .foregroundColor(SonderColors.inkLight)
                                        .frame(width: 14, height: cellSize)
                                }
                            }

                            // Grid
                            HStack(spacing: cellSpacing) {
                                ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                                    VStack(spacing: cellSpacing) {
                                        if let monthLabel = monthLabelForWeek(weekIndex) {
                                            Text(monthLabel)
                                                .font(.system(size: 8))
                                                .foregroundColor(SonderColors.inkLight)
                                                .frame(height: 12)
                                        } else {
                                            Color.clear.frame(height: 12)
                                        }

                                        ForEach(0..<7, id: \.self) { dayIndex in
                                            if let date = week[dayIndex] {
                                                let count = countForDate(date)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(colorForCount(count))
                                                    .frame(width: cellSize, height: cellSize)
                                            } else {
                                                Color.clear
                                                    .frame(width: cellSize, height: cellSize)
                                            }
                                        }
                                    }
                                    .id(weekIndex)
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
                .onAppear {
                    if !weeks.isEmpty {
                        proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                    }
                }
            }

            // Legend
            HStack(spacing: SonderSpacing.xs) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)

                ForEach([0, 1, 2, 4], id: \.self) { count in
                    ZStack {
                        if count >= 2 {
                            Circle()
                                .fill(colorForCount(count).opacity(0.3))
                                .frame(width: 14, height: 14)
                                .blur(radius: 2)
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForCount(count))
                            .frame(width: cellSize, height: cellSize)
                    }
                    .frame(width: 16, height: 16)
                }

                Text("More")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Aura Glow Layer

    private var auraLayer: some View {
        HStack(alignment: .top, spacing: 0) {
            // Day label spacer
            Color.clear.frame(width: 14)

            HStack(spacing: cellSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                    VStack(spacing: cellSpacing) {
                        Color.clear.frame(height: 12)

                        ForEach(0..<7, id: \.self) { dayIndex in
                            if let date = week[dayIndex] {
                                let count = countForDate(date)
                                ZStack {
                                    if count >= 3 {
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [
                                                        SonderColors.terracotta.opacity(0.35),
                                                        SonderColors.ochre.opacity(0.15),
                                                        Color.clear
                                                    ],
                                                    center: .center,
                                                    startRadius: 2,
                                                    endRadius: 14
                                                )
                                            )
                                            .frame(width: 28, height: 28)
                                    } else if count >= 1 {
                                        Circle()
                                            .fill(
                                                RadialGradient(
                                                    colors: [
                                                        SonderColors.terracotta.opacity(0.15),
                                                        Color.clear
                                                    ],
                                                    center: .center,
                                                    startRadius: 1,
                                                    endRadius: 8
                                                )
                                            )
                                            .frame(width: 16, height: 16)
                                    }
                                }
                                .frame(width: cellSize, height: cellSize)
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Processing

    private var countsByDate: [Date: Int] {
        Dictionary(uniqueKeysWithValues: data.entries.map { ($0.date, $0.count) })
    }

    private func countForDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return countsByDate[dayStart] ?? 0
    }

    private func colorForCount(_ count: Int) -> Color {
        switch count {
        case 0: return SonderColors.cream
        case 1: return SonderColors.terracotta.opacity(0.25)
        case 2...3: return SonderColors.terracotta.opacity(0.55)
        default: return SonderColors.terracotta
        }
    }

    private var weeks: [[Date?]] {
        let calendar = Calendar.current
        var result: [[Date?]] = []
        var current = data.startDate
        let weekday = calendar.component(.weekday, from: current) - 1
        current = calendar.date(byAdding: .day, value: -weekday, to: current)!
        let endDate = data.endDate
        while current <= endDate {
            var week: [Date?] = []
            for dayOffset in 0..<7 {
                let date = calendar.date(byAdding: .day, value: dayOffset, to: current)!
                if date >= data.startDate && date <= endDate {
                    week.append(date)
                } else {
                    week.append(nil)
                }
            }
            result.append(week)
            current = calendar.date(byAdding: .day, value: 7, to: current)!
        }
        return result
    }

    private func monthLabelForWeek(_ weekIndex: Int) -> String? {
        let calendar = Calendar.current
        guard weekIndex < weeks.count else { return nil }
        guard let firstDate = weeks[weekIndex].compactMap({ $0 }).first else { return nil }
        let day = calendar.component(.day, from: firstDate)
        if day <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: firstDate)
        }
        return nil
    }
}
