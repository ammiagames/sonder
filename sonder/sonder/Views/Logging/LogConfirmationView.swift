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
    var tripName: String? = nil
    var onAddCover: (() -> Void)? = nil

    @State private var showContent = false
    @State private var contentScale: CGFloat = 0.6
    @State private var showParticles = false
    @State private var showNudge = false

    private let messages = [
        "Another one for the journal",
        "Memory saved",
        "Noted and logged",
        "Added to your story",
        "One more for the books",
    ]

    private var randomMessage: String {
        messages[Int.random(in: 0..<messages.count)]
    }

    var body: some View {
        ZStack {
            // Warm gradient background
            LinearGradient(
                colors: [
                    SonderColors.cream,
                    SonderColors.ochre.opacity(0.25),
                    SonderColors.terracotta.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Floating accent circles
            floatingAccents

            // Main content
            VStack(spacing: SonderSpacing.xl) {
                // Animated pin icon
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(SonderColors.terracotta.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(showContent ? 1.0 : 0.3)

                    Circle()
                        .fill(SonderColors.terracotta.opacity(0.15))
                        .frame(width: 90, height: 90)

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(SonderColors.terracotta)
                }
                .scaleEffect(contentScale)
                .opacity(showContent ? 1 : 0)

                VStack(spacing: SonderSpacing.xs) {
                    Text("Logged!")
                        .font(SonderTypography.largeTitle)
                        .foregroundColor(SonderColors.inkDark)

                    Text(randomMessage)
                        .font(SonderTypography.subheadline)
                        .foregroundColor(SonderColors.inkMuted)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 12)

                // Cover photo nudge
                if let name = tripName, let addCover = onAddCover {
                    Button {
                        addCover()
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16))
                                .foregroundColor(SonderColors.terracotta)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a cover photo")
                                    .font(SonderTypography.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(SonderColors.inkDark)
                                Text("for \"\(name)\"")
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.inkMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(SonderColors.inkLight)
                        }
                        .padding(SonderSpacing.sm)
                        .background(SonderColors.warmGray.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
                    .padding(.horizontal, SonderSpacing.xl)
                    .opacity(showNudge ? 1 : 0)
                    .offset(y: showNudge ? 0 : 8)
                }
            }
        }
        .onAppear {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                showContent = true
                contentScale = 1.0
            }

            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                showParticles = true
            }

            // Show nudge with a slight delay
            if tripName != nil {
                withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                    showNudge = true
                }
            }

            // Extend auto-dismiss when nudge is shown
            let dismissDelay: Double = tripName != nil ? 3.0 : 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
                onDismiss()
            }
        }
    }

    // MARK: - Floating Accents

    private var floatingAccents: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Scattered warm circles that fade in
            Group {
                Circle()
                    .fill(SonderColors.ochre.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .position(x: w * 0.15, y: h * 0.25)

                Circle()
                    .fill(SonderColors.sage.opacity(0.2))
                    .frame(width: 16, height: 16)
                    .position(x: w * 0.82, y: h * 0.2)

                Circle()
                    .fill(SonderColors.terracotta.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .position(x: w * 0.88, y: h * 0.45)

                Circle()
                    .fill(SonderColors.dustyRose.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .position(x: w * 0.12, y: h * 0.65)

                Circle()
                    .fill(SonderColors.ochre.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .position(x: w * 0.75, y: h * 0.72)

                Circle()
                    .fill(SonderColors.sage.opacity(0.15))
                    .frame(width: 14, height: 14)
                    .position(x: w * 0.35, y: h * 0.8)
            }
            .scaleEffect(showParticles ? 1.0 : 0.0)
            .opacity(showParticles ? 1 : 0)
        }
    }
}

#Preview("Basic") {
    LogConfirmationView {
        print("Dismissed")
    }
}

#Preview("With Nudge") {
    LogConfirmationView(
        onDismiss: { print("Dismissed") },
        tripName: "Tokyo 2026",
        onAddCover: { print("Add cover tapped") }
    )
}
