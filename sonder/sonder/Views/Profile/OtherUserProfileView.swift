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
    @Environment(TripService.self) private var tripService

    @State private var user: User?
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    @State private var followerCount = 0
    @State private var followingCount = 0
    @State private var userLogs: [FeedItem] = []
    @State private var userTrips: [Trip] = []

    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: SonderSpacing.md) {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                    Text("Loading profile...")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else if let user = user {
                VStack(spacing: 0) {
                    // Profile header card
                    profileHeader(user)
                        .padding(.top, SonderSpacing.md)

                    // Stats bar
                    statsSection
                        .padding(.top, SonderSpacing.lg)

                    // Follow button
                    if user.id != authService.currentUser?.id {
                        followButton
                            .padding(.top, SonderSpacing.md)
                            .padding(.horizontal, SonderSpacing.lg)
                    }

                    // Recent trips film strip
                    if !recentTrips.isEmpty {
                        recentTripsSection
                            .padding(.top, SonderSpacing.lg)
                            .padding(.horizontal, SonderSpacing.md)
                    }

                    // Recent activity
                    if !userLogs.isEmpty {
                        recentActivitySection
                            .padding(.top, SonderSpacing.lg)
                            .padding(.horizontal, SonderSpacing.md)
                    }

                    // Divider
                    Rectangle()
                        .fill(SonderColors.warmGray)
                        .frame(height: 1)
                        .padding(.top, SonderSpacing.lg)
                        .padding(.horizontal, SonderSpacing.lg)

                    // Logs
                    logsSection
                        .padding(.top, SonderSpacing.md)
                        .padding(.horizontal, SonderSpacing.md)
                }
                .padding(.bottom, SonderSpacing.xxl)
            } else {
                ContentUnavailableView {
                    Label("User Not Found", systemImage: "person.slash")
                        .foregroundColor(SonderColors.inkMuted)
                } description: {
                    Text("This user doesn't exist or has been deleted")
                        .foregroundColor(SonderColors.inkLight)
                }
                .padding(.top, 80)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle(user?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let user = user {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OtherUserMapView(userID: user.id, username: user.username, logs: userLogs)
                    } label: {
                        Image(systemName: "map")
                            .foregroundColor(SonderColors.terracotta)
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
        VStack(spacing: SonderSpacing.sm) {
            // Avatar
            if let urlString = user.avatarURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 88, height: 88)) {
                    avatarPlaceholder(for: user)
                }
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(SonderColors.warmGray, lineWidth: 3)
                )
            } else {
                avatarPlaceholder(for: user)
                    .overlay(
                        Circle()
                            .stroke(SonderColors.warmGray, lineWidth: 3)
                    )
            }

            // Username
            Text("@\(user.username)")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            // Bio
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.xxl)
            }

            // Member since
            HStack(spacing: SonderSpacing.xxs) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundColor(SonderColors.sage)
                Text("Exploring since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatarPlaceholder(for user: User) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 88, height: 88)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 0) {
            NavigationLink {
                FollowListView(
                    userID: userID,
                    username: user?.username ?? "",
                    initialTab: .followers
                )
            } label: {
                statItem(value: followerCount, label: "Followers")
            }
            .buttonStyle(.plain)

            statDivider

            NavigationLink {
                FollowListView(
                    userID: userID,
                    username: user?.username ?? "",
                    initialTab: .following
                )
            } label: {
                statItem(value: followingCount, label: "Following")
            }
            .buttonStyle(.plain)

            statDivider

            statItem(value: userLogs.count, label: "Places")
        }
        .padding(.vertical, SonderSpacing.sm)
        .padding(.horizontal, SonderSpacing.lg)
        .background(SonderColors.warmGray.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .padding(.horizontal, SonderSpacing.lg)
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: SonderSpacing.xxs) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(SonderColors.inkDark)
            Text(label)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGrayDark)
            .frame(width: 1, height: 32)
    }

    // MARK: - Follow Button

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            HStack(spacing: SonderSpacing.xs) {
                if isFollowLoading {
                    ProgressView()
                        .tint(isFollowing ? SonderColors.inkDark : .white)
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isFollowing ? "Following" : "Follow")
                        .font(SonderTypography.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.sm)
            .background(isFollowing ? SonderColors.warmGray : SonderColors.terracotta)
            .foregroundColor(isFollowing ? SonderColors.inkDark : .white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .disabled(isFollowLoading)
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack {
                Text("Places")
                    .font(SonderTypography.journalTitle)
                    .foregroundColor(SonderColors.inkDark)

                Spacer()

                Text("\(userLogs.count)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
            }
            .padding(.horizontal, SonderSpacing.xs)

            if userLogs.isEmpty {
                VStack(spacing: SonderSpacing.sm) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 32))
                        .foregroundColor(SonderColors.inkLight)
                    Text("No places logged yet")
                        .font(SonderTypography.body)
                        .foregroundColor(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.xxl)
            } else {
                LazyVStack(spacing: SonderSpacing.sm) {
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

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        let recentLogs = Array(userLogs.sorted { $0.createdAt > $1.createdAt }.prefix(3))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Recent activity")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(recentLogs) { item in
                NavigationLink {
                    FeedLogDetailView(feedItem: item)
                } label: {
                    HStack(spacing: SonderSpacing.sm) {
                        Text(item.rating.emoji)
                            .font(.system(size: 20))
                            .frame(width: 36, height: 36)
                            .background(SonderColors.pinColor(for: item.rating).opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SonderColors.inkDark)
                                .lineLimit(1)

                            Text(item.createdAt.relativeDisplay)
                                .font(.system(size: 12))
                                .foregroundColor(SonderColors.inkLight)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)

                if item.id != recentLogs.last?.id {
                    Divider()
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Recent Trips (Boarding Pass)

    private var recentTrips: [Trip] {
        Array(userTrips.prefix(5))
    }

    private func tripDateText(_ trip: Trip) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        if let start = trip.startDate, let end = trip.endDate {
            let startText = formatter.string(from: start)
            let endText = formatter.string(from: end)
            return startText == endText ? startText : "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = trip.startDate {
            return formatter.string(from: start)
        } else if let end = trip.endDate {
            return formatter.string(from: end)
        }
        return nil
    }

    private func tripCoverURL(_ trip: Trip) -> URL? {
        if let cover = trip.coverPhotoURL, let url = URL(string: cover) {
            return url
        }
        return nil
    }

    @ViewBuilder
    private func tripCoverPhoto(_ trip: Trip, size: CGSize) -> some View {
        if let url = tripCoverURL(trip) {
            DownsampledAsyncImage(url: url, targetSize: size) {
                tripPlaceholderGradient(trip)
            }
        } else {
            tripPlaceholderGradient(trip)
        }
    }

    private func tripPlaceholderGradient(_ trip: Trip) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        let grad = gradients[abs(trip.id.hashValue) % gradients.count]
        return LinearGradient(
            colors: [grad.0.opacity(0.7), grad.1.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "airplane")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var recentTripsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Recent trips")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.sm) {
                    ForEach(recentTrips, id: \.id) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                        } label: {
                            boardingPassCard(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func boardingPassCard(trip: Trip) -> some View {
        HStack(spacing: 0) {
            tripCoverPhoto(trip, size: CGSize(width: 72, height: 100))
                .frame(width: 72, height: 100)
                .clipped()

            VStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle()
                        .fill(SonderColors.cream)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 12)
            .background(SonderColors.warmGray)

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text("DESTINATION")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(SonderColors.inkLight)
                    .tracking(0.5)

                Text(trip.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: SonderSpacing.md) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DATE")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(SonderColors.inkLight)
                            .tracking(0.5)
                        Text(tripDateText(trip) ?? "—")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
                    }
                }

                RoundedRectangle(cornerRadius: 1)
                    .fill(SonderColors.terracotta)
                    .frame(height: 3)
            }
            .padding(SonderSpacing.sm)
            .frame(width: 140, height: 100, alignment: .leading)
            .background(SonderColors.warmGray)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                .stroke(SonderColors.warmGrayDark, lineWidth: 0.5)
        )
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

        // Load trips
        do {
            userTrips = try await tripService.fetchTrips(for: userID)
        } catch {
            print("Error loading user trips: \(error)")
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

                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        HStack(spacing: SonderSpacing.sm) {
            // Photo
            if let urlString = feedItem.log.photoURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                    placePhoto
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            } else {
                placePhoto
            }

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                HStack {
                    Text(feedItem.place.name)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    Spacer()

                    Text(feedItem.rating.emoji)
                }

                Text(feedItem.place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .lineLimit(1)

                Text(feedItem.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundColor(SonderColors.inkLight)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = feedItem.place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                photoPlaceholder
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }
}

#Preview {
    NavigationStack {
        OtherUserProfileView(userID: "user123")
    }
}
