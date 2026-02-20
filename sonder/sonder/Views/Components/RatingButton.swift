//
//  RatingButton.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "RatingButton")

/// Large tappable rating button with emoji and label
struct RatingButton: View {
    let rating: Rating
    let isSelected: Bool
    let action: () -> Void

    private var emoji: String {
        rating.emoji
    }

    private var label: String {
        rating.displayName
    }

    private var subtitle: String {
        rating.subtitle
    }

    private var backgroundColor: Color {
        let color = SonderColors.pinColor(for: rating)
        return isSelected ? color.opacity(0.2) : SonderColors.warmGray
    }

    private var borderColor: Color {
        let color = SonderColors.pinColor(for: rating)
        return isSelected ? color : Color.clear
    }

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        }) {
            VStack(spacing: SonderSpacing.xs) {
                Text(emoji)
                    .font(.system(size: 48))

                Text(label)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                Text(subtitle)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.xl)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// Button style that provides a press-scale animation without competing gestures
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 16) {
        RatingButton(rating: .skip, isSelected: false) {
            logger.debug("Skip tapped")
        }
        RatingButton(rating: .okay, isSelected: true) {
            logger.debug("Okay tapped")
        }
        RatingButton(rating: .great, isSelected: false) {
            logger.debug("Great tapped")
        }
        RatingButton(rating: .mustSee, isSelected: false) {
            logger.debug("Must-See tapped")
        }
    }
    .padding()
}
