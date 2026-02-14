//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showLogFlow = false
    @State private var exploreFocusMyPlaces = false
    @State private var exploreHasSelection = false
    @Environment(SyncEngine.self) private var syncEngine

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                ExploreMapView(focusMyPlaces: $exploreFocusMyPlaces, hasSelection: $exploreHasSelection)
                    .tabItem {
                        Label("Explore", systemImage: "safari")
                    }
                    .tag(0)

                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "bubble.left.and.bubble.right")
                    }
                    .tag(1)

                JournalContainerView()
                    .tabItem {
                        Label("Journal", systemImage: "book.closed")
                    }
                    .tag(2)

                ProfileView(selectedTab: $selectedTab, exploreFocusMyPlaces: $exploreFocusMyPlaces)
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(3)
            }
            .tint(SonderColors.terracotta)
            .toolbarBackground(SonderColors.cream, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .tabBar)
            .toolbarColorScheme(.light, for: .navigationBar)

            // FAB for explore, feed, and journal tabs (hidden when explore card is showing)
            if selectedTab <= 2 && !(selectedTab == 0 && exploreHasSelection) {
                VStack(spacing: 8) {
                    // Pending sync indicator
                    if syncEngine.pendingCount > 0 {
                        PendingSyncBadge(count: syncEngine.pendingCount)
                    }

                    FloatingActionButton {
                        showLogFlow = true
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 80) // Above tab bar
            }
        }
        .fullScreenCover(isPresented: $showLogFlow) {
            SearchPlaceView()
        }
    }
}

// Note: FeedView is now imported from Views/Feed/FeedView.swift
// The SocialFeedView typealias provides backward compatibility
typealias SocialFeedView = FeedView

// ExploreMapView is the unified map in Tab 1 (personal + social)

struct LogsView: View {
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query private var places: [Place]
    @Query private var trips: [Trip]

    @Environment(AuthenticationService.self) private var authService

    @State private var groupByTrip = false
    @State private var searchText = ""
    @State private var selectedRatingFilter: Rating?
    @State private var selectedTagFilter: String?

    /// Logs filtered to current user only
    private var logs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                if !logs.isEmpty {
                    searchBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Filter chips
                    filterChips
                        .padding(.top, 8)
                }

