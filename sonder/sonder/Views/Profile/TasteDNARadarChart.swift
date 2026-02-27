//
//  TasteDNARadarChart.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

struct TasteDNARadarChart: View {
    let tasteDNA: TasteDNA

    private let size: CGFloat = 220
    private let gridLevels = [0.25, 0.5, 0.75, 1.0]

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Taste DNA")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ZStack {
                // Grid rings
                ForEach(gridLevels, id: \.self) { level in
                    radarPolygon(values: Array(repeating: level, count: 6))
                        .stroke(SonderColors.inkLight.opacity(0.2), lineWidth: 1)
                }

                // Axis lines
                ForEach(0..<6, id: \.self) { i in
                    let angle = angleFor(index: i)
                    let end = pointOnCircle(angle: angle, radius: size / 2 - 24)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: end)
                    }
                    .stroke(SonderColors.inkLight.opacity(0.15), lineWidth: 0.5)
                }

                // Data polygon
                let values = tasteDNA.axes.map { $0.value }
                radarPolygon(values: values)
                    .fill(SonderColors.terracotta.opacity(0.2))
                radarPolygon(values: values)
                    .stroke(SonderColors.terracotta.opacity(0.8), lineWidth: 2)

                // Data points
                ForEach(0..<6, id: \.self) { i in
                    let value = tasteDNA.axes[i].value
                    let angle = angleFor(index: i)
                    let point = pointOnCircle(angle: angle, radius: (size / 2 - 24) * CGFloat(value))
                    Circle()
                        .fill(SonderColors.terracotta)
                        .frame(width: 6, height: 6)
                        .position(point)
                }

                // Axis labels with icons
                ForEach(0..<6, id: \.self) { i in
                    let axis = tasteDNA.axes[i]
                    let angle = angleFor(index: i)
                    let labelPoint = pointOnCircle(angle: angle, radius: size / 2 - 4)

                    VStack(spacing: 1) {
                        Image(systemName: axis.icon)
                            .font(.system(size: 10))
                        Text(axis.label)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                    .position(labelPoint)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
        }
        .profileSectionCard(tint: SonderColors.terracotta, isFullBleed: true)
    }

    // MARK: - Geometry Helpers

    private var center: CGPoint {
        CGPoint(x: size / 2, y: size / 2)
    }

    private func angleFor(index: Int) -> CGFloat {
        // Start from top (-90 degrees), go clockwise
        let slice: CGFloat = 2 * .pi / 6
        return -(.pi / 2) + CGFloat(index) * slice
    }

    private func pointOnCircle(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + radius * CoreGraphics.cos(angle),
            y: center.y + radius * CoreGraphics.sin(angle)
        )
    }

    private func radarPolygon(values: [Double]) -> Path {
        let maxRadius: CGFloat = size / 2 - 24

        return Path { path in
            for (i, value) in values.enumerated() {
                let angle = angleFor(index: i)
                let point = pointOnCircle(angle: angle, radius: maxRadius * CGFloat(value))
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }
}

// MARK: - Comparison Taste DNA Radar Chart

struct ComparisonTasteDNARadarChart: View {
    let theirDNA: TasteDNA
    let myDNA: TasteDNA

    private let size: CGFloat = 220
    private let gridLevels = [0.25, 0.5, 0.75, 1.0]

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Taste DNA")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ZStack {
                // Grid rings
                ForEach(gridLevels, id: \.self) { level in
                    radarPolygon(values: Array(repeating: level, count: 6))
                        .stroke(SonderColors.inkLight.opacity(0.2), lineWidth: 1)
                }

                // Axis lines
                ForEach(0..<6, id: \.self) { i in
                    let angle = angleFor(index: i)
                    let end = pointOnCircle(angle: angle, radius: size / 2 - 24)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: end)
                    }
                    .stroke(SonderColors.inkLight.opacity(0.15), lineWidth: 0.5)
                }

                // "My" polygon — ghost (behind)
                let myValues = myDNA.axes.map { $0.value }
                radarPolygon(values: myValues)
                    .fill(SonderColors.warmBlue.opacity(0.08))
                radarPolygon(values: myValues)
                    .stroke(SonderColors.warmBlue.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                // "Their" polygon — solid (on top)
                let theirValues = theirDNA.axes.map { $0.value }
                radarPolygon(values: theirValues)
                    .fill(SonderColors.terracotta.opacity(0.2))
                radarPolygon(values: theirValues)
                    .stroke(SonderColors.terracotta.opacity(0.8), lineWidth: 2)

                // Data points — theirs
                ForEach(0..<6, id: \.self) { i in
                    let value = theirDNA.axes[i].value
                    let angle = angleFor(index: i)
                    let point = pointOnCircle(angle: angle, radius: (size / 2 - 24) * CGFloat(value))
                    Circle()
                        .fill(SonderColors.terracotta)
                        .frame(width: 6, height: 6)
                        .position(point)
                }

                // Axis labels with icons
                ForEach(0..<6, id: \.self) { i in
                    let axis = theirDNA.axes[i]
                    let angle = angleFor(index: i)
                    let labelPoint = pointOnCircle(angle: angle, radius: size / 2 - 4)

                    VStack(spacing: 1) {
                        Image(systemName: axis.icon)
                            .font(.system(size: 10))
                        Text(axis.label)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                    .position(labelPoint)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)

            // Legend
            HStack(spacing: SonderSpacing.lg) {
                Spacer()
                HStack(spacing: SonderSpacing.xxs) {
                    Circle()
                        .fill(SonderColors.warmBlue.opacity(0.35))
                        .frame(width: 8, height: 8)
                    Text("You")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SonderColors.inkMuted)
                }
                HStack(spacing: SonderSpacing.xxs) {
                    Circle()
                        .fill(SonderColors.terracotta.opacity(0.8))
                        .frame(width: 8, height: 8)
                    Text("Them")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SonderColors.inkMuted)
                }
                Spacer()
            }
        }
        .profileSectionCard(tint: SonderColors.terracotta, isFullBleed: true)
    }

    // MARK: - Geometry Helpers

    private var center: CGPoint {
        CGPoint(x: size / 2, y: size / 2)
    }

    private func angleFor(index: Int) -> CGFloat {
        let slice: CGFloat = 2 * .pi / 6
        return -(.pi / 2) + CGFloat(index) * slice
    }

    private func pointOnCircle(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + radius * CoreGraphics.cos(angle),
            y: center.y + radius * CoreGraphics.sin(angle)
        )
    }

    private func radarPolygon(values: [Double]) -> Path {
        let maxRadius: CGFloat = size / 2 - 24

        return Path { path in
            for (i, value) in values.enumerated() {
                let angle = angleFor(index: i)
                let point = pointOnCircle(angle: angle, radius: maxRadius * CGFloat(value))
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }
}
