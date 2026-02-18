//
//  OnboardingLogStep.swift
//  sonder
//

import SwiftUI
import CoreLocation

/// Step 3: Prompt user to log their first place (skippable)
struct OnboardingLogStep: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var showSearchPlace = false
    @State private var didLogPlace = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SonderSpacing.xl) {
                // Illustration
                ZStack {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                        .fill(SonderColors.warmGray)
                        .frame(width: 120, height: 120)

                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 48))
                        .foregroundColor(SonderColors.terracotta)
                }

                // Header
                Text("Log your first place")
                    .font(SonderTypography.title)
                    .foregroundColor(SonderColors.inkDark)

                // Body
                Text("Your favorite coffee shop, a restaurant you always go back to, that one park...")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.lg)

                // Success state
                if didLogPlace {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(SonderColors.sage)
                        Text("Place logged!")
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.sage)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer()

            // CTAs
            VStack(spacing: SonderSpacing.md) {
                if didLogPlace {
                    Button("Continue", action: onContinue)
                        .buttonStyle(WarmButtonStyle(isPrimary: true))
                } else {
                    Button("Find a Place") {
                        showSearchPlace = true
                    }
                    .buttonStyle(WarmButtonStyle(isPrimary: true))

                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(SonderTypography.subheadline)
                            .foregroundColor(SonderColors.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, SonderSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, SonderSpacing.xxl)
        .background(SonderColors.cream)
        .fullScreenCover(isPresented: $showSearchPlace) {
            SearchPlaceView(onLogComplete: { _ in
                showSearchPlace = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    didLogPlace = true
                }
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)
            })
        }
    }
}
