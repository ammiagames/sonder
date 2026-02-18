//
//  TripExportEffects.swift
//  sonder
//

import SwiftUI

// MARK: - Seeded RNG (deterministic effects across renders)

struct ExportSeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Film Grain Overlay

struct FilmGrainOverlay: View {
    var opacity: Double = 0.035
    var seed: Int = 42

    var body: some View {
        Canvas { context, size in
            var rng = ExportSeededRNG(seed: UInt64(bitPattern: Int64(seed)))
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let val = Double.random(in: 0...1, using: &rng)
                    if val > 0.6 {
                        let alpha = (val - 0.6) * 2.5 * opacity
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(.white.opacity(alpha))
                        )
                    } else if val < 0.4 {
                        let alpha = (0.4 - val) * 2.5 * opacity
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(.black.opacity(alpha))
                        )
                    }
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Paper Texture Overlay

struct PaperTextureOverlay: View {
    var warmth: Double = 0.03
    var seed: Int = 99

    var body: some View {
        Canvas { context, size in
            var rng = ExportSeededRNG(seed: UInt64(bitPattern: Int64(seed)))
            let step: CGFloat = 8
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let variation = Double.random(in: -warmth...warmth, using: &rng)
                    if variation > 0 {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(Color(red: 0.92, green: 0.87, blue: 0.78).opacity(variation * 6))
                        )
                    } else {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: step, height: step)),
                            with: .color(Color.black.opacity(abs(variation) * 2))
                        )
                    }
                    x += step
                }
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}
