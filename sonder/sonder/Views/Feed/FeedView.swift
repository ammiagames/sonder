//
//  FeedView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "FeedView")

/// Main feed showing trips and standalone logs from followed users
struct FeedView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(FeedService.self) private var feedService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(SocialService.self) private var socialService

    var popToRoot: UUID = UUID()

    @State private var showUserSearch = false
    @State private var selectedUserID: String?
    @State private var selectedFeedItem: FeedItem?
    @State private var selectedTripID: String?
    @State private var scrollToTopTrigger: UUID?
    @State private var emptyIconScale: CGFloat = 1.0
    /// Temporary: toggle note display style for A/B comparison
    @State private var noteStyle: NoteDisplayStyle = .original

    var body: some View {
        NavigationStack {
            Group {
                if !feedService.hasLoadedOnce {
                    skeletonContent
                } else if feedService.feedEntries.isEmpty && feedService.isDiscoveryMode {
                    // Not following anyone and no public content to show
                    ScrollView {
                        discoveryEmptyState
                            .frame(maxWidth: .infinity, minHeight: 400)
                    }
                    .refreshable {
                        if let userID = authService.currentUser?.id {
                            await feedService.refreshFeed(for: userID)
                        }
                    }
                } else if feedService.feedEntries.isEmpty {
                    // Following people but they haven't posted
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
            .background(feedBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if feedService.hasLoadedOnce && (syncEngine.isSyncing || feedService.isLoading) {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                    }
                }

                // Temporary: note style picker for A/B comparison
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(NoteDisplayStyle.allCases) { style in
                            Button {
                                noteStyle = style
                            } label: {
                                HStack {
                                    Text(style.rawValue)
                                    if noteStyle == style {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(noteStyle.rawValue)
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(SonderColors.terracotta)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SonderColors.terracotta.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUserSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(SonderColors.inkMuted)
                            .toolbarIcon()
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
            .navigationDestination(item: $selectedTripID) { tripID in
                FeedTripDestination(tripID: tripID)
            }
            .task {
                await loadInitialData()
            }
            .onChange(of: popToRoot) {
                let hadActiveDestination = selectedUserID != nil || selectedFeedItem != nil || selectedTripID != nil
                selectedUserID = nil
                selectedFeedItem = nil
                selectedTripID = nil

                // If we're already at the feed root, tab re-tap should scroll to top.
                // If we're currently in a pushed destination, just pop back and keep position.
                if !hadActiveDestination {
                    scrollToTopTrigger = popToRoot
                }
            }
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        Text(greetingText)
            .font(SonderTypography.largeTitle)
            .foregroundStyle(SonderColors.inkDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, SonderSpacing.sm)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = authService.currentUser?.firstName
        let name = (firstName?.isEmpty == false ? firstName : nil) ?? "traveler"
        switch hour {
        case 5..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }

    // MARK: - Empty State (following people but they haven't posted)

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.lg) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [SonderColors.terracotta.opacity(0.15), SonderColors.ochre.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 160, height: 160)
                .overlay {
                    Image(systemName: "globe.europe.africa")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [SonderColors.terracotta, SonderColors.ochre],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(emptyIconScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        emptyIconScale = 1.08
                    }
                }
                .onDisappear { emptyIconScale = 1.0 }

            VStack(spacing: SonderSpacing.xs) {
                Text("Nothing here yet")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)

                Text("The people you follow haven't posted yet. Check back soon!")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SonderSpacing.xxl)
    }

    // MARK: - Discovery Empty State (no followers and no public content)

    private var discoveryEmptyState: some View {
        VStack(spacing: SonderSpacing.lg) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [SonderColors.terracotta.opacity(0.15), SonderColors.ochre.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 160, height: 160)
                .overlay {
                    Image(systemName: "globe.europe.africa")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [SonderColors.terracotta, SonderColors.ochre],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(emptyIconScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        emptyIconScale = 1.08
                    }
                }
                .onDisappear { emptyIconScale = 1.0 }

            VStack(spacing: SonderSpacing.xs) {
                Text("Your feed is waiting")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)

                Text("Follow friends to see their discoveries, favorite spots, and travel stories")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.xl)
            }

            Button {
                showUserSearch = true
            } label: {
                Text("Find Friends")
            }
            .buttonStyle(WarmButtonStyle())
            .padding(.top, SonderSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SonderSpacing.xxl)
    }

    // MARK: - Discovery Banner

    private var discoveryBanner: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))

            Text("Explore what travelers are sharing")
                .font(SonderTypography.caption)
                .fontWeight(.medium)

            Spacer()

            Button {
                showUserSearch = true
            } label: {
                Text("Find Friends")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(SonderColors.terracotta)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.terracotta.opacity(0.1))
        .foregroundStyle(SonderColors.terracotta)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Feed Content

    // MARK: - Skeleton Content

    private var skeletonContent: some View {
        ScrollView {
            LazyVStack(spacing: SonderSpacing.md) {
                greetingHeader
                ForEach(0..<3, id: \.self) { _ in
                    FeedItemCardSkeleton()
                }
            }
            .padding(SonderSpacing.md)
        }
        .scrollDisabled(true)
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: SonderSpacing.md) {
                greetingHeader
                    .id("feedTop")

                if feedService.isDiscoveryMode {
                    discoveryBanner
                }

                if !syncEngine.isOnline {
                    offlineBanner
                }

                if feedService.newPostsAvailable {
                    newPostsBanner
                }

                ForEach(Array(feedService.feedEntries.enumerated()), id: \.element.id) { index, entry in
                    switch entry {
                    case .trip(let tripItem):
                        TripFeedCard(
                            tripItem: tripItem,
                            onUserTap: {
                                selectedUserID = tripItem.user.id
                            },
                            onTripTap: {
                                selectedTripID = tripItem.id
                            }
                        )
                        .feedCardEntrance(index: index)
                    case .log(let feedItem):
                        FeedItemCard(
                            feedItem: feedItem,
                            onUserTap: {
                                selectedUserID = feedItem.user.id
                            },
                            onPlaceTap: {
                                selectedFeedItem = feedItem
                            },
                            noteStyle: noteStyle
                        )
                        .feedCardEntrance(index: index)
                    case .tripCreated(let item):
                        TripCreatedCard(item: item) {
                            selectedUserID = item.user.id
                        }
                        .feedCardEntrance(index: index)
                    }

                    // Auto-pagination: trigger loadMore when near the end of the list
                    if feedService.feedEntries.count >= 3, index >= feedService.feedEntries.count - 3,
                       feedService.hasMore,
                       !feedService.isLoading,
                       !feedService.isDiscoveryMode {
                        Color.clear.frame(height: 0)
                            .onAppear {
                                Task {
                                    if let userID = authService.currentUser?.id {
                                        await feedService.loadMoreFeed(for: userID)
                                    }
                                }
                            }
                    }
                }

                if feedService.isLoading && !feedService.feedEntries.isEmpty {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                        .padding()
                }
            }
            .padding(SonderSpacing.md)
        }
        .background(feedBackground)
        .refreshable {
            if let userID = authService.currentUser?.id {
                await feedService.refreshFeed(for: userID)
            }
        }
        .onChange(of: scrollToTopTrigger) { _, trigger in
            guard trigger != nil else { return }
            withAnimation {
                proxy.scrollTo("feedTop", anchor: .top)
            }
        }
        } // ScrollViewReader
    }

    // MARK: - Warm Journal Background

    /// Warm parchment-like gradient background for the travel journal feel
    private var feedBackground: some View {
        ZStack {
            SonderColors.cream

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: SonderColors.ochre.opacity(0.04), location: 0.4),
                    .init(color: SonderColors.terracotta.opacity(0.03), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { geo in
                RadialGradient(
                    colors: [
                        .clear,
                        SonderColors.warmGray.opacity(0.3)
                    ],
                    center: .center,
                    startRadius: geo.size.height * 0.3,
                    endRadius: geo.size.height * 0.7
                )
            }
        }
        .ignoresSafeArea()
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
        .foregroundStyle(SonderColors.ochre)
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
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        guard let userID = authService.currentUser?.id else { return }
        // Run all three in parallel — each independently fetches what it needs
        async let feedTask: () = feedService.loadFeed(for: userID)
        async let wantToGoTask: () = wantToGoService.syncWantToGo(for: userID)
        async let realtimeTask: () = feedService.subscribeToRealtimeUpdates(for: userID)
        _ = await (feedTask, wantToGoTask, realtimeTask)
    }

}

// MARK: - Card Entrance Animation

struct FeedCardEntranceModifier: ViewModifier {
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.95)
            .offset(y: hasAppeared ? 0 : 30)
            .onAppear {
                guard !hasAppeared else { return }
                let delay = Double(min(index, 6)) * 0.08
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay)) {
                    hasAppeared = true
                }
                if index < 8 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                        guard !Task.isCancelled else { return }
                        SonderHaptics.impact(.soft)
                    }
                }
            }
    }
}

extension View {
    func feedCardEntrance(index: Int) -> some View {
        modifier(FeedCardEntranceModifier(index: index))
    }
}

// MARK: - Trip Navigation Destination

/// Fetches a Trip by ID from SwiftData and shows TripDetailView
struct FeedTripDestination: View {
    let tripID: String
    @Environment(\.modelContext) private var modelContext
    @State private var trip: Trip?

    var body: some View {
        Group {
            if let trip {
                TripDetailView(trip: trip)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SonderColors.cream)
            }
        }
        .task {
            let id = tripID
            let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
            trip = try? modelContext.fetch(descriptor).first
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
