//
//  FollowListView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

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
            .padding()

            // Content
            TabView(selection: $selectedTab) {
                followersContent
                    .tag(Tab.followers)

                followingContent
                    .tag(Tab.following)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if followers.isEmpty {
                ContentUnavailableView {
                    Label("No Followers", systemImage: "person.2")
                } description: {
                    Text("No one is following \(username) yet")
                }
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
            }
        }
    }

    // MARK: - Following Content

    private var followingContent: some View {
        Group {
            if isLoadingFollowing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if following.isEmpty {
                ContentUnavailableView {
                    Label("Not Following Anyone", systemImage: "person.2")
                } description: {
                    Text("\(username) isn't following anyone yet")
                }
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
            print("Error loading followers: \(error)")
        }
        isLoadingFollowers = false
    }

    private func loadFollowing() async {
        isLoadingFollowing = true
        do {
            following = try await socialService.getFollowing(for: userID)
        } catch {
            print("Error loading following: \(error)")
        }
        isLoadingFollowing = false
    }
}

#Preview {
    NavigationStack {
        FollowListView(userID: "user123", username: "johndoe")
    }
}
