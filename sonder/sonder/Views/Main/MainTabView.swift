//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showLogFlow = false
    @State private var exploreFocusMyPlaces = false
    @State private var exploreHasSelection = false
    @State private var pendingPinDrop: CLLocationCoordinate2D?
    @State private var pendingLogCoord: CLLocationCoordinate2D?

    // Pop-to-root triggers: changing UUID causes .onChange to fire in child views
    @State private var feedPopTrigger = UUID()
    @State private var journalPopTrigger = UUID()
    @State private var profilePopTrigger = UUID()

    /// Tracks which tabs have been visited at least once so their views are kept alive.
    @State private var loadedTabs: Set<Int> = [0]

    var body: some View {
        ZStack {
            if loadedTabs.contains(0) {
                FeedView(popToRoot: feedPopTrigger)
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)
            }

            if loadedTabs.contains(1) {
                ExploreMapView(focusMyPlaces: $exploreFocusMyPlaces, hasSelection: $exploreHasSelection, pendingPinDrop: $pendingPinDrop)
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
            }

            if loadedTabs.contains(2) {
                JournalContainerView(popToRoot: journalPopTrigger)
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)
            }

            if loadedTabs.contains(3) {
                ProfileView(selectedTab: $selectedTab, exploreFocusMyPlaces: $exploreFocusMyPlaces, popToRoot: profilePopTrigger)
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            loadedTabs.insert(newTab)
        }
        .toolbarColorScheme(.light, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            SonderTabBar(
                selectedTab: $selectedTab,
                onLogTap: { showLogFlow = true },
                onSameTabTap: { tab in
                    switch tab {
                    case 0: feedPopTrigger = UUID()
                    case 2: journalPopTrigger = UUID()
                    case 3: profilePopTrigger = UUID()
                    default: break
                    }
                }
            )
        }
        .overlay(alignment: .bottom) {
            PendingSyncOverlay()
                .padding(.bottom, 60)
        }
        .overlay(alignment: .top) {
            PhotoUploadBannerOverlay()
        }
        .fullScreenCover(isPresented: $showLogFlow, onDismiss: {
            guard let coord = pendingLogCoord else { return }
            pendingLogCoord = nil
            pendingPinDrop = coord
        }) {
            SearchPlaceView { coord in
                pendingLogCoord = coord
                selectedTab = 1
                showLogFlow = false
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct SonderTabBar: View {
    @Binding var selectedTab: Int
    let onLogTap: () -> Void
    var onSameTabTap: ((Int) -> Void)? = nil

    @Namespace private var pillAnimation
    /// Local visual state — animated independently so the TabView content swap stays instant.
    @State private var visualTab: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "bubble.left.and.bubble.right", label: "Feed", tag: 0)
            tabButton(icon: "safari", label: "Explore", tag: 1)
            logButton
            tabButton(icon: "book.closed", label: "Journal", tag: 2)
            tabButton(icon: "person", label: "Profile", tag: 3)
        }
        .padding(.top, SonderSpacing.xxs)
        .padding(.bottom, SonderSpacing.xxs)
        .offset(y: 16)
        .onAppear { visualTab = selectedTab }
        .onChange(of: selectedTab) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                visualTab = newValue
            }
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(SonderColors.cream.opacity(0.7))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Gradient fade above the bar — content dissolves into it
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [SonderColors.cream.opacity(0), SonderColors.cream.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 24)
            .offset(y: -24)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Tab Button

    private func tabButton(icon: String, label: String, tag: Int) -> some View {
        let isSelected = visualTab == tag

        return Button {
            if selectedTab == tag {
                onSameTabTap?(tag)
            } else {
                selectedTab = tag
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: SonderSpacing.xxs) {
                ZStack {
                    // Sliding selection pill
                    if isSelected {
                        Capsule()
                            .fill(SonderColors.terracotta.opacity(0.15))
                            .frame(width: 52, height: 30)
                            .matchedGeometryEffect(id: "tabPill", in: pillAnimation)
                    }

                    Image(systemName: icon)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 20))
                        .frame(width: 52, height: 30)
                }

                Text(label)
                    .font(.system(size: 10, design: .rounded))
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(isSelected ? SonderColors.terracotta : SonderColors.inkLight)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Elevated Log Button

    private var logButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLogTap()
        } label: {
            VStack(spacing: SonderSpacing.xxs) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SonderColors.terracotta, SonderColors.terracotta.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, x: 0, y: 3)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Log")
                    .font(.system(size: 10, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.terracotta)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -16)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.9))
    }
}

// MARK: - Pending Sync Badge Overlay

/// Isolated sub-view so SyncEngine observation doesn't re-render MainTabView.
struct PendingSyncOverlay: View {
    @Environment(SyncEngine.self) private var syncEngine
    @State private var showSyncAlert = false

    var body: some View {
        Group {
            if syncEngine.pendingCount > 0 {
                HStack {
                    Spacer()
                    Button { showSyncAlert = true } label: {
                        PendingSyncBadge(count: syncEngine.pendingCount)
                    }
                    .buttonStyle(.plain)
                        .padding(.trailing, 16)
                }
                .padding(.bottom, 56)
            }
        }
        .alert("\(syncEngine.pendingCount) log\(syncEngine.pendingCount == 1 ? "" : "s") stuck", isPresented: $showSyncAlert) {
            Button("Retry Sync") {
                Task { await syncEngine.forceSyncNow() }
            }
            Button("Dismiss", role: .destructive) {
                syncEngine.dismissStuckLogs()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("These logs failed to sync to the server. You can retry or dismiss them to clear the badge.")
        }
    }
}

// MARK: - Photo Upload Banner Overlay

/// Isolated sub-view so PhotoService observation doesn't re-render MainTabView.
struct PhotoUploadBannerOverlay: View {
    @Environment(PhotoService.self) private var photoService

