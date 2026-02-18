//
//  ProfileInsightsSection.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

struct ProfileInsightsSection: View {
    let stats: ProfileStats

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Insights")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            // Streak counter
            if stats.streak.longestStreak > 0 {
                streakRow
            }

            // Day of week pattern
            if stats.totalLogs >= 3 {
                dayOfWeekRow
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Streak Row

    private var streakRow: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20))
                .foregroundStyle(SonderColors.terracotta)
                .frame(width: 36, height: 36)
                .background(SonderColors.terracotta.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            VStack(alignment: .leading, spacing: 2) {
                if stats.streak.currentStreak > 0 {
                    Text("\(stats.streak.currentStreak)-day streak")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SonderColors.inkDark)
                } else {
                    Text("No active streak")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SonderColors.inkDark)
                }

                Text("Longest: \(stats.streak.longestStreak) days")
                    .font(.system(size: 12))
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()
        }
    }

    // MARK: - Day of Week Row

    private var dayOfWeekRow: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(SonderColors.warmBlue)
                .frame(width: 36, height: 36)
                .background(SonderColors.warmBlue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            VStack(alignment: .leading, spacing: 2) {
                if stats.dayOfWeek.isWeekdayExplorer {
                    Text("You're a weekday explorer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SonderColors.inkDark)
                } else {
                    Text("You explore most on **\(stats.dayOfWeek.peakDay)**")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SonderColors.inkDark)
                }

                Text("\(Int(stats.dayOfWeek.peakPercentage * 100))% of your logs")
                    .font(.system(size: 12))
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()
        }
    }
}
