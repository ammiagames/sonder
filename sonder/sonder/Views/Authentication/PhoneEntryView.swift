//
//  PhoneEntryView.swift
//  sonder
//

import SwiftUI
import AuthenticationServices

/// Primary authentication screen — phone number entry with OTP flow.
/// "Already have an account?" link reveals Apple/Google sign-in as a secondary option.
struct PhoneEntryView: View {
    @Environment(AuthenticationService.self) private var authService

    @State private var phoneDigits = ""  // raw digits only (no formatting)
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showOTPView = false
    @State private var showSecondarySignIn = false

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

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Branding
            VStack(spacing: SonderSpacing.sm) {
                Text("sonder")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SonderColors.terracotta, SonderColors.terracotta.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Log anything. Remember everywhere.")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()

            // Phone input
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
                    }
                    .padding(.vertical, SonderSpacing.md)
                    .padding(.trailing, SonderSpacing.md)
                    .background(SonderColors.warmGray)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
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
            }
            .padding(.horizontal, SonderSpacing.lg)

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
        }
        .background(SonderColors.cream)
        .fullScreenCover(isPresented: $showOTPView) {
            OTPVerificationView(phoneNumber: fullPhoneNumber)
        }
        .sheet(isPresented: $showSecondarySignIn) {
            SecondarySignInSheet()
        }
    }

    private func sendOTP() {
        guard isValid else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.sendPhoneOTP(phone: fullPhoneNumber)
                showOTPView = true
            } catch {
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
