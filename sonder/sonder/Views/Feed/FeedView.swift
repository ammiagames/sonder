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
            ZStack {
                if feedService.feedItems.isEmpty && !feedService.isLoading {
                    emptyState
                } else {
                    feedContent
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if syncEngine.isSyncing || feedService.isLoading {
                        ProgressView()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUserSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
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
        ContentUnavailableView {
            Label("No Posts Yet", systemImage: "person.2")
        } description: {
            Text("Follow friends to see their logs here")
        } actions: {
            Button {
                showUserSearch = true
            } label: {
                Text("Find Friends")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
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
                        .padding()
                }
            }
            .padding()
        }
        .refreshable {
            if let userID = authService.currentUser?.id {
                await feedService.refreshFeed(for: userID)
            }
        }
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("You're offline. Changes will sync when connected.")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .foregroundColor(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var newPostsBanner: some View {
        Button {
            Task {
                if let userID = authService.currentUser?.id {
                    await feedService.showNewPosts(for: userID)
                }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.up")
                Text("New posts available")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
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
                VStack(alignment: .leading, spacing: 20) {
                    // Place info
                    placeSection

                    Divider()

                    // Rating
                    ratingSection

                    // Note
                    if let note = feedItem.log.note, !note.isEmpty {
                        Divider()
                        noteSection(note)
                    }

                    // Tags
                    if !feedItem.log.tags.isEmpty {
                        Divider()
                        tagsSection
                    }

                    // Meta
                    Divider()
                    metaSection
                }
                .padding()
            }
        }
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
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
    }

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin")
                    .foregroundColor(.secondary)
                Text(feedItem.place.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var ratingSection: some View {
        HStack {
            Text("Rating")
                .font(.headline)
            Spacer()
            HStack(spacing: 8) {
                Text(feedItem.rating.emoji)
                    .font(.title2)
                Text(feedItem.rating.displayName)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func noteSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.headline)
            Text(note)
                .foregroundColor(.secondary)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)
            FlowLayoutTags(tags: feedItem.log.tags)
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logged by")
                    .foregroundColor(.secondary)
                Spacer()
                Text("@\(feedItem.user.username)")
            }
            .font(.subheadline)

            HStack {
                Text("Date")
                    .foregroundColor(.secondary)
                Spacer()
                Text(feedItem.createdAt.formatted(date: .long, time: .omitted))
            }
            .font(.subheadline)
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
