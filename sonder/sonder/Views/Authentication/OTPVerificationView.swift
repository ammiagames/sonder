//
//  OTPVerificationView.swift
//  sonder
//

import SwiftUI

// MARK: - Private Helpers

/// Seeded xorshift64 RNG for deterministic decorative elements.
private struct OTPScreenRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x5DEECE66D : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Lightweight paper grain texture overlay.
private struct OTPGrainOverlay: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = OTPScreenRNG(seed: seed)

            for _ in 0..<320 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let w = CGFloat.random(in: 0.4...1.6, using: &rng)
                let h = CGFloat.random(in: 0.4...1.6, using: &rng)
                let isDark = Bool.random(using: &rng)
                let alpha = Double.random(in: 0.02...0.07, using: &rng)

                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)),
                    with: .color(isDark ? Color.black.opacity(alpha) : Color.white.opacity(alpha))
                )
            }
        }
        .blendMode(.softLight)
        .opacity(0.15)
    }
}

/// 6-digit OTP verification screen with auto-fill support.
struct OTPVerificationView: View {
    let phoneNumber: String

    @Environment(AuthenticationService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isVerifying = false
    @State private var hasError = false
    @State private var shakeOffset: CGFloat = 0
    @State private var resendCountdown = 0
    @State private var resendTimer: Timer?

    // Entrance animation state
    @State private var headerVisible = false
    @State private var subtitleVisible = false
    @State private var boxesVisible = false
    @State private var backVisible = false
    @State private var resendVisible = false
    @State private var cursorOpacity: CGFloat = 1.0
    @State private var lastFilledIndex: Int = -1
    @State private var errorFlash = false
    @State private var showSuccess = false
    @State private var digitPopIndices: Set<Int> = []

    private let codeLength = 6

    /// Masked phone for display: +1 (***) ***-1234
    private var maskedPhone: String {
        let digits = phoneNumber.filter(\.isNumber)
        let last4 = String(digits.suffix(4))
        return "(***) ***-\(last4)"
    }

    // MARK: - Decorative Background

    private var decorativeBackground: some View {
        ZStack {
            // Warm gradient base
            LinearGradient(
                colors: [
                    SonderColors.cream,
                    Color(red: 0.97, green: 0.94, blue: 0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Radial glow — ochre upper-right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SonderColors.ochre.opacity(0.12), .clear],
                        center: UnitPoint(x: 0.85, y: 0.15),
                        startRadius: 20,
                        endRadius: 300
                    )
                )

            // Radial glow — terracotta lower-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SonderColors.terracotta.opacity(0.08), .clear],
                        center: UnitPoint(x: 0.15, y: 0.80),
                        startRadius: 20,
                        endRadius: 280
                    )
                )

            // Paper grain (different seed from PhoneEntryView for visual variety)
            OTPGrainOverlay(seed: 0xB28C_4D1F)
        }
        .ignoresSafeArea()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: SonderSpacing.xl) {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SonderColors.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .opacity(backVisible ? 1 : 0)
                .offset(x: backVisible ? 0 : -12)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: backVisible)

                Spacer()
            }
            .padding(.horizontal, SonderSpacing.sm)

            Spacer()

            // Header
            VStack(spacing: SonderSpacing.sm) {
                Text("Enter the code")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)
                    .opacity(headerVisible ? 1 : 0)
                    .offset(y: headerVisible ? 0 : 14)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: headerVisible)

                Text("Sent to \(maskedPhone)")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .opacity(subtitleVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(0.15), value: subtitleVisible)
            }

            // Code boxes
            HStack(spacing: SonderSpacing.sm) {
                ForEach(0..<codeLength, id: \.self) { index in
                    let digit = index < code.count
                        ? String(code[code.index(code.startIndex, offsetBy: index)])
                        : ""
                    let isActive = index == code.count && !isVerifying
                    let hasDigit = !digit.isEmpty

                    ZStack {
                        // Digit text
                        Text(digit)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(SonderColors.inkDark)

                        // Pulsing cursor for active box
                        if isActive && !showSuccess {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(SonderColors.terracotta)
                                .frame(width: 2, height: 24)
                                .opacity(cursorOpacity)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(
                        showSuccess && hasDigit
                            ? SonderColors.sage.opacity(0.12)
                            : errorFlash
                                ? SonderColors.dustyRose.opacity(0.15)
                                : SonderColors.warmGray
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                            .stroke(
                                showSuccess && hasDigit ? SonderColors.sage :
                                    hasError ? SonderColors.dustyRose :
                                    isActive ? SonderColors.terracotta : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: isActive && !showSuccess ? SonderColors.terracotta.opacity(0.2) : .clear,
                        radius: 4
                    )
                    .scaleEffect(digitPopIndices.contains(index) ? 1.08 : 1.0)
                    // Staggered entrance
                    .opacity(boxesVisible ? 1 : 0)
                    .scaleEffect(boxesVisible ? 1 : 0.8)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.7)
                            .delay(0.20 + Double(index) * 0.06),
                        value: boxesVisible
                    )
                }
            }
            .offset(x: shakeOffset)

            // Success indicator
            if showSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SonderColors.sage)
                    Text("Verified")
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.sage)
                        .fontWeight(.medium)
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Hidden text field for keyboard + auto-fill
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .frame(width: 1, height: 1)
                .opacity(0.01) // nearly invisible but still focusable
                .onChange(of: code) { _, newValue in
                    // Only allow digits, cap at 6
                    let digits = newValue.filter(\.isNumber)
                    if digits.count != newValue.count || digits.count > codeLength {
                        code = String(digits.prefix(codeLength))
                        return
                    }
                    hasError = false

                    // Micro-animation for newly entered digit
                    let newIndex = digits.count - 1
                    if newIndex >= 0 && newIndex > lastFilledIndex {
                        SonderHaptics.impact(.light, intensity: 0.4)
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            digitPopIndices.insert(newIndex)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                                _ = digitPopIndices.remove(newIndex)
                            }
                        }
                        lastFilledIndex = newIndex
                    } else if digits.isEmpty {
                        lastFilledIndex = -1
                    }

                    // Auto-submit on 6th digit
                    if digits.count == codeLength {
                        verifyCode()
                    }
                }

            // Error text
            if hasError {
                Text("Invalid code. Please try again.")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.dustyRose)
                    .transition(.opacity)
            }

            // Resend
            Group {
                if resendCountdown > 0 {
                    Text("Resend code in \(resendCountdown)s")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)
                } else {
                    Button {
                        resendCode()
                    } label: {
                        Text("Resend code")
                            .font(SonderTypography.subheadline)
                            .foregroundStyle(SonderColors.terracotta)
                    }
                    .buttonStyle(.plain)
                    .disabled(isVerifying)
                }
            }
            .opacity(resendVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(0.60), value: resendVisible)

            if isVerifying && !showSuccess {
                ProgressView()
                    .tint(SonderColors.terracotta)
            }

            Spacer()
        }
        .background(decorativeBackground)
        .onAppear {
            startResendCountdown()

            // Staggered entrance — all flags set together, individual delays in .animation() modifiers
            backVisible = true
            headerVisible = true
            subtitleVisible = true
            boxesVisible = true
            resendVisible = true

            // Start cursor pulse after boxes have appeared
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                ) {
                    cursorOpacity = 0.2
                }
            }
        }
        .onDisappear {
            resendTimer?.invalidate()
        }
    }

    // MARK: - Actions

    private func verifyCode() {
        guard code.count == codeLength, !isVerifying else { return }
        isVerifying = true

        Task {
            do {
                try await authService.verifyPhoneOTP(phone: phoneNumber, code: code)
                SonderHaptics.notification(.success)

                // Success celebration
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showSuccess = true
                }

                // Brief delay for celebration, then dismiss
                try? await Task.sleep(for: .milliseconds(600))
                dismiss()
            } catch {
                hasError = true

                // Error flash on all boxes
                withAnimation(.easeIn(duration: 0.1)) {
                    errorFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        errorFlash = false
                    }
                }

                code = ""
                lastFilledIndex = -1
                SonderHaptics.notification(.error)
                shakeBoxes()
            }
            isVerifying = false
        }
    }

    private func resendCode() {
        Task {
            do {
                try await authService.sendPhoneOTP(phone: phoneNumber)
                startResendCountdown()
                SonderHaptics.notification(.success)
            } catch {
                // Silently fail — user can tap again
            }
        }
    }

    private func startResendCountdown() {
        resendCountdown = 60
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if resendCountdown > 0 {
                    resendCountdown -= 1
                } else {
                    resendTimer?.invalidate()
                }
            }
        }
    }

    private func shakeBoxes() {
        withAnimation(.default) {
            shakeOffset = 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.default) { shakeOffset = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.default) { shakeOffset = -4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring()) { shakeOffset = 0 }
        }
    }
}
