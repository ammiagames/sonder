//
//  CalendarHeatmapView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

struct CalendarHeatmapView: View {
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
                    HStack(alignment: .top, spacing: 0) {
                        // Day labels column
                        VStack(spacing: cellSpacing) {
                            // Month label spacer
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
                                    // Month label (show at start of month)
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
                .onAppear {
                    // Scroll to current week
                    if !weeks.isEmpty {
                        proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                    }
                }
            }

            // Color scale legend
            HStack(spacing: SonderSpacing.xs) {
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

    // MARK: - Data Processing

    private var countsByDate: [Date: Int] {
        Dictionary(uniqueKeysWithValues: data.entries.map { ($0.date, $0.count) })
    }

    private func countForDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return countsByDate[dayStart] ?? 0
    }

    /// Returns weeks as arrays of 7 optional dates (Sun=0...Sat=6)
    private var weeks: [[Date?]] {
        let calendar = Calendar.current
        var result: [[Date?]] = []

        // Start from the Sunday of the start date's week
        var current = data.startDate
        let weekday = calendar.component(.weekday, from: current) - 1 // 0=Sun
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

        // Find first non-nil date in the week
        guard let firstDate = weeks[weekIndex].compactMap({ $0 }).first else { return nil }
        let day = calendar.component(.day, from: firstDate)

        // Show month label if the first day of the week is in the first 7 days of a month
        if day <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: firstDate)
        }
        return nil
    }

    // MARK: - Color Scale

    private func colorForCount(_ count: Int) -> Color {
        switch count {
        case 0: return SonderColors.cream
        case 1: return SonderColors.terracotta.opacity(0.25)
        case 2...3: return SonderColors.terracotta.opacity(0.55)
        default: return SonderColors.terracotta
        }
    }
}
