//
//  FollowListView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "FollowListView")

/// View showing followers or following list with tabs
struct FollowListView: View {
    let userID: String
    let username: String
    let initialTab: Tab

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var selectedTab: Tab
    @State private var followers: [User] = []
    @State private var following: [User] = []
    @State private var isLoadingFollowers = false
    @State private var isLoadingFollowing = false
    @State private var selectedUserID: String?

    enum Tab: String, CaseIterable {
        case followers = "Followers"
        case following = "Following"
    }

    init(userID: String, username: String, initialTab: Tab = .followers) {
        self.userID = userID
        self.username = username
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom capsule tab switcher
            tabSwitcher
                .padding(.horizontal, SonderSpacing.md)
                .padding(.vertical, SonderSpacing.sm)

            // Content
            TabView(selection: $selectedTab) {
                followersContent
                    .tag(Tab.followers)

                followingContent
                    .tag(Tab.following)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(SonderColors.cream)
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedUserID) { userID in
            OtherUserProfileView(userID: userID)
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Custom Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabButton(
                title: "Followers",
                count: followers.count,
                tab: .followers
            )
            tabButton(
                title: "Following",
                count: following.count,
                tab: .following
            )
        }
        .padding(SonderSpacing.xxs)
        .background(SonderColors.warmGray)
        .clipShape(Capsule())
    }

    private func tabButton(title: String, count: Int, tab: Tab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Text("\(title) (\(count))")
                .font(SonderTypography.caption)
                .fontWeight(.medium)
                .padding(.horizontal, SonderSpacing.md)
                .padding(.vertical, SonderSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(selectedTab == tab ? SonderColors.terracotta : .clear)
                .foregroundStyle(selectedTab == tab ? .white : SonderColors.inkMuted)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Followers Content

    private var followersContent: some View {
        Group {
            if isLoadingFollowers {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if followers.isEmpty {
                emptyState(
                    title: "No Followers Yet",
                    subtitle: "Share your journey to connect with friends"
                )
            } else {
                userList(users: followers)
            }
        }
    }

    // MARK: - Following Content

    private var followingContent: some View {
        Group {
            if isLoadingFollowing {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if following.isEmpty {
                emptyState(
                    title: "Not Following Anyone",
                    subtitle: "\(username) isn't following anyone yet"
                )
            } else {
                userList(users: following)
            }
        }
    }

    // MARK: - User List

    private func userList(users: [User]) -> some View {
        ScrollView {
            LazyVStack(spacing: SonderSpacing.sm) {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    FollowListUserCard(
                        user: user,
                        isCurrentUser: user.id == authService.currentUser?.id,
                        onTap: { selectedUserID = user.id }
                    )
                    .feedCardEntrance(index: index)
                }
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.top, SonderSpacing.xs)
            .padding(.bottom, 80)
        }
        .refreshable {
            await loadData()
        }
    }

    // MARK: - Empty State

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: SonderSpacing.md) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            SonderColors.terracotta.opacity(0.15),
                            SonderColors.ochre.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(SonderColors.terracotta.opacity(0.6))
                }

            Text(title)
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            Text(subtitle)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadFollowers()
            }
            group.addTask {
                await loadFollowing()
            }
        }
    }

    private func loadFollowers() async {
        isLoadingFollowers = true
        do {
            followers = try await socialService.getFollowers(for: userID)
        } catch {
            logger.error("Error loading followers: \(error.localizedDescription)")
        }
        isLoadingFollowers = false
    }

    private func loadFollowing() async {
        isLoadingFollowing = true
        do {
            following = try await socialService.getFollowing(for: userID)
        } catch {
            logger.error("Error loading following: \(error.localizedDescription)")
        }
        isLoadingFollowing = false
    }
}

// MARK: - Follow List User Card

private struct FollowListUserCard: View {
    let user: User
    let isCurrentUser: Bool
    let onTap: () -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var isFollowing = false
    @State private var isLoading = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SonderSpacing.sm) {
                // Avatar
                if let urlString = user.avatarURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 46, height: 46)) {
                        avatarPlaceholder
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                // User info
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)

                    Text("Exploring since \(user.createdAt.formatted(.dateTime.month(.wide).year()))")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }

                Spacer()

                // Follow button (not shown for current user)
                if !isCurrentUser {
                    followButton
                }
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
        .task {
            await checkFollowStatus()
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
            .frame(width: 46, height: 46)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
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
                        .overlay(
                            Capsule()
                                .strokeBorder(SonderColors.inkLight.opacity(0.3), lineWidth: 1)
                        )
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

    private func checkFollowStatus() async {
        guard let currentUserID = authService.currentUser?.id else { return }
        isFollowing = await socialService.isFollowingAsync(userID: user.id, currentUserID: currentUserID)
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

                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                logger.error("Follow error: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        FollowListView(userID: "user123", username: "johndoe")
    }
}
