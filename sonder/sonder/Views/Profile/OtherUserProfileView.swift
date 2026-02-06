//
//  OtherUserProfileView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// View another user's profile (read-only)
struct OtherUserProfileView: View {
    let userID: String

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService
    @Environment(FeedService.self) private var feedService

    @State private var user: User?
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    @State private var followerCount = 0
    @State private var followingCount = 0
    @State private var userLogs: [FeedItem] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if let user = user {
                    // Profile header
                    profileHeader(user)

                    // Stats
                    statsSection

                    // Follow button
                    if user.id != authService.currentUser?.id {
                        followButton
                    }

                    Divider()
                        .padding(.horizontal)

                    // Logs
                    logsSection
                } else {
                    ContentUnavailableView {
                        Label("User Not Found", systemImage: "person.slash")
                    } description: {
                        Text("This user doesn't exist or has been deleted")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(user?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let user = user {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OtherUserMapView(userID: user.id, username: user.username, logs: userLogs)
                    } label: {
                        Image(systemName: "map")
                    }
                }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Profile Header

    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: 12) {
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
                        avatarPlaceholder(for: user)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(for: user)
            }

            // Username
            Text(user.username)
                .font(.title2)
                .fontWeight(.bold)

            // Bio
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Member since
            Text("Exploring since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func avatarPlaceholder(for user: User) -> some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 80, height: 80)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 40) {
            NavigationLink {
                FollowListView(
                    userID: userID,
                    username: user?.username ?? "",
                    initialTab: .followers
                )
            } label: {
                VStack(spacing: 4) {
                    Text("\(followerCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                FollowListView(
                    userID: userID,
                    username: user?.username ?? "",
                    initialTab: .following
                )
            } label: {
                VStack(spacing: 4) {
                    Text("\(followingCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Text("\(userLogs.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Places")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Follow Button

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            HStack {
                if isFollowLoading {
                    ProgressView()
                        .tint(isFollowing ? .primary : .white)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isFollowing ? Color(.systemGray5) : Color.accentColor)
            .foregroundColor(isFollowing ? .primary : .white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isFollowLoading)
        .padding(.horizontal)
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Places")
                .font(.headline)

            if userLogs.isEmpty {
                Text("No places logged yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(userLogs) { item in
                        NavigationLink {
                            FeedLogDetailView(feedItem: item)
                        } label: {
                            OtherUserLogRow(feedItem: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true

        // Load user
        do {
            user = try await socialService.getUser(id: userID)
        } catch {
            print("Error loading user: \(error)")
        }

        // Check follow status
        if let currentUserID = authService.currentUser?.id {
            isFollowing = await socialService.isFollowingAsync(userID: userID, currentUserID: currentUserID)
        }

        // Load counts
        followerCount = await socialService.getFollowerCount(for: userID)
        followingCount = await socialService.getFollowingCount(for: userID)

        // Load logs (all profiles are public)
        do {
            userLogs = try await feedService.fetchUserLogs(userID: userID)
        } catch {
            print("Error loading user logs: \(error)")
        }

        isLoading = false
    }

    private func toggleFollow() {
        guard let currentUserID = authService.currentUser?.id else { return }

        isFollowLoading = true

        Task {
            do {
                if isFollowing {
                    try await socialService.unfollowUser(userID: userID, currentUserID: currentUserID)
                    followerCount = max(0, followerCount - 1)
                } else {
                    try await socialService.followUser(userID: userID, currentUserID: currentUserID)
                    followerCount += 1
                }
                isFollowing.toggle()

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                print("Follow error: \(error)")
            }
            isFollowLoading = false
        }
    }
}

// MARK: - Other User Log Row

struct OtherUserLogRow: View {
    let feedItem: FeedItem

    var body: some View {
        HStack(spacing: 12) {
            // Photo
            if let urlString = feedItem.log.photoURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placePhoto
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                placePhoto
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(feedItem.place.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(feedItem.rating.emoji)
                }

                Text(feedItem.place.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(feedItem.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = feedItem.place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    photoPlaceholder
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
    }
}

#Preview {
    NavigationStack {
        OtherUserProfileView(userID: "user123")
    }
}
