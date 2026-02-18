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
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(SonderSpacing.md)

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

    // MARK: - Followers Content

    private var followersContent: some View {
        Group {
            if isLoadingFollowers {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if followers.isEmpty {
                VStack(spacing: SonderSpacing.md) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundStyle(SonderColors.inkLight)

                    Text("No Followers")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)

                    Text("No one is following \(username) yet")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(followers, id: \.id) { user in
                        UserSearchRow(
                            user: user,
                            isCurrentUser: user.id == authService.currentUser?.id
                        ) {
                            selectedUserID = user.id
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(SonderColors.cream)
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
                VStack(spacing: SonderSpacing.md) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundStyle(SonderColors.inkLight)

                    Text("Not Following Anyone")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)

                    Text("\(username) isn't following anyone yet")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(following, id: \.id) { user in
                        UserSearchRow(
                            user: user,
                            isCurrentUser: user.id == authService.currentUser?.id
                        ) {
                            selectedUserID = user.id
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(SonderColors.cream)
            }
        }
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

#Preview {
    NavigationStack {
        FollowListView(userID: "user123", username: "johndoe")
    }
}
