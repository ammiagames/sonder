//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import MapKit

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showLogFlow = false
    @Environment(SyncEngine.self) private var syncEngine

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                SocialFeedView()
                    .tabItem {
                        Label("Feed", systemImage: "square.grid.2x2")
                    }
                    .tag(0)

                MapView()
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                    .tag(1)

                JournalView()
                    .tabItem {
                        Label("Journal", systemImage: "book.closed")
                    }
                    .tag(2)

                ProfileView(selectedTab: $selectedTab)
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(3)
            }

            // FAB for Feed, Map, and Trips tabs
            if selectedTab == 0 || selectedTab == 1 || selectedTab == 2 {
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

// MapView is now implemented in LogMapView.swift
// This typealias maintains compatibility with existing code
typealias MapView = LogMapView

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
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            photoPlaceholder
                                .overlay { ProgressView() }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            PlacePhotoView(photoReference: place?.photoReference, size: 56)
                        @unknown default:
                            photoPlaceholder
                        }
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
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    @Binding var selectedTab: Int

    /// Logs filtered to current user only
    private var logs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Map
                    heroMap

                    VStack(spacing: SonderSpacing.lg) {
                        // Profile header (avatar + username + bio)
                        profileHeader

                        // Social stats (followers/following)
                        socialStatsSection

                        // Journey stats (only show if has logs)
                        if !logs.isEmpty {
                            journeyStatsSection
                        }

                        // Want to Go link
                        wantToGoLink
                    }
                    .padding(SonderSpacing.md)
                }
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Your Journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(SonderColors.inkMuted)
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

    private var heroMap: some View {
        ZStack(alignment: .bottom) {
            heroMapContent
                .frame(height: 220)
                .allowsHitTesting(false) // Disable map interaction, just visual

            // Warm gradient overlay at bottom for text legibility
            LinearGradient(
                colors: [.clear, SonderColors.cream.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)

            // Places count badge with tap to view map
            HStack(spacing: SonderSpacing.xs) {
                if logs.isEmpty {
                    Image(systemName: "map")
                        .foregroundColor(SonderColors.inkMuted)
                    Text("Start your journey!")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(SonderColors.terracotta)
                    Text("\(logs.count) places in your journal")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkDark)

                    Text("•")
                        .foregroundColor(SonderColors.inkLight)

                    Text("View map")
                        .font(SonderTypography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(SonderColors.terracotta)
                }
            }
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xs)
            .background(SonderColors.cream.opacity(0.95))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .padding(.bottom, SonderSpacing.sm)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !logs.isEmpty {
                selectedTab = 1 // Switch to Map tab
            }
        }
        .onAppear {
            updateMapRegion()
        }
    }

    private var heroMapContent: some View {
        Map(position: $mapCameraPosition) {
            ForEach(userPlaces, id: \.id) { place in
                if let log = logs.first(where: { $0.placeID == place.id }) {
                    Annotation(place.name, coordinate: place.coordinate) {
                        Circle()
                            .fill(pinColor(for: log.rating))
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            }
                            .shadow(radius: 2)
                    }
                }
            }
        }
    }

    private func updateMapRegion() {
        guard !userPlaces.isEmpty else { return }

        let coordinates = userPlaces.map { $0.coordinate }

        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLng = coordinates.map(\.longitude).min() ?? 0
        let maxLng = coordinates.map(\.longitude).max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )

        let latDelta = max((maxLat - minLat) * 1.5, 0.05)
        let lngDelta = max((maxLng - minLng) * 1.5, 0.05)

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )

        mapCameraPosition = .region(region)
    }

    private func pinColor(for rating: Rating) -> Color {
        switch rating {
        case .skip: return SonderColors.ratingSkip
        case .solid: return SonderColors.ratingSolid
        case .mustSee: return SonderColors.ratingMustSee
        }
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
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                avatarPlaceholder
                                    .overlay {
                                        ProgressView()
                                            .tint(SonderColors.terracotta)
                                    }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                avatarPlaceholder
                            @unknown default:
                                avatarPlaceholder
                            }
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

    // MARK: - Journey Stats Section

    private var journeyStatsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Your journey so far")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: SonderSpacing.sm) {
                JourneyStatCard(
                    value: "\(logs.count)",
                    label: "Places",
                    icon: "mappin.circle.fill",
                    color: SonderColors.terracotta
                )

                JourneyStatCard(
                    value: "\(uniqueCities.count)",
                    label: "Cities",
                    icon: "building.2.fill",
                    color: SonderColors.sage
                )

                JourneyStatCard(
                    value: "\(uniqueCountries.count)",
                    label: "Countries",
                    icon: "globe.americas.fill",
                    color: SonderColors.warmBlue
                )
            }
        }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
