//
//  OTPVerificationView.swift
//  sonder
//

import SwiftUI

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

    private let codeLength = 6

    /// Masked phone for display: +1 (***) ***-1234
    private var maskedPhone: String {
        let digits = phoneNumber.filter(\.isNumber)
        let last4 = String(digits.suffix(4))
        return "(***) ***-\(last4)"
    }

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
                Spacer()
            }
            .padding(.horizontal, SonderSpacing.sm)

            Spacer()

            // Header
            VStack(spacing: SonderSpacing.sm) {
                Text("Enter the code")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)

                Text("Sent to \(maskedPhone)")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            // Code boxes
            HStack(spacing: SonderSpacing.sm) {
                ForEach(0..<codeLength, id: \.self) { index in
                    let digit = index < code.count
                        ? String(code[code.index(code.startIndex, offsetBy: index)])
                        : ""
                    let isActive = index == code.count && !isVerifying

                    Text(digit)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(SonderColors.inkDark)
                        .frame(width: 52, height: 52)
                        .background(SonderColors.warmGray)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                .stroke(
                                    hasError ? SonderColors.dustyRose :
                                        isActive ? SonderColors.terracotta : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
            }
            .offset(x: shakeOffset)

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

            if isVerifying {
                ProgressView()
                    .tint(SonderColors.terracotta)
            }

            Spacer()
        }
        .background(SonderColors.cream)
        .onAppear {
            startResendCountdown()
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
                dismiss()
            } catch {
                hasError = true
                code = ""
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
