//
//  OnboardingWelcomeStep.swift
//  sonder
//

import SwiftUI

/// Step 1: Brand welcome moment
struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @State private var showTitle = false
    @State private var showTagline = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SonderSpacing.lg) {
                // Brand title
                Text("sonder")
                    .font(SonderTypography.largeTitle)
                    .foregroundColor(SonderColors.inkDark)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 10)

                // Terracotta accent dot
                Circle()
                    .fill(SonderColors.terracotta)
                    .frame(width: 6, height: 6)
                    .opacity(showTitle ? 1 : 0)

                // Tagline
                Text("Your places. Your people. Your story.")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline ? 0 : 8)
            }

            Spacer()

            // CTA
            Button("Get Started", action: onContinue)
                .buttonStyle(WarmButtonStyle(isPrimary: true))
                .opacity(showButton ? 1 : 0)
                .padding(.bottom, SonderSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, SonderSpacing.xxl)
        .background(SonderColors.cream)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                showTitle = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                showTagline = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
                showButton = true
            }
        }
    }
}
