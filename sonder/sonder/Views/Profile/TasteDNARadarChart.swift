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
                .foregroundColor(SonderColors.inkMuted)
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
                    .foregroundColor(SonderColors.inkMuted)
                    .position(labelPoint)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
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
