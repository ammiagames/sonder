//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import PhotosUI

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

                LogsView()
                    .tabItem {
                        Label("Logs", systemImage: "book")
                    }
                    .tag(2)

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(3)
            }

            // FAB for Feed and Map tabs
            if selectedTab == 0 || selectedTab == 1 {
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
                        ContentUnavailableView(
                            "No Logs Yet",
                            systemImage: "book.closed",
                            description: Text("Tap the + button to log your first place")
                        )
                    } else if filteredLogs.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try adjusting your filters or search")
                        )
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
                .foregroundColor(.secondary)

            TextField("Search places, notes, tags...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        label: "#\(tag)",
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
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
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
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Place name
                Text(place?.name ?? "Unknown Place")
                    .font(.headline)
                    .lineLimit(1)

                // Address
                if let address = place?.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Note preview
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Date and trip
                HStack(spacing: 4) {
                    Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let trip = trip {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(trip.name)
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
    }
}

struct ProfileView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(PhotoService.self) private var photoService
    @Environment(SocialService.self) private var socialService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [Log]
    @Query private var places: [Place]

    @State private var showSettings = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var wantToGoCount = 0

    /// Logs filtered to current user only
    private var logs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile header
                    profileHeader

                    // Social stats (followers/following)
                    socialStatsSection

                    // Stats grid
                    statsGrid

                    // Want to Go link
                    wantToGoLink

                    // Rating breakdown
                    ratingBreakdown

                    // Top tags
                    if !topTags.isEmpty {
                        topTagsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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
        HStack(spacing: 40) {
            NavigationLink {
                FollowListView(
                    userID: authService.currentUser?.id ?? "",
                    username: authService.currentUser?.username ?? "",
                    initialTab: .followers
                )
            } label: {
                VStack(spacing: 4) {
                    if socialService.countsLoaded {
                        Text("\(socialService.followerCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    } else {
                        ProgressView()
                            .frame(height: 28)
                    }
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                FollowListView(
                    userID: authService.currentUser?.id ?? "",
                    username: authService.currentUser?.username ?? "",
                    initialTab: .following
                )
            } label: {
                VStack(spacing: 4) {
                    if socialService.countsLoaded {
                        Text("\(socialService.followingCount)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    } else {
                        ProgressView()
                            .frame(height: 28)
                    }
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.accentColor)
                Text("Want to Go")
                    .fontWeight(.medium)
                Spacer()
                if wantToGoCount > 0 {
                    Text("\(wantToGoCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar (tappable to change)
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    if let urlString = authService.currentUser?.avatarURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                avatarPlaceholder
                                    .overlay { ProgressView() }
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
                    } else {
                        avatarPlaceholder
                    }

                    // Upload indicator
                    if isUploadingPhoto {
                        Color.black.opacity(0.5)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    // Camera badge (outside clip)
                    if !isUploadingPhoto {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .offset(x: 2, y: 2)
                    }
                }
            }
            .disabled(isUploadingPhoto)

            // Username
            Text(authService.currentUser?.username ?? "User")
                .font(.title2)
                .fontWeight(.bold)

            // Member since
            if let user = authService.currentUser {
                Text("Exploring since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                await uploadProfilePhoto(from: newValue)
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .overlay {
                Text(authService.currentUser?.username.prefix(1).uppercased() ?? "?")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
    }

    private func uploadProfilePhoto(from item: PhotosPickerItem?) async {
        guard let item = item,
              let user = authService.currentUser else { return }

        await MainActor.run { isUploadingPhoto = true }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Upload to Supabase
                if let photoURL = await photoService.uploadPhoto(image, for: user.id) {
                    // Update user's avatar URL
                    user.avatarURL = photoURL
                    user.updatedAt = Date()

                    try modelContext.save()

                    // Sync to Supabase
                    await syncEngine.syncNow()

                    // Haptic feedback
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                }
            }
        } catch {
            print("Failed to upload profile photo: \(error)")
        }

        await MainActor.run {
            isUploadingPhoto = false
            selectedPhotoItem = nil
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                value: "\(logs.count)",
                label: "Places",
                icon: "mappin.circle.fill",
                color: .blue
            )

            StatCard(
                value: "\(uniqueCities.count)",
                label: "Cities",
                icon: "building.2.fill",
                color: .purple
            )

            StatCard(
                value: "\(uniqueCountries.count)",
                label: "Countries",
                icon: "globe.americas.fill",
                color: .green
            )
        }
    }

    // MARK: - Rating Breakdown

    private var ratingBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating Breakdown")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(Rating.allCases, id: \.self) { rating in
                    let count = logs.filter { $0.rating == rating }.count
                    let percentage = logs.isEmpty ? 0 : Double(count) / Double(logs.count)

                    HStack {
                        Text(rating.emoji)
                            .font(.title3)

                        Text(rating.displayName)
                            .font(.subheadline)

                        Spacer()

                        Text("\(count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(ratingColor(for: rating))
                                .frame(width: geometry.size.width * percentage)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func ratingColor(for rating: Rating) -> Color {
        switch rating {
        case .skip: return .gray
        case .solid: return .blue
        case .mustSee: return .orange
        }
    }

    // MARK: - Top Tags

    private var topTagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Tags")
                .font(.headline)

            FlowLayoutTags(tags: topTags)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var topTags: [String] {
        let allTags = logs.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        return Array(tagCounts.prefix(10).map { $0.key })
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

// MARK: - Stat Card

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
    @Environment(\.modelContext) private var modelContext

    @State private var showSignOutAlert = false
    @State private var showClearCacheAlert = false
    @State private var showEditEmailAlert = false
    @State private var editedEmail = ""

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
