//
//  OnboardingView.swift
//  sonder
//

import SwiftUI

/// 2-step onboarding container: Profile → Friends
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0

    /// Tracks whether to animate forward or backward
    @State private var isForward = true

    private let totalSteps = 2

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: back button + progress dots
            topBar

            // Step content
            ZStack {
                switch currentStep {
                case 0:
                    OnboardingProfileStep {
                        goForward()
                    }
                    .transition(slideTransition)

                case 1:
                    OnboardingFriendsStep {
                        finish()
                    }
                    .transition(slideTransition)

                default:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .background(SonderColors.cream)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Back button (hidden on step 0)
            if currentStep > 0 {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SonderColors.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }

            Spacer()

            // Progress dots
            HStack(spacing: SonderSpacing.xs) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? SonderColors.terracotta : SonderColors.warmGray)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }

            Spacer()

            // Balance spacer
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, SonderSpacing.sm)
    }

    // MARK: - Navigation

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading),
            removal: .move(edge: isForward ? .leading : .trailing)
        )
    }

    private func goForward() {
        guard currentStep < totalSteps - 1 else { return }
        isForward = true
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep += 1
        }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        isForward = false
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep -= 1
        }
    }

    private func finish() {
        onComplete()
    }
}
