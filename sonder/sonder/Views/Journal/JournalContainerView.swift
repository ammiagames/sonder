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

// MARK: - Polaroid Background Style

enum PolaroidBackgroundStyle: String, CaseIterable {
    case tripPhotos = "Trip Photos"
    case starryNight = "Starry Night"
    case neonCity = "Neon City"
    case clothesline = "Clothesline"
    case underwater = "Underwater"
    case confetti = "Confetti"
    case botanical = "Botanical"

    var icon: String {
        switch self {
        case .tripPhotos: return "photo.fill"
        case .starryNight: return "moon.stars"
        case .neonCity: return "building.2"
        case .clothesline: return "sun.horizon"
        case .underwater: return "water.waves"
        case .confetti: return "party.popper"
        case .botanical: return "leaf"
        }
    }
}

/// Main journal view showing trips in a masonry grid.
struct JournalContainerView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
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
    @State private var polaroidBackground: PolaroidBackgroundStyle = .tripPhotos

    // MARK: - Computed Data

    /// O(P) dictionary for O(1) place lookups
    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var userLogs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    private var userTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        let filtered = allTrips.filter { $0.createdBy == userID || $0.collaboratorIDs.contains(userID) }
        return sortTripsReverseChronological(filtered)
    }

    private var filteredTrips: [Trip] {
        guard !debouncedSearchText.isEmpty else { return userTrips }
        let searchLower = debouncedSearchText.lowercased()
        return userTrips.filter { trip in
            trip.name.lowercased().contains(searchLower) ||
            (trip.tripDescription?.lowercased().contains(searchLower) ?? false)
        }
    }

    private var orphanedLogs: [Log] {
        let tripIDs = Set(userTrips.map(\.id))
        return userLogs.filter { $0.hasNoTrip || (!tripIDs.contains($0.tripID!)) }
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
                            .foregroundColor(SonderColors.inkMuted)
                            .toolbarIcon()
                    }
                }

                if displayStyle == .polaroid {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(PolaroidBackgroundStyle.allCases, id: \.self) { bg in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.8)) {
                                        polaroidBackground = bg
                                    }
                                } label: {
                                    Label {
                                        Text(bg.rawValue)
                                    } icon: {
                                        Image(systemName: bg.icon)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "paintpalette")
                                .foregroundColor(SonderColors.inkMuted)
                                .toolbarIcon()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(SonderColors.terracotta)
                            .toolbarIcon()
                    }
                }
            }
            .sheet(isPresented: $showCreateTrip) {
                CreateEditTripView(mode: .create, onTripCreated: { trip in
                    newlyCreatedTrip = trip
                })
            }
            .navigationDestination(item: $selectedLog) { log in
                if let place = placesByID[log.placeID] {
                    LogDetailView(log: log, place: place, onDelete: {
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
                allLogs: allLogs,
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
                allLogs: allLogs,
                places: Array(places),
                orphanedLogs: orphanedLogs,
                selectedTrip: $selectedTrip,
                selectedLog: $selectedLog,
                backgroundStyle: polaroidBackground
            )
        case .boardingPass:
            JournalBoardingPassView(
                trips: filteredTrips,
                allLogs: allLogs,
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
                .foregroundColor(SonderColors.inkLight)
            TextField("Search trips...", text: $searchText)
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

    // MARK: - Empty State

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

    // MARK: - Helpers

    private func deleteLog(_ log: Log) {
        Task { await syncEngine.deleteLog(id: log.id) }
    }
}
