//
//  HeatmapRadialView.swift
//  sonder
//
//  Variation 6: Radial / Ring Calendar
//  Concentric rings where each ring is a month.
//  Each segment is a day — activity determines brightness.
//  Inner = oldest month, outer = most recent.
//

import SwiftUI

struct HeatmapRadialView: View {
    let data: CalendarHeatmapData

    private let ringWidth: CGFloat = 12
    private let ringSpacing: CGFloat = 3
    private let innerRadius: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Logging activity")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            let months = monthData
            let totalRings = CGFloat(months.count)
            let outerRadius = innerRadius + totalRings * (ringWidth + ringSpacing)
            let canvasSize = (outerRadius + 20) * 2

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                for (monthIndex, month) in months.enumerated() {
                    let radius = innerRadius + CGFloat(monthIndex) * (ringWidth + ringSpacing)
                    let daysInMonth = month.days.count
                    guard daysInMonth > 0 else { continue }

                    let segmentAngle = (2 * .pi) / CGFloat(daysInMonth)
                    let gapAngle: CGFloat = 0.02 // small gap between segments

                    for (dayIndex, day) in month.days.enumerated() {
                        let startAngle = CGFloat(dayIndex) * segmentAngle - .pi / 2
                        let endAngle = startAngle + segmentAngle - gapAngle

                        let path = Path { p in
                            p.addArc(
                                center: center,
                                radius: radius + ringWidth / 2,
                                startAngle: .radians(startAngle),
                                endAngle: .radians(endAngle),
                                clockwise: false
                            )
                        }

                        let color = colorForCount(day.count)
                        context.stroke(
                            path,
                            with: .color(color),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                    }

                    // Month label
                    let labelAngle: CGFloat = -.pi / 2 - 0.15 // slightly offset from 12 o'clock
                    let labelRadius = radius + ringWidth / 2
                    let labelX = center.x + cos(labelAngle) * (labelRadius + ringWidth / 2 + 4)
                    let labelY = center.y + sin(labelAngle) * (labelRadius + ringWidth / 2 + 4)

                    let text = Text(month.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(SonderColors.inkLight)
                    context.draw(text, at: CGPoint(x: labelX, y: labelY))
                }

                // Center label
                let totalLogs = data.entries.reduce(0) { $0 + $1.count }
                let centerText = Text("\(totalLogs)")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                context.draw(centerText, at: center)

                let subtitle = Text("logs")
                    .font(.system(size: 10))
                    .foregroundColor(SonderColors.inkMuted)
                context.draw(subtitle, at: CGPoint(x: center.x, y: center.y + 14))
            }
            .frame(width: canvasSize, height: canvasSize)
            .frame(maxWidth: .infinity)

            // Legend
            HStack(spacing: SonderSpacing.xs) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)

                ForEach([0, 1, 2, 4], id: \.self) { count in
                    Circle()
                        .fill(colorForCount(count))
                        .frame(width: 8, height: 8)
                }

                Text("More")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)

                Spacer()

                Text("Inner = oldest")
                    .font(.system(size: 9))
                    .foregroundColor(SonderColors.inkLight)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Month Data

    private struct MonthDayData {
        let date: Date
        let count: Int
    }

    private struct MonthData {
        let label: String
        let days: [MonthDayData]
    }

    private var monthData: [MonthData] {
        let calendar = Calendar.current
        let countsByDate = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.date, $0.count) })

        var months: [MonthData] = []
        var current = data.startDate

        while current <= data.endDate {
            let month = calendar.component(.month, from: current)
            let year = calendar.component(.year, from: current)
            let range = calendar.range(of: .day, in: .month, for: current)!

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            let label = formatter.string(from: current)

            var days: [MonthDayData] = []
            for day in range {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                if let date = calendar.date(from: components) {
                    let dayStart = calendar.startOfDay(for: date)
                    if dayStart >= data.startDate && dayStart <= data.endDate {
                        let count = countsByDate[dayStart] ?? 0
                        days.append(MonthDayData(date: dayStart, count: count))
                    }
                }
            }

            if !days.isEmpty {
                months.append(MonthData(label: label, days: days))
            }

            // Move to next month
            current = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)!
        }

        return months
    }

    private func colorForCount(_ count: Int) -> Color {
        switch count {
        case 0: return SonderColors.cream.opacity(0.5)
        case 1: return SonderColors.terracotta.opacity(0.3)
        case 2...3: return SonderColors.terracotta.opacity(0.6)
        default: return SonderColors.terracotta
        }
    }
}
