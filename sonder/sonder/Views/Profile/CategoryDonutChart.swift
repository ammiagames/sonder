//
//  CategoryDonutChart.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

struct CategoryDonutChart: View {
    let categories: [CategoryStat]
    let totalLogs: Int

    private let size: CGFloat = 180
    private let lineWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Categories")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: SonderSpacing.lg) {
                // Donut chart
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(SonderColors.inkLight.opacity(0.1), lineWidth: lineWidth)

                    // Category segments
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        let (start, end) = segmentAngles(for: index)
                        Circle()
                            .trim(from: start, to: end)
                            .stroke(category.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }

                    // Center label
                    VStack(spacing: 0) {
                        Text("\(totalLogs)")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundColor(SonderColors.inkDark)
                        Text("logs")
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }
                .frame(width: size, height: size)

                // Legend
                VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                    ForEach(categories) { category in
                        HStack(spacing: SonderSpacing.xs) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 8, height: 8)

                            Image(systemName: category.icon)
                                .font(.system(size: 11))
                                .foregroundColor(SonderColors.inkMuted)
                                .frame(width: 14)

                            Text(category.category)
                                .font(.system(size: 12))
                                .foregroundColor(SonderColors.inkDark)
                                .lineLimit(1)

                            Spacer()

                            Text("\(category.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(SonderColors.inkMuted)
                        }
                    }
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Helpers

    private func segmentAngles(for index: Int) -> (CGFloat, CGFloat) {
        let gap: CGFloat = 0.005 // Small gap between segments
        var start: CGFloat = 0
        for i in 0..<index {
            start += categories[i].percentage
        }
        let end = start + categories[index].percentage
        return (start + gap, max(start + gap, end - gap))
    }
}