    var body: some View {
        Group {
            if photoService.hasActiveUploads {
                PhotoUploadBanner(
                    completed: photoService.totalPhotosInFlight - photoService.totalPendingPhotos,
                    total: photoService.totalPhotosInFlight,
                    progress: photoService.overallProgress
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: photoService.hasActiveUploads)
    }
}

// MARK: - Photo Upload Banner

struct PhotoUploadBanner: View {
    let completed: Int
    let total: Int
    let progress: Double

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(SonderColors.terracotta.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(SonderColors.terracotta, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SonderColors.terracotta)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Uploading photos...")
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.inkDark)
                Text("\(completed) of \(total)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }

            Spacer()
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.sm)
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
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
                        .scrollDismissesKeyboard(.interactively)
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
        let dict = placesByID
        return logs.filter { log in
            // Search filter
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                let searchLower = searchText.lowercased()
                let p = dict[log.placeID]
                let placeName = p?.name.lowercased() ?? ""
                let placeAddress = p?.address.lowercased() ?? ""
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
            let matchesTag = selectedTagFilter.map { log.tags.contains($0) } ?? true

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
                    ForEach(tripLogs.sorted {
                        if let a = $0.tripSortOrder, let b = $1.tripSortOrder {
                            return b < a
                        }
                        return $0.visitedAt > $1.visitedAt
                    }, id: \.id) { log in
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

        // Logs without trips (including stale tripIDs pointing to deleted trips)
        let tripIDs = Set(trips.map(\.id))
        let unassignedLogs = filteredLogs.filter { $0.hasNoTrip || !tripIDs.contains($0.tripID!) }
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

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var tripsByID: [String: Trip] {
        Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
    }

    private func place(for log: Log) -> Place? {
        placesByID[log.placeID]
    }

    private func trip(for log: Log) -> Trip? {
        guard let tripID = log.tripID else { return nil }
        return tripsByID[tripID]
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

// ProfileView is now in Views/Profile/ProfileView.swift
// FilteredLogsListView, JourneyStatCard, WarmFlowLayoutTags, StatCard also moved there

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
                Section {
                    if let user = authService.currentUser {
                        settingsRow(label: "Username", value: user.username)

                        Button {
                            editedEmail = user.email ?? ""
                            showEditEmailAlert = true
                        } label: {
                            settingsRow(label: "Email", value: user.email ?? "Not set")
                        }
                    }
                } header: {
                    settingsSectionHeader("Account")
                }
                .listRowBackground(SonderColors.warmGray)

                // Notifications section
                Section {
                    Toggle(isOn: $proximityAlertsEnabled) {
                        Label {
                            Text("Nearby Place Alerts")
                                .font(SonderTypography.body)
                                .foregroundColor(SonderColors.inkDark)
                        } icon: {
                            Image(systemName: "location.fill")
                                .foregroundColor(SonderColors.terracotta)
                        }
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
                    settingsSectionHeader("Notifications")
                } footer: {
                    Text("Get notified when you're near a place on your Want to Go list")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkLight)
                }
                .listRowBackground(SonderColors.warmGray)

                // Privacy section
                Section {
                    NavigationLink {
                        Text("Privacy Policy")
                            .navigationTitle("Privacy Policy")
                    } label: {
                        Label {
                            Text("Privacy Policy")
                                .font(SonderTypography.body)
                                .foregroundColor(SonderColors.inkDark)
                        } icon: {
                            Image(systemName: "hand.raised")
                                .foregroundColor(SonderColors.terracotta)
                        }
                    }

                    NavigationLink {
                        Text("Terms of Service")
                            .navigationTitle("Terms of Service")
                    } label: {
                        Label {
                            Text("Terms of Service")
                                .font(SonderTypography.body)
                                .foregroundColor(SonderColors.inkDark)
                        } icon: {
                            Image(systemName: "doc.text")
                                .foregroundColor(SonderColors.terracotta)
                        }
                    }
                } header: {
                    settingsSectionHeader("Privacy")
                }
                .listRowBackground(SonderColors.warmGray)

                // Data section
                Section {
                    Button {
                        showClearCacheAlert = true
                    } label: {
                        Label {
                            Text("Clear Cache")
                                .font(SonderTypography.body)
                                .foregroundColor(SonderColors.terracotta)
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundColor(SonderColors.terracotta)
                        }
                    }
                } header: {
                    settingsSectionHeader("Data")
                }
                .listRowBackground(SonderColors.warmGray)

                // About section
                Section {
                    settingsRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    settingsRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                } header: {
                    settingsSectionHeader("About")
                }
                .listRowBackground(SonderColors.warmGray)

                // Sign out section
                Section {
                    Button {
                        showSignOutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(SonderTypography.headline)
                                .foregroundColor(SonderColors.dustyRose)
                            Spacer()
                        }
                    }
                }
                .listRowBackground(SonderColors.warmGray)
            }
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.colorScheme, .light)
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

    // MARK: - Settings Helpers

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SonderTypography.caption)
            .foregroundColor(SonderColors.terracotta)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkDark)
            Spacer()
            Text(value)
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
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
