//
//  JournalContainerView.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI
import SwiftData

/// Main journal view with segmented Trips/Logs control.
/// Trips segment shows a masonry grid with a configurable trail line style (A/B/C).
/// Logs segment shows the chronological list/grid.
struct JournalContainerView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query private var places: [Place]

    // MARK: - State

    @State private var segment: JournalSegment = .trips
    @State private var trailStyle: TrailStyle = .zigzag
    @State private var searchText = ""
    @State private var viewMode: JournalViewMode = .list
    @State private var selectedRatingFilter: Rating?
    @State private var selectedTagFilter: String?
    @State private var selectedTripFilter: Trip?
    @State private var showTripsSheet = false
    @State private var pendingInvitationCount = 0
    @State private var selectedLog: Log?
    @State private var selectedTrip: Trip?

    // MARK: - Computed Data

    private var userLogs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    private var userTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
    }

    private var filteredLogs: [Log] {
        var logs = userLogs

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

        if let rating = selectedRatingFilter {
            logs = logs.filter { $0.rating == rating }
        }
        if let tag = selectedTagFilter {
            logs = logs.filter { $0.tags.contains(tag) }
        }
        if let trip = selectedTripFilter {
            logs = logs.filter { $0.tripID == trip.id }
        }

        return logs
    }

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
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                key = formatter.string(from: log.createdAt)
            }
            groups[key, default: []].append(log)
        }

        let order = ["Today", "Yesterday", "This Week", "This Month"]
        return groups.sorted { a, b in
            let aIndex = order.firstIndex(of: a.key) ?? Int.max
            let bIndex = order.firstIndex(of: b.key) ?? Int.max
            if aIndex != Int.max || bIndex != Int.max {
                return aIndex < bIndex
            }
            let aDate = a.value.first?.createdAt ?? .distantPast
            let bDate = b.value.first?.createdAt ?? .distantPast
            return aDate > bDate
        }
    }

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

    // MARK: - Body

    var body: some View {
        let _ = syncEngine.lastSyncDate

        NavigationStack {
            Group {
                if userLogs.isEmpty && userTrips.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        searchAndFilters

                        // Segment picker
                        Picker("", selection: $segment) {
                            ForEach(JournalSegment.allCases, id: \.self) { seg in
                                Text(seg.rawValue).tag(seg)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, SonderSpacing.md)
                        .padding(.bottom, SonderSpacing.xs)

                        // Trail style picker (trips segment only)
                        if segment == .trips && !userTrips.isEmpty {
                            trailStylePicker
                        }

                        // Content
                        if segment == .trips {
                            tripsContent
                        } else {
                            if filteredLogs.isEmpty {
                                noResultsState
                            } else {
                                logsContent
                            }
                        }
                    }
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if segment == .logs {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = viewMode == .list ? .grid : .list
                            }
                        } label: {
                            Image(systemName: viewMode.icon)
                                .foregroundColor(SonderColors.inkMuted)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
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
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
            }
            .task {
                await loadInvitationCount()
            }
        }
    }

    // MARK: - Trail Style Picker

    private var trailStylePicker: some View {
        HStack(spacing: SonderSpacing.xs) {
            ForEach(TrailStyle.allCases, id: \.self) { style in
                FilterChipButton(
                    label: style.rawValue,
                    isSelected: trailStyle == style
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        trailStyle = style
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.xs)
    }

    // MARK: - Trips Content

    private var tripsContent: some View {
        MasonryTripsGrid(
            trips: userTrips,
            allLogs: allLogs,
            places: places,
            filteredLogs: filteredLogs,
            trailStyle: trailStyle,
            selectedTrip: $selectedTrip,
            selectedLog: $selectedLog,
            deleteLog: deleteLog
        )
    }

    // MARK: - Logs Content

    @ViewBuilder
    private var logsContent: some View {
        switch viewMode {
        case .list:
            logsList
        case .grid:
            logsGrid
        }
    }

    private var logsList: some View {
        List {
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
        .scrollContentBackground(.hidden)
    }

    private var logsGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SonderSpacing.md) {
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
                                }
                            }
                        }
                        .padding(.horizontal, SonderSpacing.md)
                    }
                }
                Spacer().frame(height: 80)
            }
            .padding(.top, SonderSpacing.sm)
        }
    }

    // MARK: - Search & Filters

    private var searchAndFilters: some View {
        VStack(spacing: SonderSpacing.xs) {
            searchBar
                .padding(.horizontal, SonderSpacing.md)
            filterChips
        }
        .padding(.top, SonderSpacing.xs)
        .padding(.bottom, SonderSpacing.sm)
    }

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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SonderSpacing.xs) {
                if hasActiveFilters {
                    Button {
                        clearFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }

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
}
