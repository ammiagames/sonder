//
//  LogConfirmationView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "LogConfirmationView")

// MARK: - Animation Style

private enum ConfirmationStyle: CaseIterable {
    case passportStamp
    case pinDrop
    case checkmarkBurst
    case journalFlip

    var title: String {
        switch self {
        case .passportStamp: "Stamped!"
        case .pinDrop: "Pinned!"
        case .checkmarkBurst: "Logged!"
        case .journalFlip: "Noted!"
        }
    }
}

// MARK: - Checkmark Shape

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.73))
        path.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.28))
        return path
    }
}

// MARK: - Burst Particle

private struct BurstParticle {
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let colorIndex: Int

    static func generate(count: Int = 10) -> [BurstParticle] {
        (0..<count).map { i in
            BurstParticle(
                angle: Double(i) * (2 * .pi / Double(count)) + Double.random(in: -0.25...0.25),
                distance: CGFloat.random(in: 70...130),
                size: CGFloat.random(in: 4...9),
                colorIndex: i % 4
            )
        }
    }

    func color() -> Color {
        switch colorIndex {
        case 0: SonderColors.terracotta
        case 1: SonderColors.ochre
        case 2: SonderColors.sage
        default: SonderColors.dustyRose
        }
    }
}

// MARK: - LogConfirmationView

/// Screen 4: Success confirmation with auto-dismiss — randomly picks one of four animation styles
struct LogConfirmationView: View {
    let onDismiss: () -> Void
    var tripName: String? = nil
    var onAddCover: (() -> Void)? = nil
    var placeName: String? = nil
    var ratingEmoji: String? = nil

    // Shared state
    @State private var style: ConfirmationStyle = .checkmarkBurst
    @State private var showContent = false
    @State private var showNudge = false
    @State private var message = ""

    // Passport Stamp
    @State private var stampLanded = false
    @State private var inkRingScale: CGFloat = 0.5
    @State private var inkRingOpacity: Double = 0

    // Pin Drop
    @State private var pinDropped = false
    @State private var ripple1Progress: CGFloat = 0
    @State private var ripple2Progress: CGFloat = 0
    @State private var ripple3Progress: CGFloat = 0
    @State private var ripple1Started = false
    @State private var ripple2Started = false
    @State private var ripple3Started = false

    // Checkmark Burst
    @State private var circleTrim: CGFloat = 0
    @State private var checkTrim: CGFloat = 0
    @State private var particles: [BurstParticle] = []
    @State private var burstActive = false

    // Journal Flip
    @State private var cardFlipped = false
    @State private var autoDismissTask: Task<Void, Never>?

    private static let messages = [
        "Another one for the journal",
        "Memory saved",
        "Noted and logged",
        "Added to your story",
        "One more for the books",
    ]

