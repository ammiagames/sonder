//
//  AuthenticationService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import AuthenticationServices
import Supabase
import GoogleSignIn

// TODO: Test Sign in with Apple when we have a paid Apple Developer account ($99/year)
// The capability is not available with Personal Team (free account)

@MainActor
@Observable
final class AuthenticationService {
    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false
    /// True while restoring session on launch. Show splash screen instead of auth screen.
    var isCheckingSession = true
    var error: Error?

    private let supabase = SupabaseConfig.client

    // Debug mode - set to true to bypass authentication during development
    // NOTE: Must be false for Supabase RLS to work (need real auth session)
    #if DEBUG
    private let debugBypassAuth = false
    #else
    private let debugBypassAuth = false
    #endif

    init() {
        Task {
            await checkSession()
        }
    }

    // MARK: - Debug Bypass

    /// Creates a mock user for development purposes
    func debugSignIn() {
        guard debugBypassAuth else { return }
        currentUser = User(
            id: "debug-user-\(UUID().uuidString.prefix(8))",
            username: "debug_user",
            avatarURL: nil,
            bio: "Debug user for development",
            isPublic: false
        )
    }
    
    // MARK: - Session Management
    
    func checkSession() async {
        defer { isCheckingSession = false }
        do {
            let session = try await supabase.auth.session
            await loadUser(id: session.user.id.uuidString)
        } catch {
            // No active session, user needs to sign in
            self.currentUser = nil
        }
    }
    
    private func loadUser(id: String, retries: Int = 2) async {
        for attempt in 0...retries {
            do {
                let response: User = try await supabase
                    .from("users")
                    .select()
                    .eq("id", value: id)
                    .single()
                    .execute()
                    .value

                self.currentUser = response
                return
            } catch {
                if attempt < retries {
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    self.error = error
                }
            }
        }
    }
    
    // MARK: - Sign in with Apple
    
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }
        
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )
            
            // Create or update user in database
            let userID = session.user.id.uuidString
            let email = credential.email ?? session.user.email ?? ""
            let username = generateUsername(from: email)
            
            try await createOrUpdateUser(
                id: userID,
                username: username,
                email: email
            )
            
            await loadUser(id: userID)
        } catch {
            self.error = error
            throw error
        }
    }
    
    // MARK: - Sign in with Google

    /// Initiates Google Sign-In flow
    func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Get the presenting view controller
            guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = await windowScene.windows.first?.rootViewController else {
                throw AuthError.networkError
            }

            // Perform Google Sign-In
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.invalidCredential
            }

            let accessToken = result.user.accessToken.tokenString

            // Sign in to Supabase with the Google ID token and access token
            // Both tokens are required to avoid nonce mismatch errors
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )

            // Create or update user in database
            let userID = session.user.id.uuidString
            let email = result.user.profile?.email ?? session.user.email ?? ""
            let username = generateUsername(from: email)

            try await createOrUpdateUser(
                id: userID,
                username: username,
                email: email
            )

            await loadUser(id: userID)
        } catch {
            print("Google Sign-In failed: \(error)")
            self.error = error
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() async throws {
        try await supabase.auth.signOut()
        currentUser = nil
    }
    
    // MARK: - Helpers
    
    private func createOrUpdateUser(id: String, username: String, email: String) async throws {
        // First check if user already exists
        let existingUsers: [User] = try await supabase
            .from("users")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        if existingUsers.isEmpty {
            // New user - create with current timestamp
            let user = User(
                id: id,
                username: username,
                email: email,
                isPublic: false,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await supabase
                .from("users")
                .insert(user)
                .execute()
        } else {
            // Existing user - only update email if changed, preserve createdAt
            struct UserUpdate: Codable {
                let email: String?
                let updated_at: Date
            }

            try await supabase
                .from("users")
                .update(UserUpdate(email: email, updated_at: Date()))
                .eq("id", value: id)
                .execute()
        }
    }
    
    func generateUsername(from email: String) -> String {
        let components = email.components(separatedBy: "@")
        let baseUsername = components.first ?? "user"
        return baseUsername.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidCredential
    case networkError
    case userCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid authentication credential"
        case .networkError:
            return "Network error occurred"
        case .userCreationFailed:
            return "Failed to create user account"
        }
    }
}
