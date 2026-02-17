//
//  JournalView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData

enum JournalViewMode: String, CaseIterable {
    case list = "List"
    case grid = "Grid"

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

/// Unified journal view showing all user's logged places
struct JournalView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query private var places: [Place]

    // View state
    @State private var searchText = ""
    @State private var viewMode: JournalViewMode = .list
    @State private var selectedRatingFilter: Rating?
    @State private var selectedTagFilter: String?
    @State private var selectedTripFilter: Trip?
    @State private var showTripsSheet = false
    @State private var showCreateTrip = false
    @State private var pendingInvitationCount = 0
    @State private var selectedLog: Log?

    /// Logs filtered to current user
    private var userLogs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    /// Trips filtered to current user
    private var userTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
    }

    /// Filtered and searched logs
    private var filteredLogs: [Log] {
        var logs = userLogs

        // Search filter
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            logs = logs.filter { log in
                let place = places.first { $0.id == log.placeID }
                let placeName = place?.name.lowercased() ?? ""
                let placeAddress = place?.address.lowercased() ?? ""
                let note = log.note?.lowercased() ?? ""
                let tags = log.tags.joined(separator: " ").lowercased()

                return placeName.contains(searchLower) ||
                       placeAddress.contains(searchLower) ||
                       note.contains(searchLower) ||
                       tags.contains(searchLower)
            }
        }

        // Rating filter
        if let rating = selectedRatingFilter {
            logs = logs.filter { $0.rating == rating }
        }

        // Tag filter
        if let tag = selectedTagFilter {
            logs = logs.filter { $0.tags.contains(tag) }
        }

        // Trip filter
        if let trip = selectedTripFilter {
            logs = logs.filter { $0.tripID == trip.id }
        }

        return logs
    }

    /// Logs grouped by time period
    private var groupedLogs: [(String, [Log])] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [Log]] = [:]

        for log in filteredLogs {
            let key: String

            if calendar.isDateInToday(log.createdAt) {
                key = "Today"
            } else if calendar.isDateInYesterday(log.createdAt) {
                key = "Yesterday"
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      log.createdAt > weekAgo {
                key = "This Week"
            } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
                      log.createdAt > monthAgo {
                key = "This Month"
            } else {
                // Group by month/year
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                key = formatter.string(from: log.createdAt)
            }

            groups[key, default: []].append(log)
        }

        // Sort groups by most recent first
        let order = ["Today", "Yesterday", "This Week", "This Month"]
        return groups.sorted { a, b in
            let aIndex = order.firstIndex(of: a.key) ?? Int.max
            let bIndex = order.firstIndex(of: b.key) ?? Int.max

            if aIndex != Int.max || bIndex != Int.max {
                return aIndex < bIndex
            }

            // For month/year groups, sort by date
            let aDate = a.value.first?.createdAt ?? .distantPast
            let bDate = b.value.first?.createdAt ?? .distantPast
            return aDate > bDate
        }
    }

    /// All unique tags from user's logs
    private var allTags: [String] {
        let tags = userLogs.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: tags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return Array(tagCounts.prefix(10).map { $0.key })
    }

    private var hasActiveFilters: Bool {
        selectedRatingFilter != nil || selectedTagFilter != nil || selectedTripFilter != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if userLogs.isEmpty {
                    emptyState
                } else if filteredLogs.isEmpty {
                    VStack(spacing: 0) {
                        searchAndFilters
                        noResultsState
                    }
                } else {
                    logContent
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // View mode toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = viewMode == .list ? .grid : .list
                        }
                    } label: {
                        Image(systemName: viewMode.icon)
                            .foregroundColor(SonderColors.inkMuted)
                            .toolbarIcon()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: SonderSpacing.sm) {
                        // Trips button with badge
                        Button {
                            showTripsSheet = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "suitcase")
                                    .foregroundColor(SonderColors.inkMuted)

                                if pendingInvitationCount > 0 {
                                    Circle()
                                        .fill(SonderColors.terracotta)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 2, y: -2)
                                }
                            }
                            .toolbarIcon()
                        }
                    }
                }
            }
            .sheet(isPresented: $showTripsSheet) {
                TripsSheetView(
                    pendingInvitationCount: pendingInvitationCount,
                    onInvitationsViewed: {
                        Task { await loadInvitationCount() }
                    }
                )
            }
            .navigationDestination(item: $selectedLog) { log in
                if let place = places.first(where: { $0.id == log.placeID }) {
                    LogDetailView(log: log, place: place, onDelete: {
                        selectedLog = nil
                    })
                }
            }
            .task {
                await loadInvitationCount()
            }
        }
    }

    // MARK: - Search & Filters (inline)

    private var searchAndFilters: some View {
        VStack(spacing: SonderSpacing.xs) {
            searchBar
                .padding(.horizontal, SonderSpacing.md)

            filterChips
        }
        .padding(.top, SonderSpacing.xs)
        .padding(.bottom, SonderSpacing.sm)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SonderColors.inkLight)

            TextField("Search places, notes, tags...", text: $searchText)
                .font(SonderTypography.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SonderColors.inkLight)
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
            HStack(spacing: SonderSpacing.xs) {
                // Clear filters button (when active)
                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }

                // Rating filters
                ForEach(Rating.allCases, id: \.self) { rating in
                    FilterChipButton(
                        label: rating.emoji,
                        isSelected: selectedRatingFilter == rating
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRatingFilter = selectedRatingFilter == rating ? nil : rating
                        }
                    }
                }

                // Trip filters (as individual chips)
                if !userTrips.isEmpty {
                    Rectangle()
                        .fill(SonderColors.inkLight.opacity(0.5))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, SonderSpacing.xxs)

                    ForEach(userTrips, id: \.id) { trip in
                        FilterChipButton(
                            label: trip.name,
                            icon: "suitcase.fill",
                            isSelected: selectedTripFilter?.id == trip.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTripFilter = selectedTripFilter?.id == trip.id ? nil : trip
                            }
                        }
                    }
                }

                // Tag filters
                if !allTags.isEmpty {
                    Rectangle()
                        .fill(SonderColors.inkLight.opacity(0.5))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, SonderSpacing.xxs)

                    ForEach(allTags, id: \.self) { tag in
                        FilterChipButton(
                            label: tag,
                            isSelected: selectedTagFilter == tag
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTagFilter = selectedTagFilter == tag ? nil : tag
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SonderSpacing.md)
        }
    }

    private func clearFilters() {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedRatingFilter = nil
            selectedTagFilter = nil
            selectedTripFilter = nil
        }
    }

    // MARK: - Log Content

    @ViewBuilder
    private var logContent: some View {
        switch viewMode {
        case .list:
            listView
        case .grid:
            gridView
        }
    }

    private var listView: some View {
        List {
            // Search & filters as scrollable header
            Section {
                searchAndFilters
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(groupedLogs, id: \.0) { group, logs in
                Section {
                    ForEach(logs, id: \.id) { log in
                        if let place = places.first(where: { $0.id == log.placeID }) {
                            Button {
                                selectedLog = log
                            } label: {
                                JournalLogRow(
                                    log: log,
                                    place: place,
                                    tripName: tripName(for: log)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(
                                top: SonderSpacing.xs,
                                leading: SonderSpacing.md,
                                bottom: SonderSpacing.xs,
                                trailing: SonderSpacing.md
                            ))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteLog(log)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                logContextMenu(for: log)
                            }
                        }
                    }
                } header: {
                    Text(group)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .listRowInsets(EdgeInsets(
                            top: SonderSpacing.xs,
                            leading: SonderSpacing.md,
                            bottom: SonderSpacing.xs,
                            trailing: SonderSpacing.md
                        ))
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
    }

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SonderSpacing.md) {
                searchAndFilters

                ForEach(groupedLogs, id: \.0) { group, logs in
                    VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                        Text(group)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal, SonderSpacing.md)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: SonderSpacing.xs),
                            GridItem(.flexible(), spacing: SonderSpacing.xs),
                            GridItem(.flexible(), spacing: SonderSpacing.xs)
                        ], spacing: SonderSpacing.xs) {
                            ForEach(logs, id: \.id) { log in
                                if let place = places.first(where: { $0.id == log.placeID }) {
                                    Button {
                                        selectedLog = log
                                    } label: {
                                        JournalGridCell(log: log, place: place)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        logContextMenu(for: log)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, SonderSpacing.md)
                    }
                }
            }
            .padding(.top, SonderSpacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func logContextMenu(for log: Log) -> some View {
        if let place = places.first(where: { $0.id == log.placeID }) {
            Button {
                selectedLog = log
            } label: {
                Label("View Details", systemImage: "eye")
            }

            Divider()

            // Add to trip submenu
            if !userTrips.isEmpty {
                Menu {
                    Button {
                        removeFromTrip(log)
                    } label: {
                        Label("No Trip", systemImage: log.tripID == nil ? "checkmark" : "")
                    }

                    Divider()

                    ForEach(userTrips, id: \.id) { trip in
                        Button {
                            addToTrip(log, trip: trip)
                        } label: {
                            HStack {
                                Text(trip.name)
                                if log.tripID == trip.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add to Trip", systemImage: "suitcase")
                }
            }

            Button {
                shareLog(log, place: place)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                deleteLog(log)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            if syncEngine.isSyncing {
                ProgressView()
                    .tint(SonderColors.terracotta)

                Text("Syncing your journal...")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(SonderColors.inkLight)

                Text("Your Journal Awaits")
                    .font(SonderTypography.title)
                    .foregroundColor(SonderColors.inkDark)

                Text("Start logging places to build your personal travel journal")
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(SonderColors.inkLight)

            Text("No Results")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text("Try adjusting your search or filters")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)

            if hasActiveFilters {
                Button {
                    clearFilters()
                    searchText = ""
                } label: {
                    Text("Clear All")
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.terracotta)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func tripName(for log: Log) -> String? {
        guard let tripID = log.tripID else { return nil }
        return allTrips.first(where: { $0.id == tripID })?.name
    }

    private func loadInvitationCount() async {
        guard let userID = authService.currentUser?.id else { return }
        do {
            pendingInvitationCount = try await tripService.getPendingInvitationCount(for: userID)
        } catch {
            print("Error loading invitation count: \(error)")
        }
    }

    private func deleteLog(_ log: Log) {
        Task { await syncEngine.deleteLog(id: log.id) }
    }

    private func addToTrip(_ log: Log, trip: Trip) {
        log.tripID = trip.id
        log.updatedAt = Date()
        try? modelContext.save()
    }

    private func removeFromTrip(_ log: Log) {
        log.tripID = nil
        log.updatedAt = Date()
        try? modelContext.save()
    }

    private func shareLog(_ log: Log, place: Place) {
        let text = "Check out \(place.name)! \(log.rating.emoji)"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.keyWindow?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Filter Chip Button

struct FilterChipButton: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                }
                Text(label)
            }
            .font(SonderTypography.caption)
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

// MARK: - Journal Log Row

struct JournalLogRow: View {
    let log: Log
    let place: Place
    let tripName: String?

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo thumbnail
            photoView
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                // Place name + rating
                HStack {
                    Text(place.name)
                        .font(SonderTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    Spacer()

                    Text(log.rating.emoji)
                        .font(.system(size: 18))
                }

                // Note preview or address
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)
                } else {
                    Text(place.address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)
                }

                // Trip + date
                HStack(spacing: SonderSpacing.xs) {
                    if let tripName = tripName {
                        HStack(spacing: 2) {
                            Image(systemName: "suitcase.fill")
                                .font(.system(size: 9))
                            Text(tripName)
                        }
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.terracotta)
                    }

                    Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkLight)
                }

                // Tags
                if !log.tags.isEmpty {
                    HStack(spacing: SonderSpacing.xxs) {
                        ForEach(log.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SonderColors.terracotta.opacity(0.12))
                                .foregroundColor(SonderColors.terracotta)
                                .clipShape(Capsule())
                        }
                        if log.tags.count > 3 {
                            Text("+\(log.tags.count - 3)")
                                .font(.system(size: 10))
                                .foregroundColor(SonderColors.inkLight)
                        }
                    }
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 64, height: 64)) {
                placePhotoView
            }
        } else {
            placePhotoView
        }
    }

    @ViewBuilder
    private var placePhotoView: some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 64, height: 64)) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(SonderColors.warmGrayDark)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(SonderColors.inkLight)
            }
    }
}

// MARK: - Journal Grid Cell

struct JournalGridCell: View {
    let log: Log
    let place: Place

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Photo
                photoView
                    .frame(width: geometry.size.width, height: geometry.size.width)

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Info overlay
                VStack(alignment: .leading, spacing: 2) {
                    Spacer()

                    HStack {
                        Text(place.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(log.rating.emoji)
                            .font(.system(size: 12))
                    }
                }
                .padding(SonderSpacing.xs)
            }
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 130, height: 130)) {
                placePhotoView
            }
        } else {
            placePhotoView
        }
    }

    @ViewBuilder
    private var placePhotoView: some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 130, height: 130)) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(SonderColors.warmGrayDark)
            .overlay {
                VStack(spacing: 4) {
                    Text(log.rating.emoji)
                        .font(.system(size: 24))
                    Text(place.name)
                        .font(.system(size: 10))
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
    }
}

#Preview {
    JournalView()
}
