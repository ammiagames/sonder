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
    @State private var displayStyle: JournalDisplayStyle = .polaroid

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
                if let place = placesByID[log.placeID] {
                    LogViewScreen(log: log, place: place, onDelete: {
                        selectedLog = nil
                    })
                }
            }
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip, onDelete: {
                    selectedTrip = nil
                })
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
            }
            .onChange(of: showCreateTrip) { _, isShowing in
                if !isShowing, newlyCreatedTrip != nil, !orphanedLogs.isEmpty {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        showAssignLogs = true
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
                deleteLog: deleteLog,
                searchText: searchText
            )
        case .polaroid:
            JournalPolaroidView(
                trips: filteredTrips,
                allLogs: allUserLogs,
                places: Array(places),
                orphanedLogs: orphanedLogs,
                selectedTrip: $selectedTrip,
                selectedLog: $selectedLog
            )
        case .boardingPass:
            JournalBoardingPassView(
                trips: filteredTrips,
                allLogs: allUserLogs,
                places: Array(places),
                orphanedLogs: orphanedLogs,
                selectedTrip: $selectedTrip,
                selectedLog: $selectedLog
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

    // MARK: - Helpers

    private func deleteLog(_ log: Log) {
        Task { await syncEngine.deleteLog(id: log.id) }
    }
}
