//
//  OnboardingView.swift
//  sonder
//

import SwiftUI
import SwiftData

/// 4-step onboarding container: Welcome → Profile → Log → Friends
struct OnboardingView: View {
    let onComplete: (OnboardingResult) -> Void

    @State private var currentStep = 0
    @State private var didLogPlace = false
    @State private var didFollowSomeone = false

    /// Tracks whether to animate forward or backward
    @State private var isForward = true

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: back button + progress dots
            topBar

            // Step content
            ZStack {
                switch currentStep {
                case 0:
                    OnboardingWelcomeStep {
                        goForward()
                    }
                    .transition(slideTransition)

                case 1:
                    OnboardingProfileStep {
                        goForward()
                    }
                    .transition(slideTransition)

                case 2:
                    OnboardingLogStep(
                        onContinue: {
                            didLogPlace = true
                            goForward()
                        },
                        onSkip: {
                            goForward()
                        }
                    )
                    .transition(slideTransition)

                case 3:
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
                        .foregroundColor(SonderColors.inkMuted)
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
        let result = OnboardingResult(
            didLogPlace: didLogPlace,
            didFollowSomeone: didFollowSomeone
        )
        onComplete(result)
    }
}

/// Result of the onboarding flow — used to decide initial tab
struct OnboardingResult {
    let didLogPlace: Bool
    let didFollowSomeone: Bool
}
