//
//  TripsListView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "TripsListView")

enum LogsTripsTab: String, CaseIterable {
    case logs = "Logs"
    case trips = "Trips"
}

/// Main logs/trips tab showing all user's logs and trips
struct TripsListView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @State private var allUserTrips: [Trip] = []
    @State private var allUserLogs: [Log] = []
    @Query private var places: [Place]

    @State private var selectedTab: LogsTripsTab = .logs
    @State private var isLoading = false
    @State private var showCreateTrip = false
    @State private var showInvitations = false
    @State private var pendingInvitationCount = 0
    @State private var selectedTrip: Trip?
    @State private var selectedLog: Log?
    @Namespace private var tripTransition

    // Cached lookups — rebuilt in refreshData()
    @State private var cachedPlacesByID: [String: Place] = [:]
    @State private var cachedTripsByID: [String: Trip] = [:]
    @State private var cachedLogCountsByTripID: [String: Int] = [:]

    /// Trips filtered to current user (owned + collaborating)
    private var trips: [Trip] { allUserTrips }

    /// Logs filtered to current user
    private var logs: [Log] { allUserLogs }

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

        // Rebuild O(1) lookup caches
        cachedPlacesByID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        cachedTripsByID = Dictionary(allUserTrips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var logCounts: [String: Int] = [:]
        for log in allUserLogs {
            if let tripID = log.tripID { logCounts[tripID, default: 0] += 1 }
        }
        cachedLogCountsByTripID = logCounts
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker with warm styling
                Picker("View", selection: $selectedTab) {
                    ForEach(LogsTripsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SonderSpacing.md)
                .padding(.vertical, SonderSpacing.sm)

                // Content
                Group {
                    switch selectedTab {
                    case .logs:
                        logsContent
                    case .trips:
                        tripsContent
                    }
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedTab == .trips {
                        Button {
                            showCreateTrip = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(SonderColors.terracotta)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateTrip) {
                CreateEditTripView(mode: .create)
            }
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
                    .navigationTransition(.zoom(sourceID: trip.id, in: tripTransition))
            }
            .navigationDestination(item: $selectedLog) { log in
                if let freshLog = allUserLogs.first(where: { $0.id == log.id }),
                   let place = cachedPlacesByID[freshLog.placeID] {
                    LogViewScreen(log: freshLog, place: place, onDelete: {
                        selectedLog = nil
                    })
                } else {
                    Color.clear.onAppear { selectedLog = nil }
                }
            }
            .sheet(isPresented: $showInvitations) {
                PendingInvitationsView()
            }
            .refreshable {
                await loadTrips()
                await loadInvitationCount()
            }
            .task {
                refreshData()
                await loadTrips()
                await loadInvitationCount()
            }
            .onChange(of: syncEngine.lastSyncDate) { _, _ in refreshData() }
            .onChange(of: showInvitations) { _, isShowing in
                if !isShowing {
                    Task {
                        await loadInvitationCount()
                        await loadTrips()
                    }
                }
            }
        }
    }

    // MARK: - Logs Content

    @ViewBuilder
    private var logsContent: some View {
        if logs.isEmpty {
            emptyLogsState
        } else {
            ScrollView {
                LazyVStack(spacing: SonderSpacing.sm) {
                    ForEach(logs, id: \.id) { log in
                        if let place = cachedPlacesByID[log.placeID] {
                            Button {
                                selectedLog = log
                            } label: {
                                LogListRow(
                                    log: log,
                                    place: place,
                                    tripName: tripName(for: log)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(SonderSpacing.md)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyLogsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.inkLight)

            Text("No Logs Yet")
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            Text("Start logging places you visit")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trips Content

    @ViewBuilder
    private var tripsContent: some View {
        if trips.isEmpty && pendingInvitationCount == 0 && !isLoading {
            emptyTripsState
        } else {
            ScrollView {
                LazyVStack(spacing: SonderSpacing.md) {
                    // Pending invitations banner
                    if pendingInvitationCount > 0 {
                        pendingInvitationsBanner
                    }

                    ForEach(trips, id: \.id) { trip in
                        Button {
                            selectedTrip = trip
                        } label: {
                            TripCard(
                                trip: trip,
                                logCount: logCount(for: trip),
                                isOwner: isOwner(trip)
                            )
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: trip.id, in: tripTransition)
                    }
                }
                .padding(SonderSpacing.md)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyTripsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "suitcase")
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.inkLight)

            Text("No Trips Yet")
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            Text("Create a trip to organize your logs by journey")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SonderSpacing.xl)

            Button {
                showCreateTrip = true
            } label: {
                Text("Create Trip")
                    .font(SonderTypography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SonderSpacing.lg)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
            }
            .padding(.top, SonderSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pending Invitations Banner

    private var pendingInvitationsBanner: some View {
        Button {
            showInvitations = true
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: "envelope.badge")
                    .font(.title2)
                    .foregroundStyle(SonderColors.terracotta)
                    .frame(width: 40, height: 40)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip Invitations")
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)

                    Text("\(pendingInvitationCount) pending \(pendingInvitationCount == 1 ? "invitation" : "invitations")")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                    .stroke(SonderColors.terracotta.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func tripName(for log: Log) -> String? {
        guard let tripID = log.tripID else { return nil }
        return cachedTripsByID[tripID]?.name
    }

    private func logCount(for trip: Trip) -> Int {
        cachedLogCountsByTripID[trip.id] ?? 0
    }

    private func isOwner(_ trip: Trip) -> Bool {
        trip.createdBy == authService.currentUser?.id
    }

    private func loadTrips() async {
        guard let userID = authService.currentUser?.id else { return }
        isLoading = true
        do {
            _ = try await tripService.fetchTrips(for: userID)
        } catch {
            logger.error("Error loading trips: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func loadInvitationCount() async {
        guard let userID = authService.currentUser?.id else { return }
        do {
            pendingInvitationCount = try await tripService.getPendingInvitationCount(for: userID)
        } catch {
            logger.error("Error loading invitation count: \(error.localizedDescription)")
        }
    }
}

// MARK: - Log List Row

struct LogListRow: View {
    let log: Log
    let place: Place
    let tripName: String?

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo thumbnail
            photoView
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                // Place name + rating
                HStack {
                    Text(place.name)
                        .font(SonderTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    Text(log.rating.emoji)
                        .font(.subheadline)
                }

                // Address
                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .lineLimit(1)

                // Trip + date
                HStack(spacing: SonderSpacing.xs) {
                    if let tripName = tripName {
                        HStack(spacing: 2) {
                            Image(systemName: "suitcase.fill")
                                .font(.caption2)
                            Text(tripName)
                                .font(SonderTypography.caption)
                        }
                        .foregroundStyle(SonderColors.terracotta)
                    }

                    Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SonderColors.inkLight)
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
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
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
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
                    .foregroundStyle(SonderColors.inkLight)
            }
    }
}

#Preview {
    TripsListView()
}
