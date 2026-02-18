//
//  TripCoverPlaceholderView.swift
//  sonder
//
//  Created by Codex on 2/17/26.
//

import SwiftUI

/// Warm abstract placeholder for trip covers while images load or when missing.
/// Uses travel-inspired route doodles instead of a default photo glyph.
struct TripCoverPlaceholderView: View {
    let seedKey: String
    var title: String? = nil
    var caption: String? = nil

    private var seedBits: UInt64 {
        UInt64(bitPattern: Int64(seedKey.hashValue))
    }

    private func unit(_ salt: UInt64) -> CGFloat {
        let mixed = seedBits &+ salt &* 0x9E37_79B9_7F4A_7C15
        let value = mixed ^ (mixed >> 33)
        return CGFloat(value % 1000) / 1000
    }

    private var palette: (Color, Color, Color) {
        let palettes: [(Color, Color, Color)] = [
            (
                Color(red: 0.92, green: 0.84, blue: 0.76),
                Color(red: 0.84, green: 0.74, blue: 0.63),
                Color(red: 0.98, green: 0.93, blue: 0.86)
            ),
            (
                Color(red: 0.91, green: 0.80, blue: 0.72),
                Color(red: 0.80, green: 0.70, blue: 0.62),
                Color(red: 0.97, green: 0.89, blue: 0.82)
            ),
            (
                Color(red: 0.89, green: 0.83, blue: 0.74),
                Color(red: 0.78, green: 0.72, blue: 0.63),
                Color(red: 0.95, green: 0.90, blue: 0.82)
            ),
            (
                Color(red: 0.90, green: 0.78, blue: 0.70),
                Color(red: 0.79, green: 0.67, blue: 0.59),
                Color(red: 0.96, green: 0.87, blue: 0.79)
            )
        ]
        return palettes[Int(seedBits % UInt64(palettes.count))]
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let tones = palette

            ZStack {
                LinearGradient(
                    colors: [tones.0, tones.1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tones.2.opacity(0.85), .clear],
                            center: UnitPoint(x: 0.20 + unit(1) * 0.55, y: 0.18 + unit(2) * 0.52),
                            startRadius: 2,
                            endRadius: max(size.width, size.height) * (0.62 + unit(3) * 0.26)
                        )
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(0.10), .clear],
                            center: UnitPoint(x: 0.70 + unit(4) * 0.20, y: 0.74 + unit(5) * 0.16),
                            startRadius: 1,
                            endRadius: max(size.width, size.height) * (0.66 + unit(6) * 0.25)
                        )
                    )

                routeDoodle(size: size)

                if size.height > 72 {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title, !title.isEmpty, size.height > 92 {
                            Text(title)
                                .font(.system(size: min(20, max(12, size.height * 0.15)), weight: .semibold, design: .serif))
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                        }

                        if let caption, !caption.isEmpty {
                            Text(caption)
                                .font(.system(size: min(13, max(10, size.height * 0.10)), weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, min(16, max(8, size.width * 0.08)))
                    .padding(.bottom, min(14, max(8, size.height * 0.10)))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder
    private func routeDoodle(size: CGSize) -> some View {
        let start = CGPoint(
            x: size.width * (0.14 + unit(7) * 0.24),
            y: size.height * (0.22 + unit(8) * 0.30)
        )
        let mid = CGPoint(
            x: size.width * (0.48 + unit(9) * 0.14),
            y: size.height * (0.20 + unit(10) * 0.48)
        )
        let end = CGPoint(
            x: size.width * (0.66 + unit(11) * 0.20),
            y: size.height * (0.58 + unit(12) * 0.26)
        )
        let lineWidth = max(1, min(2.2, size.height * 0.014))

        Path { path in
            path.move(to: start)
            path.addQuadCurve(to: mid, control: CGPoint(x: size.width * (0.34 + unit(13) * 0.16), y: size.height * (0.02 + unit(14) * 0.26)))
            path.addQuadCurve(to: end, control: CGPoint(x: size.width * (0.58 + unit(15) * 0.16), y: size.height * (0.62 + unit(16) * 0.22)))
        }
        .stroke(
            Color.white.opacity(0.45),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [5, 5])
        )
        .overlay {
            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: lineWidth * 2.8, height: lineWidth * 2.8)
                .position(start)
        }
        .overlay {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: max(8, size.height * 0.09), weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
                .position(end)
        }
    }
}

