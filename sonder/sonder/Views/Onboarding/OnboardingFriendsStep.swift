//
//  OnboardingFriendsStep.swift
//  sonder
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "OnboardingFriendsStep")

/// Step 4: Find and follow friends (skippable)
struct OnboardingFriendsStep: View {
    let onComplete: () -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var followedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SonderSpacing.xs) {
                Text("Travel is better together")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)

                Text("See where your friends go and share your discoveries")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, SonderSpacing.lg)
            .padding(.horizontal, SonderSpacing.lg)

            // Search bar
            searchBar
                .padding(SonderSpacing.md)

            // Results
            if isSearching {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .padding()
                Spacer()
            } else if searchText.isEmpty {
                emptyState
            } else if searchResults.isEmpty {
                noResultsState
            } else {
                resultsList
            }

            // Bottom section
            VStack(spacing: SonderSpacing.md) {
                if followedCount > 0 {
                    Text("Following \(followedCount) \(followedCount == 1 ? "person" : "people")")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.sage)
                }

                Button("Start Exploring", action: onComplete)
                    .buttonStyle(WarmButtonStyle(isPrimary: true))

                Button(action: onComplete) {
                    Text("Skip")
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SonderSpacing.xxl)
            .padding(.bottom, SonderSpacing.xxl)
        }
        .background(SonderColors.cream)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SonderColors.inkMuted)

            TextField("Search by username", text: $searchText)
                .font(SonderTypography.body)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onSubmit { performSearch() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .onChange(of: searchText) { _, newValue in
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if searchText == newValue && !newValue.isEmpty {
                    performSearch()
                }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.inkLight)

            Text("Search for friends by username")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Text("No users found matching \"\(searchText)\"")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.id) { user in
                    OnboardingUserRow(
                        user: user,
                        isCurrentUser: user.id == authService.currentUser?.id,
                        onFollowChanged: { isNowFollowing in
                            followedCount += isNowFollowing ? 1 : -1
                        }
                    )
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.xs)

                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Search

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true

        Task {
            do {
                searchResults = try await socialService.searchUsers(query: searchText)
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }
}

// MARK: - Onboarding User Row

/// Simplified user row for onboarding — no profile navigation, just follow/unfollow
private struct OnboardingUserRow: View {
    let user: User
    let isCurrentUser: Bool
    let onFollowChanged: (Bool) -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var isFollowing = false
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Avatar
            if let urlString = user.avatarURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) {
                    avatarPlaceholder
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(user.username)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Follow button
            if !isCurrentUser {
                Button { toggleFollow() } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(SonderColors.terracotta)
                                .frame(width: 80)
                        } else if isFollowing {
                            Text("Following")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(SonderColors.inkMuted)
                                .padding(.horizontal, SonderSpacing.sm)
                                .padding(.vertical, SonderSpacing.xxs)
                                .background(SonderColors.warmGray)
                                .clipShape(Capsule())
                        } else {
                            Text("Follow")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, SonderSpacing.sm)
                                .padding(.vertical, SonderSpacing.xxs)
                                .background(SonderColors.terracotta)
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .task {
            guard let currentUserID = authService.currentUser?.id else { return }
            isFollowing = await socialService.isFollowingAsync(userID: user.id, currentUserID: currentUserID)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 50, height: 50)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    private func toggleFollow() {
        guard let currentUserID = authService.currentUser?.id else { return }
        isLoading = true

        Task {
            do {
                if isFollowing {
                    try await socialService.unfollowUser(userID: user.id, currentUserID: currentUserID)
                } else {
                    try await socialService.followUser(userID: user.id, currentUserID: currentUserID)
                }
                isFollowing.toggle()
                onFollowChanged(isFollowing)

                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                logger.error("Follow error: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}
