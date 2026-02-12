//
//  FeedView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData

/// Main feed showing logs from followed users in chronological order
struct FeedView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(FeedService.self) private var feedService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(SocialService.self) private var socialService

    @State private var showUserSearch = false
    @State private var selectedUserID: String?
    @State private var selectedFeedItem: FeedItem?

    var body: some View {
        NavigationStack {
            Group {
                if feedService.feedItems.isEmpty && !feedService.isLoading {
                    ScrollView {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 400)
                    }
                    .refreshable {
                        if let userID = authService.currentUser?.id {
                            await feedService.refreshFeed(for: userID)
                        }
                    }
                } else {
                    feedContent
                }
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if syncEngine.isSyncing || feedService.isLoading {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUserSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }
            }
            .sheet(isPresented: $showUserSearch) {
                UserSearchView()
            }
            .navigationDestination(item: $selectedUserID) { userID in
                OtherUserProfileView(userID: userID)
            }
            .navigationDestination(item: $selectedFeedItem) { feedItem in
                FeedLogDetailView(feedItem: feedItem)
            }
            .task {
                await loadInitialData()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(SonderColors.inkLight)

            Text("No Posts Yet")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text("Follow friends to see their logs here")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
                .multilineTextAlignment(.center)

            Button {
                showUserSearch = true
            } label: {
                Text("Find Friends")
                    .font(SonderTypography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, SonderSpacing.lg)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
            }
            .padding(.top, SonderSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SonderSpacing.xxl)
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: SonderSpacing.md) {
                // Network status banner
                if !syncEngine.isOnline {
                    offlineBanner
                }

                // New posts banner
                if feedService.newPostsAvailable {
                    newPostsBanner
                }

                // Feed items
                ForEach(feedService.feedItems) { item in
                    FeedItemCard(
                        feedItem: item,
                        isWantToGo: isWantToGo(placeID: item.place.id),
                        onUserTap: {
                            selectedUserID = item.user.id
                        },
                        onPlaceTap: {
                            selectedFeedItem = item
                        },
                        onWantToGoTap: {
                            toggleWantToGo(for: item)
                        }
                    )
                    .onAppear {
                        // Infinite scroll: load more when approaching end
                        if item.id == feedService.feedItems.last?.id {
                            Task {
                                if let userID = authService.currentUser?.id {
                                    await feedService.loadMoreFeed(for: userID)
                                }
                            }
                        }
                    }
                }

                // Loading indicator at bottom
                if feedService.isLoading && !feedService.feedItems.isEmpty {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                        .padding()
                }
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .refreshable {
            if let userID = authService.currentUser?.id {
                await feedService.refreshFeed(for: userID)
            }
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 16, weight: .medium))
            Text("You're offline. Changes will sync when connected.")
                .font(SonderTypography.caption)
            Spacer()
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.ochre.opacity(0.15))
        .foregroundColor(SonderColors.ochre)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    private var newPostsBanner: some View {
        Button {
            Task {
                if let userID = authService.currentUser?.id {
                    await feedService.showNewPosts(for: userID)
                }
            }
        } label: {
            HStack(spacing: SonderSpacing.xs) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("New posts available")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.vertical, SonderSpacing.sm)
            .background(SonderColors.terracotta)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        guard let userID = authService.currentUser?.id else { return }

        // Load feed
        await feedService.loadFeed(for: userID)

        // Sync want-to-go list
        await wantToGoService.syncWantToGo(for: userID)

        // Subscribe to realtime updates
        await feedService.subscribeToRealtimeUpdates(for: userID)
    }

    // MARK: - Want to Go

    private func isWantToGo(placeID: String) -> Bool {
        guard let userID = authService.currentUser?.id else { return false }
        return wantToGoService.isInWantToGo(placeID: placeID, userID: userID)
    }

    private func toggleWantToGo(for item: FeedItem) {
        guard let userID = authService.currentUser?.id else { return }

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: item.place.id,
                    userID: userID,
                    placeName: item.place.name,
                    placeAddress: item.place.address,
                    photoReference: item.place.photoReference,
                    sourceLogID: item.log.id
                )

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                print("Error toggling want to go: \(error)")
            }
        }
    }
}

// MARK: - FeedLogDetailView

/// Detail view for a feed item (read-only for others' logs)
struct FeedLogDetailView: View {
    let feedItem: FeedItem

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero photo
                photoSection

                // Content
                VStack(alignment: .leading, spacing: SonderSpacing.lg) {
                    // Place info
                    placeSection

                    sectionDivider

                    // Rating
                    ratingSection

                    // Note
                    if let note = feedItem.log.note, !note.isEmpty {
                        sectionDivider
                        noteSection(note)
                    }

                    // Tags
                    if !feedItem.log.tags.isEmpty {
                        sectionDivider
                        tagsSection
                    }

                    // Meta
                    sectionDivider
                    metaSection
                }
                .padding(SonderSpacing.lg)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle(feedItem.place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                WantToGoButton(
                    placeID: feedItem.place.id,
                    sourceLogID: feedItem.log.id
                )
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGray)
            .frame(height: 1)
    }

    private var photoSection: some View {
        Group {
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
            } else {
                placePhoto
            }
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = feedItem.place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
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
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack(spacing: SonderSpacing.xs) {
                Image(systemName: "mappin")
                    .font(.system(size: 12))
                    .foregroundColor(SonderColors.inkMuted)
                Text(feedItem.place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }
        }
    }

    private var ratingSection: some View {
        HStack {
            Text("Rating")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
            Spacer()
            HStack(spacing: SonderSpacing.xs) {
                Text(feedItem.rating.emoji)
                    .font(.title2)
                Text(feedItem.rating.displayName)
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
            }
        }
    }

    private func noteSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Note")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
            Text(note)
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Tags")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
            FlowLayoutTags(tags: feedItem.log.tags)
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("Logged by")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                Spacer()
                Text("@\(feedItem.user.username)")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.terracotta)
            }

            HStack {
                Text("Date")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                Spacer()
                Text(feedItem.createdAt.formatted(date: .long, time: .omitted))
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkDark)
            }
        }
    }
}

// Make FeedItem conform to Hashable for navigation
extension FeedItem: Hashable {
    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    FeedView()
        .environment(AuthenticationService())
        .environment(SyncEngine(modelContext: try! ModelContainer(for: User.self).mainContext))
}
