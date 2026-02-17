//
//  HeatmapStreakGlowView.swift
//  sonder
//
//  Variation 4: Streak Glow
//  Standard grid with glowing connecting lines through
//  consecutive active days. Long streaks glow brighter.
//

import SwiftUI

struct HeatmapStreakGlowView: View {
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
                    ZStack(alignment: .topLeading) {
                        // Streak glow layer (behind the grid)
                        streakGlowLayer
                            .padding(.leading, 14) // match day label width

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
                // Streak indicator
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(SonderColors.terracotta.opacity(0.4))
                        .frame(width: 20, height: 3)
                    Text("Streak")
                        .font(.system(size: 9))
                        .foregroundColor(SonderColors.inkLight)
                }

                Spacer()

                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)

                ForEach([0, 1, 2, 4], id: \.self) { count in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForCount(count))
                        .frame(width: cellSize, height: cellSize)
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

    // MARK: - Streak Glow Layer

    private var streakGlowLayer: some View {
        Canvas { context, size in
            let offsetY: CGFloat = 12 // month label height
            let streaks = computeStreaks()

            for streak in streaks {
                guard streak.count >= 2 else { continue }

                let glowIntensity = min(Double(streak.count) / 7.0, 1.0)
                let glowColor = SonderColors.terracotta.opacity(0.15 + 0.25 * glowIntensity)
                let lineWidth: CGFloat = 3 + CGFloat(glowIntensity) * 3

                var path = Path()
                for (i, pos) in streak.positions.enumerated() {
                    let x = CGFloat(pos.week) * (cellSize + cellSpacing) + cellSize / 2
                    let y = offsetY + CGFloat(pos.day) * (cellSize + cellSpacing) + cellSize / 2

                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Outer glow
                context.stroke(
                    path,
                    with: .color(glowColor),
                    style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round, lineJoin: .round)
                )

                // Inner line
                context.stroke(
                    path,
                    with: .color(SonderColors.terracotta.opacity(0.3 + 0.3 * glowIntensity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(
            width: CGFloat(weeks.count) * (cellSize + cellSpacing),
            height: 12 + 7 * (cellSize + cellSpacing)
        )
    }

    // MARK: - Streak Computation

    private struct GridPosition {
        let week: Int
        let day: Int
    }

    private struct Streak {
        var positions: [GridPosition]
        var count: Int { positions.count }
    }

    private func computeStreaks() -> [Streak] {
        var streaks: [Streak] = []
        var currentStreak: [GridPosition] = []

        // Flatten grid into chronological order
        for weekIndex in 0..<weeks.count {
            for dayIndex in 0..<7 {
                guard let date = weeks[weekIndex][dayIndex] else {
                    if currentStreak.count >= 2 {
                        streaks.append(Streak(positions: currentStreak))
                    }
                    currentStreak = []
                    continue
                }

                let count = countForDate(date)
                if count > 0 {
                    currentStreak.append(GridPosition(week: weekIndex, day: dayIndex))
                } else {
                    if currentStreak.count >= 2 {
                        streaks.append(Streak(positions: currentStreak))
                    }
                    currentStreak = []
                }
            }
        }

        if currentStreak.count >= 2 {
            streaks.append(Streak(positions: currentStreak))
        }

        return streaks
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
