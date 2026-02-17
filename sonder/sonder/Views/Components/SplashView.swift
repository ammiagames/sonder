//
//  SplashView.swift
//  sonder
//

import SwiftUI

/// Shown briefly while restoring the user session on launch.
/// Typewriter animation that reveals the app name letter by letter.
struct SplashView: View {
    @State private var visibleCount = 0
    @State private var showCursor = true
    @State private var showSubtitle = false

    private let letters = Array("sonder")

    var body: some View {
        ZStack {
            SonderColors.cream.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    ForEach(0..<letters.count, id: \.self) { i in
                        Text(String(letters[i]))
                            .font(.system(size: 52, weight: .bold, design: .serif))
                            .foregroundColor(SonderColors.inkDark)
                            .opacity(i < visibleCount ? 1 : 0)
                            .offset(y: i < visibleCount ? 0 : -8)
                    }

                    // Cursor
                    Rectangle()
                        .fill(SonderColors.terracotta)
                        .frame(width: 3, height: 46)
                        .opacity(showCursor ? 1 : 0)
                        .offset(y: 2)
                }

                Text("/\u{02C8}s\u{0252}n.d\u{0259}r/")
                    .font(.system(size: 15, design: .serif))
                    .italic()
                    .foregroundColor(SonderColors.inkMuted)
                    .opacity(showSubtitle ? 1 : 0)

                Text("the realization that each passerby\nhas a life as vivid as your own")
                    .font(.system(size: 13, design: .serif))
                    .foregroundColor(SonderColors.inkLight)
                    .multilineTextAlignment(.center)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 8)
            }
        }
        .onAppear {
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

            // Show subtitle sooner after typing finishes
            withAnimation(.easeOut(duration: 0.4).delay(Double(letters.count) * 0.14 + 0.15)) {
                showSubtitle = true
            }
        }
    }
}

#Preview {
    SplashView()
}
