//
//  HeatmapDotGardenView.swift
//  sonder
//
//  Variation 3: Dot Garden
//  Circles instead of squares, with varying sizes.
//  High-activity days bloom with layered petal circles.
//

import SwiftUI

struct HeatmapDotGardenView: View {
    let data: CalendarHeatmapData

    private let cellSize: CGFloat = 12
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
                                            gardenDot(count: count)
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
                .onAppear {
                    if !weeks.isEmpty {
                        proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                    }
                }
            }

            // Legend
            HStack(spacing: SonderSpacing.sm) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)

                ForEach([0, 1, 2, 4], id: \.self) { count in
                    gardenDot(count: count)
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

    // MARK: - Garden Dot

    @ViewBuilder
    private func gardenDot(count: Int) -> some View {
        let dotSize = dotSizeForCount(count)
        let color = colorForCount(count)

        ZStack {
            if count >= 4 {
                // Bloom effect: outer glow petals
                Circle()
                    .fill(SonderColors.ochre.opacity(0.15))
                    .frame(width: cellSize, height: cellSize)

                Circle()
                    .fill(SonderColors.terracotta.opacity(0.25))
                    .frame(width: dotSize + 3, height: dotSize + 3)
            }

            if count >= 2 {
                // Mid glow
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: dotSize + 1.5, height: dotSize + 1.5)
            }

            // Core dot
            Circle()
                .fill(count == 0 ? SonderColors.cream : color)
                .frame(width: dotSize, height: dotSize)
        }
    }

    private func dotSizeForCount(_ count: Int) -> CGFloat {
        switch count {
        case 0: return 4
        case 1: return 6
        case 2...3: return 8
        default: return 10
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
        case 1: return SonderColors.sage.opacity(0.5)
        case 2...3: return SonderColors.sage
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
