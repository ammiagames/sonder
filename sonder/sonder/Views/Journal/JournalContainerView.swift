//
//  JournalContainerView.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI
import SwiftData

/// Main journal view showing trips in a masonry grid.
struct JournalContainerView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query private var places: [Place]

    // MARK: - State

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showCreateTrip = false
    @State private var selectedLog: Log?
    @State private var selectedTrip: Trip?

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
        let _ = syncEngine.lastSyncDate

        NavigationStack {
            Group {
                if userLogs.isEmpty && userTrips.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        searchBar
                            .padding(.horizontal, SonderSpacing.md)
                            .padding(.top, SonderSpacing.xs)
                            .padding(.bottom, SonderSpacing.sm)

                        tripsContent
                    }
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(SonderColors.terracotta)
                    }
                }
            }
            .sheet(isPresented: $showCreateTrip) {
                CreateEditTripView(mode: .create)
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
        }
    }

    // MARK: - Trips Content

    private var tripsContent: some View {
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
