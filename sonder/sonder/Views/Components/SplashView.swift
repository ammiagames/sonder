//
//  SplashView.swift
//  sonder
//

import SwiftUI

/// Shown while the app initializes and the feed loads.
///
/// - First launch ever: full typewriter animation with pronunciation and definition.
/// - Subsequent launches: "sonder" shown immediately, fades out as soon as content is ready.
struct SplashView: View {
    var isFirstLaunch: Bool = true

    @State private var visibleCount = 0
    @State private var showCursor = true
    @State private var showSubtitle = false
    @State private var breatheScale: CGFloat = 1.0

    private let letters = Array("sonder")
    private var entranceDuration: Double { Double(letters.count) * 0.14 + 0.55 }

    var body: some View {
        ZStack {
            SonderColors.cream.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    ForEach(0..<letters.count, id: \.self) { i in
                        Text(String(letters[i]))
                            .font(.system(size: 52, weight: .bold, design: .serif))
                            .foregroundStyle(SonderColors.inkDark)
                            .opacity(isFirstLaunch ? (i < visibleCount ? 1 : 0) : 1)
                            .offset(y: isFirstLaunch ? (i < visibleCount ? 0 : -8) : 0)
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

                if isFirstLaunch {
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
            }
            .scaleEffect(breatheScale)
        }
        .onAppear {
            guard isFirstLaunch else { return }

            // Type each letter
            for i in 0..<letters.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.14) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        visibleCount = i + 1
                    }
                }
            }

            // Blink cursor
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                showCursor.toggle()
            }

            // Show subtitle after typing finishes
            withAnimation(.easeOut(duration: 0.4).delay(Double(letters.count) * 0.14 + 0.15)) {
                showSubtitle = true
            }

            // Gentle breathing pulse while waiting for content to load
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(entranceDuration)) {
                breatheScale = 1.02
            }
        }
    }
}

#Preview("First Launch") {
    SplashView(isFirstLaunch: true)
}

#Preview("Returning User") {
    SplashView(isFirstLaunch: false)
}
