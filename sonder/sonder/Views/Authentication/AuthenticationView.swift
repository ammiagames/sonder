//
//  AuthenticationView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @Environment(AuthenticationService.self) private var authService
    @State private var isSigningInWithGoogle = false

    var body: some View {
        VStack(spacing: SonderSpacing.xxl) {
            Spacer()

            // Logo/Branding
            VStack(spacing: SonderSpacing.sm) {
                Image(systemName: "map.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(SonderColors.terracotta)

                Text("Sonder")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.inkDark)

                Text("Log anything. Remember everywhere.")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Authentication Buttons
            VStack(spacing: SonderSpacing.md) {
                #if DEBUG
                // Debug bypass button - only visible in debug builds
                Button {
                    authService.debugSignIn()
                } label: {
                    HStack {
                        Image(systemName: "hammer.fill")
                        Text("Debug Sign In (Dev Only)")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(SonderColors.ochre)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }
                #endif

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task {
                        switch result {
                        case .success(let authorization):
                            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                try? await authService.signInWithApple(credential: credential)
                            }
                        case .failure(let error):
                            print("Sign in with Apple failed: \(error)")
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
                    .foregroundColor(SonderColors.inkDark)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                            .stroke(SonderColors.inkLight.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(isSigningInWithGoogle)
            }
            .padding(.horizontal, SonderSpacing.xxl)
            .padding(.bottom, SonderSpacing.xxl)
        }
        .padding()
        .background(SonderColors.cream)
    }
}

#Preview {
    AuthenticationView()
        .environment(AuthenticationService())
}
