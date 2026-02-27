//
//  PhoneEntryView.swift
//  sonder
//

import SwiftUI
import AuthenticationServices

// MARK: - Private Helpers

/// Seeded xorshift64 RNG for deterministic decorative elements.
private struct AuthScreenRNG: RandomNumberGenerator {
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
private struct AuthGrainOverlay: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = AuthScreenRNG(seed: seed)

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

/// Primary authentication screen — phone number entry with OTP flow.
/// "Already have an account?" link reveals Apple/Google sign-in as a secondary option.
struct PhoneEntryView: View {
    @Environment(AuthenticationService.self) private var authService

    @State private var phoneDigits = ""  // raw digits only (no formatting)
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showOTPView = false
    @State private var showSecondarySignIn = false

    // Entrance animation state
    @State private var wordmarkVisible = false
    @State private var taglineVisible = false
    @State private var inputVisible = false
    @State private var linkVisible = false
    @State private var breatheScale: CGFloat = 1.0
    @State private var buttonPop = false
    @FocusState private var isPhoneFieldFocused: Bool

    private let sonderLetters = ["s", "o", "n", "d", "e", "r"]

    /// Formatted E.164 phone string for OTP
    private var fullPhoneNumber: String {
        "+1\(phoneDigits)"
    }

    /// Formatted display string: (xxx) xxx-xxxx
    private var formattedPhone: String {
        let d = phoneDigits
        switch d.count {
        case 0: return ""
        case 1...3: return "(\(d)"
        case 4...6:
            let area = d.prefix(3)
            let mid = d.dropFirst(3)
            return "(\(area)) \(mid)"
        default:
            let area = d.prefix(3)
            let mid = d.dropFirst(3).prefix(3)
            let last = d.dropFirst(6).prefix(4)
            return "(\(area)) \(mid)-\(last)"
        }
    }

    private var isValid: Bool { phoneDigits.count == 10 }

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

            // Route doodles
            GeometryReader { geo in
                authRouteDoodles(size: geo.size)
            }

