//
//  BulkImportProcessingView.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import SwiftUI

/// Loading/progress view shown during metadata extraction, clustering, and place resolution.
struct BulkImportProcessingView: View {
    let state: BulkImportState

    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: SonderSpacing.xl) {
            Spacer()

            // Animated icon
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.terracotta)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text(state.displayText)
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            // Progress bar
            if let progress = state.progress {
                VStack(spacing: SonderSpacing.xs) {
                    ProgressView(value: progress)
                        .tint(SonderColors.terracotta)
                        .frame(maxWidth: 240)
                    Text("\(Int(progress * 100))%")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SonderColors.cream)
    }

    private var iconName: String {
        switch state {
        case .extracting: return "location.magnifyingglass"
        case .clustering: return "square.grid.3x3"
        case .resolving: return "mappin.and.ellipse"
        default: return "arrow.triangle.2.circlepath"
        }
    }
}
