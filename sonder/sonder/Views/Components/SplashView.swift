//
//  SplashView.swift
//  sonder
//

import SwiftUI

/// Shown while the app initializes and the feed loads.
///
/// - First launch ever: full typewriter animation with pronunciation and definition.
/// - Subsequent launches: staggered letter entrance, then lifts away when content is ready.
struct SplashView: View {
    var isFirstLaunch: Bool = true

    // Returning users: letters start fully visible (no blank frame while task starts).
    // First-launch users: typewriter starts from 0.
    @State private var visibleCount: Int
    @State private var showCursor = true
    @State private var showSubtitle = false
    @State private var breatheScale: CGFloat = 1.0

    private let letters = Array("sonder")
    private var entranceDuration: Double { Double(letters.count) * 0.14 + 0.55 }

    init(isFirstLaunch: Bool = true) {
        self.isFirstLaunch = isFirstLaunch
        // Returning users: start with all letters visible so there's no blank cream frame
        // between the OS launch screen and the splash animation beginning.
        _visibleCount = State(initialValue: isFirstLaunch ? 0 : Array("sonder").count)
    }

    var body: some View {
        ZStack {
            SonderColors.cream.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    ForEach(0..<letters.count, id: \.self) { i in
                        Text(String(letters[i]))
                            .font(.system(size: 52, weight: .bold, design: .serif))
                            .foregroundStyle(SonderColors.inkDark)
                            // Both paths: opacity driven by visibleCount so entrance is always animated.
                            // First launch: letters drop in from above (offset -10 → 0).
                            // Returning: letters rise from below (offset +10 → 0).
                            .opacity(i < visibleCount ? 1 : 0)
                            .offset(y: i < visibleCount ? 0 : (isFirstLaunch ? -10 : 10))
                    }

                    // Cursor — only on first launch
                    if isFirstLaunch {
                        Rectangle()
                            .fill(SonderColors.terracotta)
                            .frame(width: 3, height: 46)
                            .opacity(showCursor ? 1 : 0)
                            .offset(y: 2)
                    }
                }

                Text("/\u{02C8}s\u{0252}n.d\u{0259}r/")
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .foregroundStyle(SonderColors.inkMuted)
                    .opacity(showSubtitle ? 1 : 0)

                Text("the realization that each passerby\nhas a life as vivid as your own")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(SonderColors.inkLight)
                    .multilineTextAlignment(.center)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 8)
            }
            .scaleEffect(breatheScale)
        }
        .task {
            if isFirstLaunch {
                // Typewriter entrance: letters drop in one by one
                for i in 0..<letters.count {
                    if i > 0 {
                        try? await Task.sleep(for: .milliseconds(140))
                        guard !Task.isCancelled else { return }
                    }
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        visibleCount = i + 1
                    }
                }
            }
            // Returning users: letters are already fully visible from init — nothing to animate.
        }
        .onAppear {
            if isFirstLaunch {
                // Blinking cursor
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    showCursor.toggle()
                }
                // Pronunciation + definition after typing
                withAnimation(.easeOut(duration: 0.4).delay(Double(letters.count) * 0.14 + 0.15)) {
                    showSubtitle = true
                }
                // Gentle breathing pulse while waiting for content
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(entranceDuration)) {
                    breatheScale = 1.02
                }
            } else {
                // Letters are already visible — subtitle can appear immediately
                withAnimation(.easeOut(duration: 0.35)) {
                    showSubtitle = true
                }
                // Breathing pulse starts right away
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(0.4)) {
                    breatheScale = 1.02
                }
            }
        }
    }
}

// MARK: - Splash Exit Transition

/// Removes the splash by floating it upward while dissolving —
/// like a card being lifted to reveal the app beneath.
private struct SplashLiftModifier: ViewModifier {
    /// 0 = fully visible (identity), 1 = fully gone (active)
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - progress)
            .offset(y: -progress * 48)
    }
}

extension AnyTransition {
    static var splashLift: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .modifier(
                active: SplashLiftModifier(progress: 1),
                identity: SplashLiftModifier(progress: 0)
            )
        )
    }
}

#Preview("First Launch") {
    SplashView(isFirstLaunch: true)
}

#Preview("Returning User") {
    SplashView(isFirstLaunch: false)
}
