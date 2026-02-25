//
//  AuthenticationService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import AuthenticationServices
import SwiftData
import Supabase
import GoogleSignIn
import os

@MainActor
@Observable
final class AuthenticationService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "AuthenticationService")
    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false
    /// True while restoring session on launch. Show splash screen instead of auth screen.
    var isCheckingSession = true
    var error: Error?

    /// Set by SonderApp after ModelContainer is ready. Used for local user caching.
    var modelContext: ModelContext?

    private let supabase = SupabaseConfig.client

    init() {
        // Session check is deferred until modelContext is set (called from initializeServices).
        // This ensures the SwiftData user cache is available for offline launches.
    }

    // MARK: - Session Management

    /// Restores session from local Keychain + SwiftData cache (no network).
    /// Call before showing UI to ensure currentUser is available immediately.
    func restoreLocalSession() {
        guard let session = supabase.auth.currentSession else {
            isCheckingSession = false
            return
        }
        let userID = session.user.id.uuidString.lowercased()
        if let cached = loadCachedUser(id: userID) {
            self.currentUser = cached
        }
    }

    func checkSession() async {
        defer { isCheckingSession = false }
        // Use local Keychain session (~ms) instead of network call (~2-5s).
        // Supabase SDK auto-refreshes expired tokens on the next API call.
        guard let session = supabase.auth.currentSession else { return }
        // Normalize to lowercase: Swift's UUID.uuidString returns uppercase, but
        // Supabase/PostgreSQL returns UUIDs as lowercase. SwiftData and UserDefaults
        // keys were set from the Supabase response (lowercase), so a case mismatch
        // causes loadCachedUser to miss and the onboarding-completion check to fail offline.
        let userID = session.user.id.uuidString.lowercased()

        // Try to load user from SwiftData cache first for instant UI
        if let cached = loadCachedUser(id: userID) {
            self.currentUser = cached
        }

        // Then refresh from Supabase in background
        await loadUser(id: userID)

        // If both cache and network failed (e.g. offline cold start),
        // create a minimal user from the session so we stay authenticated.
        // Full details will refresh when connectivity returns.
        if self.currentUser == nil {
            self.currentUser = User(
                id: userID,
                username: session.user.email?.components(separatedBy: "@").first ?? "user",
                email: session.user.email,
                isPublic: false
            )
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
                cacheUser(response)
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

    // MARK: - SwiftData User Cache

    /// Load user from local SwiftData cache (~5ms vs ~2s network).
    func loadCachedUser(id: String) -> User? {
        guard let ctx = modelContext else { return nil }
        let userID = id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == userID }
        )
        return try? ctx.fetch(descriptor).first
    }

    /// Save or update user in SwiftData for fast startup next time.
    private func cacheUser(_ user: User) {
        guard let ctx = modelContext else { return }
        let userID = user.id
        let descriptor = FetchDescriptor<User>(
            predicate: #Predicate { $0.id == userID }
        )
        if let existing = try? ctx.fetch(descriptor).first {
            existing.username = user.username
            existing.firstName = user.firstName
            existing.email = user.email
            existing.avatarURL = user.avatarURL
            existing.bio = user.bio
            existing.isPublic = user.isPublic
            existing.pinnedPlaceIDs = user.pinnedPlaceIDs
            existing.phoneNumber = user.phoneNumber
            existing.phoneNumberHash = user.phoneNumberHash
            existing.updatedAt = user.updatedAt
        } else {
            ctx.insert(user)
        }
        try? ctx.save()
    }

    /// Remove cached user from SwiftData on sign-out.
    private func clearCachedUser() {
        guard let ctx = modelContext else { return }
        let allUsers = (try? ctx.fetch(FetchDescriptor<User>())) ?? []
        for user in allUsers {
            ctx.delete(user)
        }
        try? ctx.save()
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
            let firstName = credential.fullName?.givenName

            try await createOrUpdateUser(
                id: userID,
                username: username,
                firstName: firstName,
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
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.keyWindow?.rootViewController else {
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
            let firstName = result.user.profile?.givenName

            try await createOrUpdateUser(
                id: userID,
                username: username,
                firstName: firstName,
                email: email
            )

            await loadUser(id: userID)
        } catch {
            logger.error("Google Sign-In failed: \(error.localizedDescription)")
            self.error = error
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() async throws {
        try await supabase.auth.signOut()
        currentUser = nil
        clearCachedUser()
    }
    
    // MARK: - Helpers
    
    private func createOrUpdateUser(id: String, username: String, firstName: String?, email: String) async throws {
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
                firstName: firstName,
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
            // Existing user - update email and first_name if provided
            struct UserUpdate: Codable {
                let email: String?
                let first_name: String?
                let updated_at: Date
            }

            try await supabase
                .from("users")
                .update(UserUpdate(email: email, first_name: firstName, updated_at: Date()))
                .eq("id", value: id)
                .execute()
        }
    }
    
    /// Sync current user profile fields to Supabase.
    /// Shared by EditProfileView and OnboardingProfileStep.
    func syncUserProfile(_ user: User) async {
        struct UserProfileUpdate: Codable {
            let first_name: String?
            let username: String
            let bio: String?
            let avatar_url: String?
            let phone_number: String?
            let phone_number_hash: String?
            let updated_at: Date
        }

        let update = UserProfileUpdate(
            first_name: user.firstName,
            username: user.username,
            bio: user.bio,
            avatar_url: user.avatarURL,
            phone_number: user.phoneNumber,
            phone_number_hash: user.phoneNumberHash,
            updated_at: user.updatedAt
        )

        do {
            try await supabase
                .from("users")
                .update(update)
                .eq("id", value: user.id)
                .execute()
            logger.info("User profile synced to Supabase")
        } catch {
            logger.error("Error syncing user to Supabase: \(error.localizedDescription)")
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
