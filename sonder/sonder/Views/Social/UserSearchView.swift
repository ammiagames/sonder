//
//  UserSearchView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Search for users by username
struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var selectedUserID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                    emptySearchState
                } else if searchResults.isEmpty {
                    noResultsState
                } else {
                    resultsList
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(SonderColors.inkMuted)
                }
            }
            .navigationDestination(item: $selectedUserID) { userID in
                OtherUserProfileView(userID: userID)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SonderColors.inkMuted)

            TextField("Search by username", text: $searchText)
                .font(SonderTypography.body)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onSubmit {
                    performSearch()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SonderColors.inkLight)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .onChange(of: searchText) { _, newValue in
            // Debounced search
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if searchText == newValue && !newValue.isEmpty {
                    performSearch()
                }
            }
        }
    }

    // MARK: - States

    private var emptySearchState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(SonderColors.inkLight)

            Text("Search Users")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text("Enter a username to find friends")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(SonderColors.inkLight)

            Text("No Results")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text("No users found matching \"\(searchText)\"")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(searchResults, id: \.id) { user in
                UserSearchRow(
                    user: user,
                    isCurrentUser: user.id == authService.currentUser?.id
                ) {
                    selectedUserID = user.id
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(SonderColors.cream)
    }

    // MARK: - Search

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true

        Task {
            do {
                searchResults = try await socialService.searchUsers(query: searchText)
            } catch {
                print("Search error: \(error)")
                searchResults = []
            }
            isSearching = false
        }
    }
}

// MARK: - User Search Row

struct UserSearchRow: View {
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
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) {
                        avatarPlaceholder
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                // User info
                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    Text(user.username)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Follow button (not shown for current user)
                if !isCurrentUser {
                    followButton
                }
            }
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
            .frame(width: 50, height: 50)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
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
                        .foregroundColor(SonderColors.inkMuted)
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xxs)
                        .background(SonderColors.warmGray)
                        .clipShape(Capsule())
                } else {
                    Text("Follow")
                        .font(SonderTypography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
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

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                print("Follow error: \(error)")
            }
            isLoading = false
        }
    }
}

#Preview {
    UserSearchView()
        .environment(AuthenticationService())
}
