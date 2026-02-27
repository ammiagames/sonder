//
//  PageCounterPill.swift
//  sonder
//

import SwiftUI

/// Frosted capsule showing "1 / 5" page position, used in photo carousels.
struct PageCounterPill: View {
    let current: Int
    let total: Int
    var style: Style = .compact

    enum Style {
        /// Small pill for card overlays (feed items, log detail)
        case compact
        /// Larger pill for fullscreen photo viewers
        case fullscreen
    }

    var body: some View {
        Text("\(current + 1) / \(total)")
            .font(.system(
                size: style == .compact ? 11 : 14,
                weight: style == .compact ? .semibold : .medium,
                design: style == .compact ? .rounded : .default
            ))
            .foregroundStyle(.white)
            .padding(.horizontal, style == .compact ? 8 : 14)
            .padding(.vertical, style == .compact ? 4 : 6)
            .background(Color.black.opacity(style == .compact ? 0.35 : 0.5))
            .clipShape(Capsule())
    }
}