            // Paper grain
            AuthGrainOverlay(seed: 0xA17B_5C3E)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func authRouteDoodles(size: CGSize) -> some View {
        let lineWidth: CGFloat = 1.4
        let dotSize: CGFloat = 4.8
        let doodleColor = SonderColors.inkLight.opacity(0.12)

        ZStack {
            // Route 1 — upper area curve
            Path { path in
                let start = CGPoint(x: size.width * 0.12, y: size.height * 0.18)
                let mid = CGPoint(x: size.width * 0.38, y: size.height * 0.12)
                let end = CGPoint(x: size.width * 0.55, y: size.height * 0.22)
                path.move(to: start)
                path.addQuadCurve(to: mid, control: CGPoint(x: size.width * 0.24, y: size.height * 0.06))
                path.addQuadCurve(to: end, control: CGPoint(x: size.width * 0.48, y: size.height * 0.08))
            }
            .stroke(doodleColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [5, 5]))

            // Waypoint dots — route 1
            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.12, y: size.height * 0.18)
            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.38, y: size.height * 0.12)
            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.55, y: size.height * 0.22)

            // Route 2 — lower-right
            Path { path in
                let start = CGPoint(x: size.width * 0.60, y: size.height * 0.78)
                let end = CGPoint(x: size.width * 0.88, y: size.height * 0.72)
                path.move(to: start)
                path.addQuadCurve(to: end, control: CGPoint(x: size.width * 0.76, y: size.height * 0.88))
            }
            .stroke(doodleColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [5, 5]))

            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.60, y: size.height * 0.78)
            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.88, y: size.height * 0.72)

            // Route 3 — short path mid-right
            Path { path in
                let start = CGPoint(x: size.width * 0.82, y: size.height * 0.35)
                let end = CGPoint(x: size.width * 0.92, y: size.height * 0.48)
                path.move(to: start)
                path.addQuadCurve(to: end, control: CGPoint(x: size.width * 0.96, y: size.height * 0.38))
            }
            .stroke(doodleColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [4, 4]))

            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.82, y: size.height * 0.35)
            Circle().fill(doodleColor).frame(width: dotSize, height: dotSize)
                .position(x: size.width * 0.92, y: size.height * 0.48)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Branding
            VStack(spacing: SonderSpacing.sm) {
                // Per-letter wordmark with staggered entrance
                HStack(spacing: 0) {
                    ForEach(Array(sonderLetters.enumerated()), id: \.offset) { index, letter in
                        Text(letter)
                            .font(.system(size: 48, weight: .bold, design: .serif))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [SonderColors.terracotta, SonderColors.terracotta.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(wordmarkVisible ? 1 : 0)
                            .offset(y: wordmarkVisible ? 0 : 16)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.75)
                                    .delay(Double(index) * 0.08),
                                value: wordmarkVisible
                            )
                    }
                }
                .scaleEffect(breatheScale)

                Text("Log anything. Remember everywhere.")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: taglineVisible ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.55), value: taglineVisible)
            }

            Spacer()

            // Phone input section
            VStack(spacing: SonderSpacing.lg) {
                VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                    Text("Phone number")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    HStack(spacing: SonderSpacing.sm) {
                        // Country code
                        Text("+1")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkDark)
                            .padding(.leading, SonderSpacing.md)

                        Divider()
                            .frame(height: 24)

                        // Phone number input
                        TextField("(555) 123-4567", text: Binding(
                            get: { formattedPhone },
                            set: { newValue in
                                // Extract only digits from pasted/typed input
                                let digits = newValue.filter(\.isNumber)
                                phoneDigits = String(digits.prefix(10))
                            }
                        ))
                        .font(SonderTypography.body)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isPhoneFieldFocused)
                    }
                    .padding(.vertical, SonderSpacing.md)
                    .padding(.trailing, SonderSpacing.md)
                    .background(SonderColors.warmGray)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                            .stroke(
                                isPhoneFieldFocused ? SonderColors.terracotta : Color.clear,
                                lineWidth: 2
                            )
                            .animation(.easeInOut(duration: 0.2), value: isPhoneFieldFocused)
                    )
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.dustyRose)
                        .transition(.opacity)
                }

                // Continue button
                Button(action: sendOTP) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WarmButtonStyle(isPrimary: true))
                .disabled(!isValid || isLoading)
                .opacity(isValid && !isLoading ? 1 : 0.5)
                .scaleEffect(buttonPop ? 1.03 : 1.0)
            }
            .padding(.horizontal, SonderSpacing.lg)
            .opacity(inputVisible ? 1 : 0)
            .offset(y: inputVisible ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.70), value: inputVisible)

            Spacer()

            // Secondary sign-in link
            Button {
                showSecondarySignIn = true
            } label: {
                Text("Already have an account? ")
                    .foregroundStyle(SonderColors.inkMuted) +
                Text("Sign in")
                    .foregroundStyle(SonderColors.terracotta)
                    .fontWeight(.medium)
            }
            .font(SonderTypography.subheadline)
            .buttonStyle(.plain)
            .padding(.bottom, SonderSpacing.xxl)
            .opacity(linkVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.90), value: linkVisible)
        }
        .background(decorativeBackground)
        .fullScreenCover(isPresented: $showOTPView) {
            OTPVerificationView(phoneNumber: fullPhoneNumber)
        }
        .sheet(isPresented: $showSecondarySignIn) {
            SecondarySignInSheet()
        }
        .onChange(of: isValid) { oldValue, newValue in
            if newValue && !oldValue {
                // Button pop + haptic when phone becomes valid
                SonderHaptics.impact(.light, intensity: 0.6)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    buttonPop = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        buttonPop = false
                    }
                }
            }
        }
        .onAppear {
            // Staggered entrance — all flags set together, individual delays in .animation() modifiers
            wordmarkVisible = true
            taglineVisible = true
            inputVisible = true
            linkVisible = true

            // Breathing animation on wordmark
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(
                    .easeInOut(duration: 3.0)
                    .repeatForever(autoreverses: true)
                ) {
                    breatheScale = 1.01
                }
            }
        }
    }

    // MARK: - Actions

    private func sendOTP() {
        guard isValid else { return }
        SonderHaptics.impact(.medium)
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.sendPhoneOTP(phone: fullPhoneNumber)
                showOTPView = true
            } catch {
                print("📱 OTP send error: \(error)")
                errorMessage = "Couldn't send code. Please try again."
            }
            isLoading = false
        }
    }
}

// MARK: - Secondary Sign-In Sheet

/// Apple / Google sign-in for existing users.
private struct SecondarySignInSheet: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var isSigningInWithGoogle = false
    @State private var signInError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: SonderSpacing.xl) {
                Spacer()

                VStack(spacing: SonderSpacing.sm) {
                    Text("Welcome back")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)

                    Text("Sign in with your existing account")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)
                }

                VStack(spacing: SonderSpacing.md) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        Task {
                            switch result {
                            case .success(let authorization):
                                if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    do {
                                        try await authService.signInWithApple(credential: credential)
                                        dismiss()
                                    } catch {
                                        signInError = error.localizedDescription
                                    }
                                }
                            case .failure(let error):
                                signInError = error.localizedDescription
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)

                    Button {
                        Task {
                            isSigningInWithGoogle = true
                            defer { isSigningInWithGoogle = false }
                            await authService.signInWithGoogle()
                            if authService.isAuthenticated {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if isSigningInWithGoogle {
                                ProgressView()
                                    .tint(SonderColors.inkDark)
                            } else {
                                Image(systemName: "g.circle.fill")
                            }
                            Text("Sign in with Google")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(SonderColors.warmGray)
                        .foregroundStyle(SonderColors.inkDark)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                                .stroke(SonderColors.inkLight.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .disabled(isSigningInWithGoogle)
                }
                .padding(.horizontal, SonderSpacing.xxl)

                Spacer()
            }
            .background(SonderColors.cream)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }
            }
            .alert("Sign In Failed", isPresented: Binding(
                get: { signInError != nil },
                set: { if !$0 { signInError = nil } }
            )) {
                Button("OK", role: .cancel) { signInError = nil }
            } message: {
                Text(signInError ?? "An unknown error occurred.")
            }
        }
    }
}
