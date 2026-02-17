//
//  HeatmapIsometricView.swift
//  sonder
//
//  Variation 1: Isometric 3D Bars
//  Each cell is a small 3D column that rises based on activity count.
//

import SwiftUI

struct HeatmapIsometricView: View {
    let data: CalendarHeatmapData

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 14
    private let dayLabels = ["", "M", "", "W", "", "F", ""]

    // Isometric projection angles
    private let isoAngle: CGFloat = .pi / 6 // 30 degrees

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Logging activity")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    Canvas { context, size in
                        let offsetX: CGFloat = 20 // space for day labels
                        let offsetY: CGFloat = 12 + maxBarHeight // space for month labels + bar height

                        // Draw day labels
                        for day in 0..<7 {
                            let label = dayLabels[day]
                            guard !label.isEmpty else { continue }
                            let y = offsetY + CGFloat(day) * (cellSize + cellSpacing) + cellSize / 2
                            let text = Text(label)
                                .font(.system(size: 8))
                                .foregroundColor(SonderColors.inkLight)
                            context.draw(text, at: CGPoint(x: 7, y: y))
                        }

                        // Draw grid with isometric cells
                        let weeksArray = weeks
                        for (weekIndex, week) in weeksArray.enumerated() {
                            // Month labels
                            if let monthLabel = monthLabelForWeek(weekIndex) {
                                let x = offsetX + CGFloat(weekIndex) * (cellSize + cellSpacing) + cellSize / 2
                                let text = Text(monthLabel)
                                    .font(.system(size: 8))
                                    .foregroundColor(SonderColors.inkLight)
                                context.draw(text, at: CGPoint(x: x, y: 6))
                            }

                            // Draw cells back-to-front (top rows first for proper z-ordering)
                            for dayIndex in 0..<7 {
                                guard let date = week[dayIndex] else { continue }
                                let count = countForDate(date)

                                let x = offsetX + CGFloat(weekIndex) * (cellSize + cellSpacing)
                                let y = offsetY + CGFloat(dayIndex) * (cellSize + cellSpacing)
                                let barHeight = count == 0 ? 1.5 : CGFloat(min(count, 4)) / 4.0 * maxBarHeight

                                drawIsometricBar(
                                    context: &context,
                                    x: x, y: y - barHeight,
                                    width: cellSize, depth: cellSize,
                                    height: barHeight,
                                    count: count
                                )
                            }
                        }
                    }
                    .frame(
                        width: 20 + CGFloat(weeks.count) * (cellSize + cellSpacing) + 10,
                        height: 12 + maxBarHeight + 7 * (cellSize + cellSpacing) + 10
                    )
                    .id("canvas")
                }
                .onAppear {
                    proxy.scrollTo("canvas", anchor: .trailing)
                }
            }

            // Legend
            HStack(spacing: SonderSpacing.xs) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)

                ForEach([0, 1, 2, 4], id: \.self) { count in
                    let height: CGFloat = count == 0 ? 2 : CGFloat(min(count, 4)) / 4.0 * 10
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(colorForCount(count))
                            .frame(width: cellSize, height: max(cellSize, height + 2))
                    }
                    .frame(height: 14)
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

    // MARK: - Isometric Drawing

    private func drawIsometricBar(
        context: inout GraphicsContext,
        x: CGFloat, y: CGFloat,
        width: CGFloat, depth: CGFloat,
        height: CGFloat,
        count: Int
    ) {
        let baseColor = colorForCount(count)

        // Top face (lightest)
        let topPath = Path { p in
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + width, y: y))
            p.addLine(to: CGPoint(x: x + width, y: y + depth * 0.3))
            p.addLine(to: CGPoint(x: x, y: y + depth * 0.3))
            p.closeSubpath()
        }
        context.fill(topPath, with: .color(baseColor))

        // Front face (medium)
        let frontPath = Path { p in
            p.move(to: CGPoint(x: x, y: y + depth * 0.3))
            p.addLine(to: CGPoint(x: x + width, y: y + depth * 0.3))
            p.addLine(to: CGPoint(x: x + width, y: y + depth * 0.3 + height))
            p.addLine(to: CGPoint(x: x, y: y + depth * 0.3 + height))
            p.closeSubpath()
        }
        if count > 0 {
            context.fill(frontPath, with: .color(baseColor.opacity(0.7)))
        } else {
            context.fill(frontPath, with: .color(baseColor.opacity(0.5)))
        }

        // Right edge highlight (subtle)
        if count > 0 && height > 3 {
            let edgePath = Path { p in
                p.move(to: CGPoint(x: x + width - 1.5, y: y + depth * 0.3))
                p.addLine(to: CGPoint(x: x + width, y: y + depth * 0.3))
                p.addLine(to: CGPoint(x: x + width, y: y + depth * 0.3 + height))
                p.addLine(to: CGPoint(x: x + width - 1.5, y: y + depth * 0.3 + height))
                p.closeSubpath()
            }
            context.fill(edgePath, with: .color(baseColor.opacity(0.5)))
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

    private func colorForCount(_ count: Int) -> Color {
        switch count {
        case 0: return SonderColors.cream
        case 1: return SonderColors.terracotta.opacity(0.3)
        case 2...3: return SonderColors.terracotta.opacity(0.6)
        default: return SonderColors.terracotta
        }
    }
}
