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
        VStack(spacing: 32) {
            Spacer()

            // Logo/Branding
            VStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)

                Text("Sonder")
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                Text("Log anything. Remember everywhere.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Authentication Buttons
            VStack(spacing: 16) {
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
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                #endif

                // TODO: Test Sign in with Apple when we have paid Apple Developer account
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
                                .tint(.black)
                        } else {
                            Image(systemName: "g.circle.fill")
                        }
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(isSigningInWithGoogle)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding()
    }
}

#Preview {
    AuthenticationView()
        .environment(AuthenticationService())
}
