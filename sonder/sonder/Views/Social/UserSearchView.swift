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
                    .padding()

                // Results
                if isSearching {
                    ProgressView()
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
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
                .foregroundColor(.secondary)

            TextField("Search by username", text: $searchText)
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
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        ContentUnavailableView {
            Label("Search Users", systemImage: "person.2")
        } description: {
            Text("Enter a username to find friends")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No users found matching \"\(searchText)\"")
        }
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
            HStack(spacing: 12) {
                // Avatar
                if let urlString = user.avatarURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                // User info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 50, height: 50)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(width: 80)
                } else if isFollowing {
                    Text("Following")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                } else {
                    Text("Follow")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
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
