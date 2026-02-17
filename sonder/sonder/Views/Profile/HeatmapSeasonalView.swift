//
//  HeatmapSeasonalView.swift
//  sonder
//
//  Variation 2: Seasonal Color Flow
//  Colors shift by month — sage in spring, ochre in summer,
//  terracotta in autumn, warm blue in winter.
//

import SwiftUI

struct HeatmapSeasonalView: View {
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
                                                .fill(seasonalColor(for: date, count: count))
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

            // Seasonal legend
            HStack(spacing: SonderSpacing.sm) {
                seasonLegendDot(color: winterColor, label: "Winter")
                seasonLegendDot(color: springColor, label: "Spring")
                seasonLegendDot(color: summerColor, label: "Summer")
                seasonLegendDot(color: autumnColor, label: "Autumn")
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    private func seasonLegendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(SonderColors.inkLight)
        }
    }

    // MARK: - Seasonal Colors

    private let winterColor = Color(red: 0.45, green: 0.58, blue: 0.68)   // warm blue
    private let springColor = Color(red: 0.50, green: 0.68, blue: 0.45)   // fresh sage
    private let summerColor = Color(red: 0.85, green: 0.68, blue: 0.40)   // golden ochre
    private let autumnColor = Color(red: 0.80, green: 0.45, blue: 0.35)   // terracotta

    private func seasonalColor(for date: Date, count: Int) -> Color {
        guard count > 0 else { return SonderColors.cream }

        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)

        let base: Color
        switch month {
        case 12, 1, 2: base = winterColor
        case 3, 4, 5: base = springColor
        case 6, 7, 8: base = summerColor
        case 9, 10, 11: base = autumnColor
        default: base = SonderColors.terracotta
        }

        switch count {
        case 1: return base.opacity(0.3)
        case 2...3: return base.opacity(0.6)
        default: return base
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
