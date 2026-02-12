//
//  LogConfirmationView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Screen 4: Success confirmation with auto-dismiss
struct LogConfirmationView: View {
    let onDismiss: () -> Void

    @State private var showCheckmark = false
    @State private var checkmarkScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Success card
            VStack(spacing: SonderSpacing.lg) {
                // Animated checkmark
                ZStack {
                    Circle()
                        .fill(SonderColors.sage)
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(checkmarkScale)
                .opacity(showCheckmark ? 1 : 0)

                Text("Logged!")
                    .font(SonderTypography.title)
                    .foregroundColor(SonderColors.inkDark)
                    .opacity(showCheckmark ? 1 : 0)

                Text("Your place has been saved")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .padding(SonderSpacing.xxl)
            .background(SonderColors.cream)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusXl))
            .shadow(color: .black.opacity(0.15), radius: 20)
        }
        .onAppear {
            // Haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            // Animate in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showCheckmark = true
                checkmarkScale = 1.0
            }

            // Auto-dismiss after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onDismiss()
            }
        }
    }
}

#Preview {
    LogConfirmationView {
        print("Dismissed")
    }
}
