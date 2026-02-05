//
//  RatingButton.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Large tappable rating button with emoji and label
struct RatingButton: View {
    let rating: Rating
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    private var emoji: String {
        switch rating {
        case .skip:
            return "👎"
        case .solid:
            return "👍"
        case .mustSee:
            return "🔥"
        }
    }

    private var label: String {
        switch rating {
        case .skip:
            return "Skip"
        case .solid:
            return "Solid"
        case .mustSee:
            return "Must-See"
        }
    }

    private var subtitle: String {
        switch rating {
        case .skip:
            return "Wouldn't recommend"
        case .solid:
            return "Good, would go again"
        case .mustSee:
            return "Exceptional, go out of your way"
        }
    }

    private var backgroundColor: Color {
        switch rating {
        case .skip:
            return isSelected ? Color.red.opacity(0.2) : Color(.systemGray6)
        case .solid:
            return isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6)
        case .mustSee:
            return isSelected ? Color.orange.opacity(0.2) : Color(.systemGray6)
        }
    }

    private var borderColor: Color {
        switch rating {
        case .skip:
            return isSelected ? Color.red : Color.clear
        case .solid:
            return isSelected ? Color.blue : Color.clear
        case .mustSee:
            return isSelected ? Color.orange : Color.clear
        }
    }

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        }) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 48))

                Text(label)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        RatingButton(rating: .skip, isSelected: false) {
            print("Skip tapped")
        }
        RatingButton(rating: .solid, isSelected: true) {
            print("Solid tapped")
        }
        RatingButton(rating: .mustSee, isSelected: false) {
            print("Must-See tapped")
        }
    }
    .padding()
}
