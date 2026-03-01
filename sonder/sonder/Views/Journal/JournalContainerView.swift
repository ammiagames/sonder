//
//  JournalContainerView.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI
import SwiftData

// MARK: - Journal Display Style

enum JournalDisplayStyle: String, CaseIterable {
    case polaroid = "Polaroid"
    case boardingPass = "Boarding Pass"
    case masonry = "Grid"

    var icon: String {
        switch self {
        case .polaroid: return "photo.on.rectangle"
        case .boardingPass: return "airplane.departure"
        case .masonry: return "square.grid.2x2"
        }
    }
}

/// Main journal view showing trips in a masonry grid.
struct JournalContainerView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @State private var allUserLogs: [Log] = []
    @State private var allUserTrips: [Trip] = []
    @Query private var places: [Place]

    var popToRoot: UUID = UUID()

    // MARK: - State

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showCreateTrip = false
    @State private var selectedLog: Log?
    @State private var selectedTrip: Trip?
    @State private var newlyCreatedTrip: Trip?
    @State private var showAssignLogs = false
    @State private var assignLogsTask: Task<Void, Never>?
    @State private var displayStyle: JournalDisplayStyle = .polaroid
    @State private var showFloatingSearch = true

    // Multi-select bulk delete for orphaned logs
    @State private var orphanedLogSelection = OrphanedLogSelectionState()
    @State private var showBulkDeleteAlert = false

    // Cached derived data — rebuilt when source data changes
    @State private var cachedPlacesByID: [String: Place] = [:]
    @State private var cachedOrphanedLogs: [Log] = []

    // MARK: - Computed Data

    /// O(1) dictionary lookup — rebuilt via rebuildJournalCaches()
    private var placesByID: [String: Place] { cachedPlacesByID }

    private var userLogs: [Log] { allUserLogs }

    private var userTrips: [Trip] {
        sortTripsReverseChronological(allUserTrips)
    }

    private func refreshData() {
        guard let userID = authService.currentUser?.id else { return }
        let logDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        allUserLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        let tripDescriptor = FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allTrips = (try? modelContext.fetch(tripDescriptor)) ?? []
        allUserTrips = allTrips.filter { $0.isAccessible(by: userID) }

        rebuildJournalCaches()
    }

    private func rebuildJournalCaches() {
        cachedPlacesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let tripIDs = Set(allUserTrips.map(\.id))
        cachedOrphanedLogs = allUserLogs.filter { $0.tripID.map { !tripIDs.contains($0) } ?? true }
    }

    private var filteredTrips: [Trip] {
        guard !debouncedSearchText.isEmpty else { return userTrips }
        let searchLower = debouncedSearchText.lowercased()
        return userTrips.filter { trip in
            trip.name.lowercased().contains(searchLower) ||
            (trip.tripDescription?.lowercased().contains(searchLower) ?? false)
        }
    }

    private var orphanedLogs: [Log] { cachedOrphanedLogs }

    private var filteredOrphanedLogs: [Log] {
        guard !debouncedSearchText.isEmpty else { return orphanedLogs }
        let searchLower = debouncedSearchText.lowercased()
        let dict = placesByID
        return orphanedLogs.filter { log in
            let place = dict[log.placeID]
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

    private var filteredLogs: [Log] {
        var logs = userLogs
        if !debouncedSearchText.isEmpty {
            let searchLower = debouncedSearchText.lowercased()
            let dict = placesByID
            logs = logs.filter { log in
                let place = dict[log.placeID]
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
        return logs
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if userLogs.isEmpty && userTrips.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        if displayStyle != .polaroid {
                            searchBar
                                .padding(.horizontal, SonderSpacing.md)
                                .padding(.top, SonderSpacing.xs)
                                .padding(.bottom, SonderSpacing.sm)
                        }

                        tripsContent
                            .overlay(alignment: .top) {
                                if displayStyle == .polaroid {
                                    let visible = showFloatingSearch || !searchText.isEmpty
                                    polaroidSearchBar
                                        .padding(.horizontal, SonderSpacing.lg)
                                        .padding(.top, SonderSpacing.sm)
                                        .offset(y: visible ? 0 : -80)
                                        .opacity(visible ? 1 : 0)
                                        .animation(.easeInOut(duration: 0.25), value: visible)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if orphanedLogSelection.isActive {
                                    selectionActionBar
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .animation(.easeInOut(duration: 0.25), value: orphanedLogSelection.isActive)
                    }
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(SonderColors.cream, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(JournalDisplayStyle.allCases, id: \.self) { style in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    displayStyle = style
                                }
                            } label: {
                                Label {
                                    Text(style.rawValue)
                                } icon: {
                                    Image(systemName: style.icon)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: displayStyle.icon)
                            .foregroundStyle(SonderColors.inkMuted)
                            .toolbarIcon()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(SonderColors.terracotta)
                            .toolbarIcon()
                    }
                }
            }
            .task { refreshData() }
            .onChange(of: syncEngine.lastSyncDate) { _, _ in refreshData() }
            .sheet(isPresented: $showCreateTrip) {
                CreateEditTripView(mode: .create, onTripCreated: { trip in
                    newlyCreatedTrip = trip
                    refreshData()
                })
            }
            .navigationDestination(item: $selectedLog) { log in
                if let freshLog = allUserLogs.first(where: { $0.id == log.id }),
                   let place = placesByID[freshLog.placeID] {
                    LogViewScreen(log: freshLog, place: place, onDelete: {
                        selectedLog = nil
                    })
                } else {
                    // Data became stale (deleted/synced) — dismiss gracefully
                    Color.clear.onAppear { selectedLog = nil }
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                if allUserTrips.contains(where: { $0.id == trip.id }) {
                    TripDetailView(trip: trip, onDelete: {
                        selectedTrip = nil
                    })
                } else {
                    // Data became stale (deleted/synced) — dismiss gracefully
                    Color.clear.onAppear { selectedTrip = nil }
                }
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                if newValue.isEmpty {
                    debouncedSearchText = ""
                } else {
                    searchDebounceTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        debouncedSearchText = newValue
                    }
                }
            }
            .onChange(of: popToRoot) {
                selectedLog = nil
                selectedTrip = nil
                orphanedLogSelection.reset()
            }
            .onChange(of: displayStyle) { _, _ in
                orphanedLogSelection.reset()
            }
            .alert(
                "Delete \(orphanedLogSelection.selectedIDs.count) Log\(orphanedLogSelection.selectedIDs.count == 1 ? "" : "s")?",
                isPresented: $showBulkDeleteAlert
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    bulkDeleteSelectedLogs()
                }
            } message: {
                Text("This cannot be undone.")
            }
            .onChange(of: showCreateTrip) { _, isShowing in
                if !isShowing, let trip = newlyCreatedTrip {
                    assignLogsTask?.cancel()
                    assignLogsTask = Task { @MainActor in
                        // Wait for sheet dismiss animation to complete
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        // Navigate to the newly created trip
                        selectedTrip = trip
                        // If orphaned logs exist, show assign sheet after navigation settles
                        if !orphanedLogs.isEmpty {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            showAssignLogs = true
                        } else {
                            newlyCreatedTrip = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $showAssignLogs, onDismiss: {
                newlyCreatedTrip = nil
            }) {
                if let trip = newlyCreatedTrip {
                    AssignLogsToTripSheet(
                        trip: trip,
                        orphanedLogs: orphanedLogs,
                        placesByID: placesByID
                    )
                }
            }
        }
    }

    // MARK: - Trips Content

    @ViewBuilder
    private var tripsContent: some View {
        switch displayStyle {
        case .masonry:
            MasonryTripsGrid(
                trips: filteredTrips,
                allLogs: allUserLogs,
                places: places,
                filteredLogs: filteredLogs,
                selectedTrip: $selectedTrip,
                selectedLog: $selectedLog,
                orphanedLogSelection: $orphanedLogSelection,
                deleteLog: deleteLog,
                searchText: searchText
            )
        case .polaroid:
            JournalPolaroidView(
                trips: filteredTrips,
                allLogs: allUserLogs,
                places: Array(places),
                orphanedLogs: filteredOrphanedLogs,
                selectedTrip: $selectedTrip,
                selectedLog: $selectedLog,
                orphanedLogSelection: $orphanedLogSelection,
                showFloatingSearch: $showFloatingSearch
            )
        case .boardingPass:
            JournalBoardingPassView(
                trips: filteredTrips,
                allLogs: allUserLogs,
                places: Array(places),
                orphanedLogs: orphanedLogs,
                selectedTrip: $selectedTrip,
                selectedLog: $selectedLog,
                orphanedLogSelection: $orphanedLogSelection
            )
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SonderColors.inkLight)
            TextField("Search trips...", text: $searchText)
                .font(SonderTypography.body)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    /// Frosted search bar that floats over the polaroid topographic background.
    private var polaroidSearchBar: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SonderColors.terracotta.opacity(0.7))
            TextField("Search memories...", text: $searchText)
                .font(.system(size: 15, weight: .regular, design: .serif))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                .strokeBorder(SonderColors.terracotta.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            if syncEngine.isSyncing {
                ProgressView()
                    .tint(SonderColors.terracotta)
                Text("Syncing your journal...")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(SonderColors.inkLight)
                Text("Your Journal Awaits")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)
                Text("Start logging places to build your personal travel journal")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: SonderSpacing.md) {
            Button {
                withAnimation { orphanedLogSelection.reset() }
            } label: {
                Text("Cancel")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkDark)
            }

            Spacer()

            Text("\(orphanedLogSelection.selectedIDs.count) selected")
                .font(SonderTypography.subheadline)
                .foregroundStyle(SonderColors.inkMuted)

            Spacer()

            Button {
                showBulkDeleteAlert = true
            } label: {
                Text("Delete")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(orphanedLogSelection.selectedIDs.isEmpty ? Color.gray : Color.red)
                    )
            }
            .disabled(orphanedLogSelection.selectedIDs.isEmpty)
        }
        .padding(.horizontal, SonderSpacing.lg)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func deleteLog(_ log: Log) {
        Task { await syncEngine.deleteLog(id: log.id) }
    }

    private func bulkDeleteSelectedLogs() {
        let idsToDelete = Array(orphanedLogSelection.selectedIDs)
        withAnimation { orphanedLogSelection.reset() }
        SonderHaptics.notification(.success)
        Task { await syncEngine.bulkDeleteLogs(ids: idsToDelete) }
    }
}
