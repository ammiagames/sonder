//
//  HeatmapInteractiveView.swift
//  sonder
//
//  Variation 5: Interactive + Animated
//  Cells wave-animate in on appear. Today pulses.
//  Tapping a cell shows a tooltip with details.
//

import SwiftUI

struct HeatmapInteractiveView: View {
    let data: CalendarHeatmapData

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 2
    private let dayLabels = ["", "M", "", "W", "", "F", ""]

    @State private var appeared = false
    @State private var selectedDate: Date?
    @State private var todayPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Logging activity")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            // Selected date tooltip
            if let selected = selectedDate {
                let count = countForDate(selected)
                HStack(spacing: SonderSpacing.xs) {
                    Circle()
                        .fill(colorForCount(count))
                        .frame(width: 8, height: 8)

                    Text(selected.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)

                    Text(count == 0 ? "No logs" : "\(count) place\(count == 1 ? "" : "s") logged")
                        .font(.system(size: 12))
                        .foregroundColor(SonderColors.inkMuted)

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedDate = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }
                .padding(.horizontal, SonderSpacing.sm)
                .padding(.vertical, SonderSpacing.xxs + 2)
                .background(SonderColors.cream)
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

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
                                            let isToday = Calendar.current.isDateInToday(date)
                                            let isSelected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false

                                            ZStack {
                                                // Pulse ring for today
                                                if isToday {
                                                    Circle()
                                                        .stroke(SonderColors.terracotta.opacity(todayPulse ? 0.4 : 0.1), lineWidth: 1.5)
                                                        .frame(width: cellSize + 3, height: cellSize + 3)
                                                }

                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(colorForCount(count))
                                                    .frame(width: cellSize, height: cellSize)
                                                    .scaleEffect(appeared ? 1.0 : 0.0)
                                                    .animation(
                                                        .spring(response: 0.4, dampingFraction: 0.6)
                                                            .delay(Double(weekIndex) * 0.012 + Double(dayIndex) * 0.008),
                                                        value: appeared
                                                    )

                                                // Selection ring
                                                if isSelected {
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .stroke(SonderColors.terracotta, lineWidth: 1.5)
                                                        .frame(width: cellSize + 2, height: cellSize + 2)
                                                }
                                            }
                                            .onTapGesture {
                                                withAnimation(.easeOut(duration: 0.15)) {
                                                    if selectedDate.map({ Calendar.current.isDate($0, inSameDayAs: date) }) == true {
                                                        selectedDate = nil
                                                    } else {
                                                        selectedDate = date
                                                    }
                                                }
                                            }
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
                .onAppear {
                    if !weeks.isEmpty {
                        proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appeared = true
                    }
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        todayPulse = true
                    }
                }
            }

            // Legend
            HStack(spacing: SonderSpacing.xs) {
                Text("Tap a day")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(SonderColors.terracotta)

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