                // Content
                Group {
                    if logs.isEmpty {
                        VStack(spacing: SonderSpacing.md) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 48))
                                .foregroundColor(SonderColors.inkLight)
                            Text("No Logs Yet")
                                .font(SonderTypography.title)
                                .foregroundColor(SonderColors.inkDark)
                            Text("Tap the + button to log your first place")
                                .font(SonderTypography.body)
                                .foregroundColor(SonderColors.inkMuted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredLogs.isEmpty {
                        VStack(spacing: SonderSpacing.md) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(SonderColors.inkLight)
                            Text("No Results")
                                .font(SonderTypography.title)
                                .foregroundColor(SonderColors.inkDark)
                            Text("Try adjusting your filters or search")
                                .font(SonderTypography.body)
                                .foregroundColor(SonderColors.inkMuted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            if groupByTrip {
                                groupedByTripContent
                            } else {
                                chronologicalContent
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("View") {
                            Button {
                                groupByTrip = false
                            } label: {
                                HStack {
                                    Text("Chronological")
                                    if !groupByTrip {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button {
                                groupByTrip = true
                            } label: {
                                HStack {
                                    Text("Group by Trip")
                                    if groupByTrip {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        if hasActiveFilters {
                            Section {
                                Button(role: .destructive) {
                                    clearFilters()
                                } label: {
                                    Label("Clear Filters", systemImage: "xmark.circle")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SonderColors.inkMuted)

            TextField("Search places, notes, tags...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SonderColors.inkMuted)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Rating filters
                ForEach(Rating.allCases, id: \.self) { rating in
                    FilterChip(
                        label: rating.emoji,
                        isSelected: selectedRatingFilter == rating
                    ) {
                        if selectedRatingFilter == rating {
                            selectedRatingFilter = nil
                        } else {
                            selectedRatingFilter = rating
                        }
                    }
                }

                // Divider
                if !allTags.isEmpty {
                    Divider()
                        .frame(height: 24)
                }

                // Tag filters (top 5 most used)
                ForEach(topTags, id: \.self) { tag in
                    FilterChip(
                        label: tag,
                        isSelected: selectedTagFilter == tag
                    ) {
                        if selectedTagFilter == tag {
                            selectedTagFilter = nil
                        } else {
                            selectedTagFilter = tag
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Filtered Logs

    private var filteredLogs: [Log] {
        logs.filter { log in
            // Search filter
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                let searchLower = searchText.lowercased()
                let placeName = place(for: log)?.name.lowercased() ?? ""
                let placeAddress = place(for: log)?.address.lowercased() ?? ""
                let note = log.note?.lowercased() ?? ""
                let tags = log.tags.joined(separator: " ").lowercased()

                matchesSearch = placeName.contains(searchLower) ||
                               placeAddress.contains(searchLower) ||
                               note.contains(searchLower) ||
                               tags.contains(searchLower)
            }

            // Rating filter
            let matchesRating = selectedRatingFilter == nil || log.rating == selectedRatingFilter

            // Tag filter
            let matchesTag = selectedTagFilter == nil || log.tags.contains(selectedTagFilter!)

            return matchesSearch && matchesRating && matchesTag
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedRatingFilter != nil || selectedTagFilter != nil
    }

    private func clearFilters() {
        searchText = ""
        selectedRatingFilter = nil
        selectedTagFilter = nil
    }

    // MARK: - Tags

    private var allTags: [String] {
        logs.flatMap { $0.tags }
    }

    private var topTags: [String] {
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        return Array(tagCounts.prefix(5).map { $0.key })
    }

    // MARK: - Chronological View

    @ViewBuilder
    private var chronologicalContent: some View {
        ForEach(filteredLogs, id: \.id) { log in
            if let place = place(for: log) {
                NavigationLink {
                    LogDetailView(log: log, place: place)
                } label: {
                    LogRow(log: log, place: place, trip: trip(for: log))
                }
            }
        }
    }

    // MARK: - Grouped by Trip View

    @ViewBuilder
    private var groupedByTripContent: some View {
        // Logs with trips
        let logsByTrip = Dictionary(grouping: filteredLogs.filter { $0.tripID != nil }) { $0.tripID! }

        ForEach(trips.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }, id: \.id) { trip in
            if let tripLogs = logsByTrip[trip.id], !tripLogs.isEmpty {
                Section(trip.name) {
                    ForEach(tripLogs.sorted { $0.createdAt > $1.createdAt }, id: \.id) { log in
                        if let place = place(for: log) {
                            NavigationLink {
                                LogDetailView(log: log, place: place)
                            } label: {
                                LogRow(log: log, place: place, trip: nil)
                            }
                        }
                    }
                }
            }
        }

        // Logs without trips
        let unassignedLogs = filteredLogs.filter { $0.tripID == nil }
        if !unassignedLogs.isEmpty {
            Section("No Trip") {
                ForEach(unassignedLogs.sorted { $0.createdAt > $1.createdAt }, id: \.id) { log in
                    if let place = place(for: log) {
                        NavigationLink {
                            LogDetailView(log: log, place: place)
                        } label: {
                            LogRow(log: log, place: place, trip: nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func place(for log: Log) -> Place? {
        places.first { $0.id == log.placeID }
    }

    private func trip(for log: Log) -> Trip? {
        guard let tripID = log.tripID else { return nil }
        return trips.first { $0.id == tripID }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SonderTypography.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, SonderSpacing.sm)
                .padding(.vertical, SonderSpacing.xs)
                .background(isSelected ? SonderColors.terracotta : SonderColors.warmGray)
                .foregroundColor(isSelected ? .white : SonderColors.inkDark)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Row

struct LogRow: View {
    let log: Log
    let place: Place?
    let trip: Trip?

    var body: some View {
        HStack(spacing: 12) {
            // Photo: user's photo first, then place photo, then placeholder
            ZStack(alignment: .bottomTrailing) {
                if let userPhotoURL = log.photoURL, let url = URL(string: userPhotoURL) {
                    // User's uploaded photo
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) {
                        photoPlaceholder
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Fall back to place photo
                    PlacePhotoView(photoReference: place?.photoReference, size: 56)
                }

                // Rating badge overlay
                Text(log.rating.emoji)
                    .font(.system(size: 16))
                    .padding(2)
                    .background(SonderColors.cream)
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Place name
                Text(place?.name ?? "Unknown Place")
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                // Address
                if let address = place?.address {
                    Text(address)
                        .font(SonderTypography.subheadline)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }

                // Note preview
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(2)
                }

                // Date and trip
                HStack(spacing: 4) {
                    Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(SonderColors.inkLight)

                    if let trip = trip {
                        Text("•")
                            .foregroundColor(SonderColors.inkLight)
                        Text(trip.name)
                            .font(.caption2)
                            .foregroundColor(SonderColors.terracotta)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }
}

struct ProfileView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(SocialService.self) private var socialService
    @Environment(WantToGoService.self) private var wantToGoService
    @Query private var allLogs: [Log]
    @Query private var places: [Place]

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showShareProfile = false
    @State private var wantToGoCount = 0

    @Binding var selectedTab: Int
    @Binding var exploreFocusMyPlaces: Bool

    /// Logs filtered to current user only
    private var logs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.lg) {
                    // Profile header (avatar + username + bio)
                    profileHeader

                    // Social stats (followers/following)
                    socialStatsSection

                    // Journey stats (only show if has logs)
                    if !logs.isEmpty {
                        heroStatSection

                        ratingBreakdownSection

                        if !topTags.isEmpty {
                            youLoveSection
                        }

                        recentActivitySection
                    }

                    // City breakdown options for comparison
                    if uniqueCities.count > 1 {
                        cityOption6_PhotoCards
                        cityOption7_PhotoMosaic
                    }

                    // View My Map
                    viewMyMapBanner

                    // Want to Go link
                    wantToGoLink
                }
                .padding(SonderSpacing.md)
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Your Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(SonderColors.inkDark)
                    }
                }
            }
            .tint(SonderColors.terracotta)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showShareProfile) {
                ShareProfileCardView(
                    placesCount: logs.count,
                    citiesCount: uniqueCities.count,
                    countriesCount: uniqueCountries.count,
                    topTags: topTagsForShare,
                    mustSeeCount: logs.filter { $0.rating == .mustSee }.count
                )
            }
            .refreshable {
                await syncEngine.forceSyncNow()
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                }
            }
            .task {
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                }
            }
        }
    }

    // MARK: - Social Stats Section

    private var socialStatsSection: some View {
        HStack(spacing: SonderSpacing.xxl) {
            NavigationLink {
                FollowListView(
                    userID: authService.currentUser?.id ?? "",
                    username: authService.currentUser?.username ?? "",
                    initialTab: .followers
                )
            } label: {
                VStack(spacing: SonderSpacing.xxs) {
                    if socialService.countsLoaded {
                        Text("\(socialService.followerCount)")
                            .font(SonderTypography.title)
                            .foregroundColor(SonderColors.inkDark)
                    } else {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .frame(height: 28)
                    }
                    Text("Followers")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
            }
            .buttonStyle(.plain)

            // Divider dot
            Circle()
                .fill(SonderColors.inkLight)
                .frame(width: 4, height: 4)

            NavigationLink {
                FollowListView(
                    userID: authService.currentUser?.id ?? "",
                    username: authService.currentUser?.username ?? "",
                    initialTab: .following
                )
            } label: {
                VStack(spacing: SonderSpacing.xxs) {
                    if socialService.countsLoaded {
                        Text("\(socialService.followingCount)")
                            .font(SonderTypography.title)
                            .foregroundColor(SonderColors.inkDark)
                    } else {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .frame(height: 28)
                    }
                    Text("Following")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Want to Go Link

    private var wantToGoLink: some View {
        NavigationLink {
            WantToGoListView()
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Bookmark icon with warm background
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16))
                    .foregroundColor(SonderColors.terracotta)
                    .frame(width: 36, height: 36)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Want to Go")
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)

                    if wantToGoCount > 0 {
                        Text("\(wantToGoCount) saved")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    } else {
                        Text("Save places to visit later")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SonderColors.inkLight)
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
        .buttonStyle(.plain)
        .task {
            await loadWantToGoCount()
        }
    }

    private func loadWantToGoCount() async {
        guard let userID = authService.currentUser?.id else { return }
        do {
            let items = try await wantToGoService.fetchWantToGoWithPlaces(for: userID)
            wantToGoCount = items.count
        } catch {
            print("Error loading want to go count: \(error)")
        }
    }

    // MARK: - Hero Map

    // MARK: - View My Map Banner

    private var viewMyMapBanner: some View {
        Button {
            if !logs.isEmpty {
                exploreFocusMyPlaces = true
                selectedTab = 0
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Map icon
                Image(systemName: "map.fill")
                    .font(.system(size: 20))
                    .foregroundColor(SonderColors.terracotta)
                    .frame(width: 40, height: 40)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    if logs.isEmpty {
                        Text("Your Map")
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.inkDark)
                        Text("Start logging places to see them on the map")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    } else {
                        Text("Your Map")
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.inkDark)
                        Text("\(logs.count) places logged")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }

                Spacer()

                if !logs.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(SonderColors.inkLight)
                }
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
        .buttonStyle(.plain)
        .disabled(logs.isEmpty)
    }

    // MARK: - Profile Header

    private var hasAvatarPhoto: Bool {
        authService.currentUser?.avatarURL != nil
    }

    private var profileHeader: some View {
        VStack(spacing: SonderSpacing.sm) {
            // Avatar (tappable to edit profile)
            Button {
                showEditProfile = true
            } label: {
                ZStack {
                    if let urlString = authService.currentUser?.avatarURL,
                       let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 100, height: 100)) {
                            avatarPlaceholder
                        }
                        .id(urlString) // Force refresh when URL changes
                    } else {
                        avatarPlaceholder
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(SonderColors.cream, lineWidth: 4)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    // Camera badge - only show when no photo
                    if !hasAvatarPhoto {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(SonderColors.terracotta)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(SonderColors.cream, lineWidth: 2)
                            }
                            .offset(x: 4, y: 4)
                    }
                }
            }
            .buttonStyle(.plain)

            // Username
            Text(authService.currentUser?.username ?? "User")
                .font(SonderTypography.largeTitle)
                .foregroundColor(SonderColors.inkDark)

            // Bio
            if let bio = authService.currentUser?.bio, !bio.isEmpty {
                Text(bio)
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.lg)
            }

            // Member since
            if let user = authService.currentUser {
                Text("Journaling since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
            }

            // Edit Profile & Share buttons
            HStack(spacing: SonderSpacing.sm) {
                Button {
                    showEditProfile = true
                } label: {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "pencil")
                        Text("Edit Profile")
                    }
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.inkDark)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(SonderColors.warmGray)
                    .clipShape(Capsule())
                }

                Button {
                    showShareProfile = true
                } label: {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.terracotta)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(SonderColors.terracotta.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, SonderSpacing.sm)
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
            .overlay {
                Text(authService.currentUser?.username.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Hero Stat Section

    private var heroStatSection: some View {
        VStack(spacing: SonderSpacing.xs) {
            Text("\(logs.count)")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundColor(SonderColors.inkDark)

            Text("places logged")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkMuted)

            // Breakdown line
            let parts: [String] = {
                var p: [String] = []
                if uniqueCities.count > 1 {
                    p.append("\(uniqueCities.count) cities")
                }
                if uniqueCountries.count > 1 {
                    p.append("\(uniqueCountries.count) countries")
                }
                return p
            }()

            if !parts.isEmpty {
                Text("across " + parts.joined(separator: " in "))
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
            }

            // Momentum indicator
            let thisMonthCount = logsThisMonth
            if thisMonthCount > 0 {
                Text("\(thisMonthCount) place\(thisMonthCount == 1 ? "" : "s") this month")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SonderColors.terracotta)
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xxs)
                    .background(SonderColors.terracotta.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.top, SonderSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SonderSpacing.lg)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Rating Breakdown Section

    private var ratingBreakdownSection: some View {
        let total = max(logs.count, 1)
        let mustSeeCount = logs.filter { $0.rating == .mustSee }.count
        let solidCount = logs.filter { $0.rating == .solid }.count
        let skipCount = logs.filter { $0.rating == .skip }.count

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Your ratings")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            // Horizontal stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if mustSeeCount > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SonderColors.ratingMustSee)
                            .frame(width: max(geo.size.width * CGFloat(mustSeeCount) / CGFloat(total), 8))
                    }
                    if solidCount > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SonderColors.ratingSolid)
                            .frame(width: max(geo.size.width * CGFloat(solidCount) / CGFloat(total), 8))
                    }
                    if skipCount > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SonderColors.ratingSkip)
                            .frame(width: max(geo.size.width * CGFloat(skipCount) / CGFloat(total), 8))
                    }
                }
            }
            .frame(height: 12)

            // Legend row
            HStack(spacing: SonderSpacing.md) {
                ratingLegendItem(emoji: Rating.mustSee.emoji, label: "Must-See", count: mustSeeCount)
                ratingLegendItem(emoji: Rating.solid.emoji, label: "Solid", count: solidCount)
                ratingLegendItem(emoji: Rating.skip.emoji, label: "Skip", count: skipCount)
                Spacer()
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    private func ratingLegendItem(emoji: String, label: String, count: Int) -> some View {
        HStack(spacing: SonderSpacing.xxs) {
            Text(emoji)
                .font(.system(size: 14))
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SonderColors.inkDark)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    // MARK: - You Love Section

    private var youLoveSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("You love")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            FlowLayoutWrapper {
                ForEach(topTags, id: \.self) { tag in
                    NavigationLink {
                        FilteredLogsListView(
                            title: tag,
                            logs: logsForTag(tag)
                        )
                    } label: {
                        HStack(spacing: SonderSpacing.xxs) {
                            Text(tag)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(SonderColors.terracotta)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(SonderColors.terracotta.opacity(0.6))
                        }
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xxs + 2)
                        .background(SonderColors.terracotta.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        let recentLogs = Array(logs.sorted { $0.createdAt > $1.createdAt }.prefix(3))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Recent activity")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(recentLogs, id: \.id) { log in
                if let place = places.first(where: { $0.id == log.placeID }) {
                    NavigationLink {
                        LogDetailView(log: log, place: place)
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Text(log.rating.emoji)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .background(SonderColors.pinColor(for: log.rating).opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SonderColors.inkDark)
                                    .lineLimit(1)

                                Text(log.createdAt.relativeDisplay)
                                    .font(.system(size: 12))
                                    .foregroundColor(SonderColors.inkLight)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(SonderColors.inkLight)
                        }
                    }
                    .buttonStyle(.plain)

                    if log.id != recentLogs.last?.id {
                        Divider()
                    }
                }
            }

            // "See all" link → switches to Journal tab
            if logs.count > 3 {
                Divider()

                Button {
                    selectedTab = 2
                } label: {
                    HStack {
                        Text("See all \(logs.count) logs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SonderColors.terracotta)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SonderColors.terracotta)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - City Data (shared)

    private var cityCounts: [(city: String, count: Int)] {
        var counts: [String: Int] = [:]
        for place in userPlaces {
            if let city = extractCity(from: place.address) {
                counts[city, default: 0] += 1
            }
        }
        return counts.map { (city: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - City Photo Helper

    /// Returns the best photo URL for a city: user's own photo first, then Google Places photo
    private func cityPhotoURL(_ city: String, maxWidth: Int = 400) -> URL? {
        let cityPlaces = userPlaces.filter { extractCity(from: $0.address) == city }
        let cityLogs = logs.filter { log in cityPlaces.contains(where: { $0.id == log.placeID }) }

        // 1. User's own log photo (most personal)
        if let userPhoto = cityLogs.sorted(by: { $0.createdAt > $1.createdAt })
            .first(where: { $0.photoURL != nil })?.photoURL,
           let url = URL(string: userPhoto) {
            return url
        }

        // 2. Google Places photo of the most-logged place in this city
        let placesByLogCount = cityPlaces.sorted { p1, p2 in
            cityLogs.filter { $0.placeID == p1.id }.count > cityLogs.filter { $0.placeID == p2.id }.count
        }
        if let ref = placesByLogCount.first(where: { $0.photoReference != nil })?.photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: maxWidth) {
            return url
        }

        return nil
    }

    // MARK: - Option 6: Photo Cards

    private var cityOption6_PhotoCards: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Option 6 — Photo Cards")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)

            Text("Your cities")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.sm) {
                    ForEach(Array(cityCounts.prefix(8).enumerated()), id: \.element.city) { index, item in
                        NavigationLink {
                            FilteredLogsListView(title: item.city, logs: logsForCity(item.city))
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                // Photo background or gradient fallback
                                if let url = cityPhotoURL(item.city) {
                                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 160, height: 200)) {
                                        cityPhotoFallback(index: index)
                                    }
                                    .frame(width: 160, height: 200)
                                    .clipped()
                                } else {
                                    cityPhotoFallback(index: index)
                                        .frame(width: 160, height: 200)
                                }

                                // Dark gradient overlay
                                LinearGradient(
                                    colors: [.clear, .clear, .black.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )

                                // Text overlay
                                VStack(alignment: .leading, spacing: 2) {
                                    Spacer()

                                    Text(item.city)
                                        .font(.system(size: 17, weight: .bold, design: .serif))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    Text("\(item.count) place\(item.count == 1 ? "" : "s")")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(SonderSpacing.sm)
                            }
                            .frame(width: 160, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SonderSpacing.xxs)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Option 7: Photo Mosaic

    private var cityOption7_PhotoMosaic: some View {
        let items = Array(cityCounts.prefix(5))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Option 7 — Photo Mosaic")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)

            Text("Your cities")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            if let hero = items.first {
                // Hero: full-width photo card for top city
                NavigationLink {
                    FilteredLogsListView(title: hero.city, logs: logsForCity(hero.city))
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        if let url = cityPhotoURL(hero.city, maxWidth: 600) {
                            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 180)) {
                                cityPhotoFallback(index: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()
                        } else {
                            cityPhotoFallback(index: 0)
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                        }

                        // Gradient overlay
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Spacer()

                            Text(hero.city)
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundColor(.white)

                            Text("\(hero.count) place\(hero.count == 1 ? "" : "s") logged")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(SonderSpacing.md)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }
                .buttonStyle(.plain)
            }

            // Rest: 2-column photo grid
            if items.count > 1 {
                let rest = Array(items.dropFirst())
                let columns = [
                    GridItem(.flexible(), spacing: SonderSpacing.xs),
                    GridItem(.flexible(), spacing: SonderSpacing.xs)
                ]

                LazyVGrid(columns: columns, spacing: SonderSpacing.xs) {
                    ForEach(Array(rest.enumerated()), id: \.element.city) { index, item in
                        NavigationLink {
                            FilteredLogsListView(title: item.city, logs: logsForCity(item.city))
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let url = cityPhotoURL(item.city) {
                                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 200, height: 120)) {
                                        cityPhotoFallback(index: index + 1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 100)
                                    .clipped()
                                } else {
                                    cityPhotoFallback(index: index + 1)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 100)
                                }

                                // Gradient
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.6)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )

                                VStack(alignment: .leading, spacing: 1) {
                                    Spacer()

                                    Text(item.city)
                                        .font(.system(size: 14, weight: .bold, design: .serif))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    Text("\(item.count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(SonderSpacing.sm)
                            }
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    /// Gradient fallback when no photo is available for a city
    private func cityPhotoFallback(index: Int) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        let grad = gradients[index % gradients.count]
        return LinearGradient(
            colors: [grad.0, grad.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Computed Stats

    /// Places that the current user has logged
    private var userPlaces: [Place] {
        let loggedPlaceIDs = Set(logs.map { $0.placeID })
        return places.filter { loggedPlaceIDs.contains($0.id) }
    }

    private var uniqueCities: Set<String> {
        Set(userPlaces.compactMap { extractCity(from: $0.address) })
    }

    private var uniqueCountries: Set<String> {
        Set(userPlaces.compactMap { extractCountry(from: $0.address) })
    }

    /// Top tags for the share card
    private var topTagsForShare: [String] {
        let allTags = logs.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return Array(tagCounts.prefix(4).map { $0.key })
    }

    /// Top tags for the profile "You love" section
    private var topTags: [String] {
        let allTags = logs.flatMap { $0.tags }
        guard !allTags.isEmpty else { return [] }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return Array(tagCounts.prefix(6).map { $0.key })
    }

    /// Number of logs created this calendar month
    private var logsThisMonth: Int {
        let now = Date()
        let calendar = Calendar.current
        return logs.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }.count
    }

    private func logsForTag(_ tag: String) -> [Log] {
        logs.filter { $0.tags.contains(tag) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func logsForCity(_ city: String) -> [Log] {
        logs.filter { log in
            guard let place = places.first(where: { $0.id == log.placeID }) else { return false }
            return extractCity(from: place.address) == city
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func extractCity(from address: String) -> String? {
        let components = address.components(separatedBy: ", ")
        guard components.count >= 2 else { return nil }
        // City is typically second-to-last component (before state/country)
        // Handle "City, State ZIP, Country" or "City, Country"
        if components.count >= 3 {
            return components[components.count - 3]
        }
        return components[0]
    }

    private func extractCountry(from address: String) -> String? {
        let components = address.components(separatedBy: ", ")
        guard let last = components.last else { return nil }
        // Remove any zip code if present
        let trimmed = last.trimmingCharacters(in: .whitespaces)
        // If it looks like a zip code or state abbreviation, use previous component
        if trimmed.count <= 2 || trimmed.allSatisfy({ $0.isNumber }) {
            return components.count >= 2 ? components[components.count - 2] : nil
        }
        return trimmed
    }
}

// MARK: - Filtered Logs List View

/// Reusable view showing a filtered list of logs (used by tag/city navigation on Profile)
struct FilteredLogsListView: View {
    let title: String
    let logs: [Log]
    @Query private var places: [Place]

    var body: some View {
        List {
            ForEach(logs, id: \.id) { log in
                if let place = places.first(where: { $0.id == log.placeID }) {
                    NavigationLink {
                        LogDetailView(log: log, place: place)
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Text(log.rating.emoji)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .background(SonderColors.pinColor(for: log.rating).opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SonderColors.inkDark)
                                    .lineLimit(1)

                                Text(place.address)
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.inkMuted)
                                    .lineLimit(1)

                                Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12))
                                    .foregroundColor(SonderColors.inkLight)
                            }

                            Spacer()
                        }
                    }
                    .listRowBackground(SonderColors.warmGray)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SonderColors.cream)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Journey Stat Card (Warm Style)

struct JourneyStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: SonderSpacing.xs) {
            // Icon with warm background
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            Text(value)
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text(label)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }
}

// MARK: - Warm Flow Layout Tags

struct WarmFlowLayoutTags: View {
    let tags: [String]

    var body: some View {
        FlowLayoutWrapper {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(SonderTypography.subheadline)
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(SonderColors.terracotta.opacity(0.12))
                    .foregroundColor(SonderColors.terracotta)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Stat Card (Legacy - keeping for compatibility)

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(ProximityNotificationService.self) private var proximityService
    @Environment(\.modelContext) private var modelContext

    @State private var showSignOutAlert = false
    @State private var showClearCacheAlert = false
    @State private var showEditEmailAlert = false
    @State private var editedEmail = ""
    @State private var proximityAlertsEnabled = false

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section("Account") {
                    if let user = authService.currentUser {
                        LabeledContent("Username", value: user.username)

                        Button {
                            editedEmail = user.email ?? ""
                            showEditEmailAlert = true
                        } label: {
                            HStack {
                                Text("Email")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(user.email ?? "Not set")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Notifications section
                Section {
                    Toggle(isOn: $proximityAlertsEnabled) {
                        Label("Nearby Place Alerts", systemImage: "location.fill")
                    }
                    .onChange(of: proximityAlertsEnabled) { _, newValue in
                        Task {
                            if newValue {
                                await proximityService.startMonitoring()
                            } else {
                                proximityService.stopMonitoring()
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified when you're near a place on your Want to Go list")
                }

                // Privacy section
                Section("Privacy") {
                    NavigationLink {
                        Text("Privacy Policy")
                            .navigationTitle("Privacy Policy")
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    NavigationLink {
                        Text("Terms of Service")
                            .navigationTitle("Terms of Service")
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                // Data section
                Section("Data") {
                    Button {
                        showClearCacheAlert = true
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                }

                // About section
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                // Sign out section
                Section {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .tint(SonderColors.terracotta)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await authService.signOut()
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Clear Cache", isPresented: $showClearCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("This will clear cached place data. Your logs will not be affected.")
            }
            .alert("Edit Email", isPresented: $showEditEmailAlert) {
                TextField("Email", text: $editedEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    saveEmail()
                }
            } message: {
                Text("Enter your email address")
            }
            .onAppear {
                proximityAlertsEnabled = proximityService.isMonitoring
            }
        }
    }

    private func saveEmail() {
        guard let user = authService.currentUser else { return }
        let trimmedEmail = editedEmail.trimmingCharacters(in: .whitespaces)

        user.email = trimmedEmail.isEmpty ? nil : trimmedEmail
        user.updatedAt = Date()

        try? modelContext.save()

        // Sync the update
        Task {
            await syncEngine.syncNow()
        }
    }

    private func clearCache() {
        // Clear recent searches
        do {
            let descriptor = FetchDescriptor<RecentSearch>()
            let searches = try modelContext.fetch(descriptor)
            for search in searches {
                modelContext.delete(search)
            }
            try modelContext.save()
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthenticationService())
}