    var body: some View {
        ZStack {
            SonderColors.cream.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.clear,
                    SonderColors.ochre.opacity(0.25),
                    SonderColors.terracotta.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: SonderSpacing.xl) {
                Spacer()

                // Hero animation area
                heroAnimation
                    .frame(height: 180)

                // Title + subtitle
                VStack(spacing: SonderSpacing.xs) {
                    Text(style.title)
                        .font(SonderTypography.largeTitle)
                        .foregroundStyle(SonderColors.inkDark)

                    Text(message)
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 12)

                // Cover photo nudge
                if let name = tripName, let addCover = onAddCover {
                    coverNudgeButton(tripName: name, action: addCover)
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            style = ConfirmationStyle.allCases.randomElement() ?? .checkmarkBurst
            message = Self.messages.randomElement() ?? Self.messages[0]
            particles = BurstParticle.generate()
            runAnimation()

            if tripName != nil {
                withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
                    showNudge = true
                }
            }

            let dismissDelay: UInt64 = tripName != nil ? 3500 : 2500
            autoDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(dismissDelay))
                guard !Task.isCancelled else { return }
                onDismiss()
            }
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }

    // MARK: - Hero Animation Router

    @ViewBuilder
    private var heroAnimation: some View {
        switch style {
        case .passportStamp: passportStampHero
        case .pinDrop: pinDropHero
        case .checkmarkBurst: checkmarkBurstHero
        case .journalFlip: journalFlipHero
        }
    }

    // MARK: - Passport Stamp

    private var passportStampHero: some View {
        ZStack {
            // Ink bleed ring
            Circle()
                .stroke(SonderColors.terracotta.opacity(0.3), lineWidth: 2)
                .frame(width: 140, height: 140)
                .scaleEffect(inkRingScale)
                .opacity(inkRingOpacity)

            // Stamp body
            ZStack {
                // Outer dashed border
                Circle()
                    .strokeBorder(SonderColors.terracotta, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    .frame(width: 120, height: 120)

                // Inner border
                Circle()
                    .strokeBorder(SonderColors.terracotta, lineWidth: 1.5)
                    .frame(width: 104, height: 104)

                VStack(spacing: 2) {
                    Text("LOGGED")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(SonderColors.terracotta)
                        .tracking(3)

                    Text(ratingEmoji ?? "📍")
                        .font(.system(size: 36))

                    if let name = placeName {
                        Text(String(name.prefix(14)).uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(SonderColors.terracotta)
                            .lineLimit(1)
                    }
                }
            }
            .rotationEffect(.degrees(stampLanded ? -6 : -14))
            .scaleEffect(stampLanded ? 1.0 : 1.8)
            .offset(y: stampLanded ? 0 : -50)
            .opacity(stampLanded ? 1 : 0)
        }
    }

    // MARK: - Pin Drop

    private var pinDropHero: some View {
        ZStack {
            // Ripples at ground level
            Group {
                Circle()
                    .stroke(SonderColors.terracotta, lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.5 + ripple1Progress * 3.0)
                    .opacity(ripple1Started ? 0.5 * (1 - ripple1Progress) : 0)

                Circle()
                    .stroke(SonderColors.terracotta, lineWidth: 1.5)
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.5 + ripple2Progress * 3.0)
                    .opacity(ripple2Started ? 0.4 * (1 - ripple2Progress) : 0)

                Circle()
                    .stroke(SonderColors.terracotta, lineWidth: 1)
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.5 + ripple3Progress * 3.0)
                    .opacity(ripple3Started ? 0.3 * (1 - ripple3Progress) : 0)
            }
            .offset(y: 30)

            // Shadow at ground
            Ellipse()
                .fill(SonderColors.inkDark.opacity(0.08))
                .frame(width: 24, height: 8)
                .offset(y: 34)
                .opacity(pinDropped ? 1 : 0)
                .scaleEffect(x: pinDropped ? 1.0 : 0.3)

            // The pin
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(SonderColors.terracotta)
                .offset(y: pinDropped ? 0 : -300)
        }
    }

    // MARK: - Checkmark Burst

    private var checkmarkBurstHero: some View {
        ZStack {
            // Burst particles
            ForEach(Array(particles.enumerated()), id: \.offset) { _, particle in
                Circle()
                    .fill(particle.color())
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: burstActive ? cos(particle.angle) * particle.distance : 0,
                        y: burstActive ? sin(particle.angle) * particle.distance : 0
                    )
                    .opacity(burstActive ? 0 : 1)
            }

            // Circle outline
            Circle()
                .trim(from: 0, to: circleTrim)
                .stroke(SonderColors.terracotta, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))

            // Checkmark
            CheckmarkShape()
                .trim(from: 0, to: checkTrim)
                .stroke(SonderColors.terracotta, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 60, height: 60)
        }
    }

    // MARK: - Journal Flip

    private var journalFlipHero: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(SonderColors.terracotta)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(ratingEmoji ?? "📍")
                    .font(.system(size: 28))

                Text(placeName ?? "New place")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                Text("Just logged")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()
        }
        .padding(SonderSpacing.md)
        .frame(width: 240, height: 100)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .shadow(color: SonderColors.inkDark.opacity(0.1), radius: 12, y: 4)
        .rotation3DEffect(.degrees(cardFlipped ? 0 : 90), axis: (1, 0, 0), perspective: 0.5)
        .opacity(cardFlipped ? 1 : 0)
    }

    // MARK: - Cover Nudge Button

    private func coverNudgeButton(tripName name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SonderColors.terracotta)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a cover photo")
                        .font(SonderTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(SonderColors.inkDark)
                    Text("for \"\(name)\"")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.warmGray.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .padding(.horizontal, SonderSpacing.xl)
        .opacity(showNudge ? 1 : 0)
        .offset(y: showNudge ? 0 : 8)
    }

    // MARK: - Animation Orchestration

    private func runAnimation() {
        // Text reveal (shared across all styles)
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            showContent = true
        }

        switch style {
        case .passportStamp: animateStamp()
        case .pinDrop: animatePinDrop()
        case .checkmarkBurst: animateCheckmark()
        case .journalFlip: animateJournalFlip()
        }
    }

    private func animateStamp() {
        // Stamp slams down
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            stampLanded = true
        }

        // Haptic timed with landing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            SonderHaptics.impact(.heavy)
        }

        // Ink ring expands and fades
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            inkRingOpacity = 0.5
            withAnimation(.easeOut(duration: 0.7)) {
                inkRingScale = 2.5
                inkRingOpacity = 0
            }
        }
    }

    private func animatePinDrop() {
        // Pin drops with bouncy spring
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
            pinDropped = true
        }

        // Haptic on landing
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            SonderHaptics.impact(.medium)
        }

        // Staggered ripples
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            ripple1Started = true
            withAnimation(.easeOut(duration: 0.8)) { ripple1Progress = 1 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(430))
            ripple2Started = true
            withAnimation(.easeOut(duration: 0.8)) { ripple2Progress = 1 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(580))
            ripple3Started = true
            withAnimation(.easeOut(duration: 0.8)) { ripple3Progress = 1 }
        }
    }

    private func animateCheckmark() {
        // Circle draws
        withAnimation(.easeInOut(duration: 0.5)) {
            circleTrim = 1.0
        }

        // Checkmark draws after circle
        withAnimation(.easeOut(duration: 0.35).delay(0.5)) {
            checkTrim = 1.0
        }

        // Burst + haptic after checkmark completes
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            SonderHaptics.notification(.success)
            withAnimation(.easeOut(duration: 0.5)) {
                burstActive = true
            }
        }
    }

    private func animateJournalFlip() {
        SonderHaptics.impact(.light)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            cardFlipped = true
        }
    }
}

// MARK: - Previews

#Preview("Passport Stamp") {
    LogConfirmationView(
        onDismiss: { logger.debug("Dismissed") },
        placeName: "Blue Bottle Coffee",
        ratingEmoji: "🔥"
    )
}

#Preview("With Nudge") {
    LogConfirmationView(
        onDismiss: { logger.debug("Dismissed") },
        tripName: "Tokyo 2026",
        onAddCover: { logger.debug("Add cover tapped") },
        placeName: "Tsukiji Market",
        ratingEmoji: "🤩"
    )
}
