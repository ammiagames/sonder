//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showLogFlow = false
    @Environment(SyncEngine.self) private var syncEngine

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                FeedView()
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

// MARK: - Placeholder Views

struct FeedView: View {
    @Environment(SyncEngine.self) private var syncEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Network status banner
                    if !syncEngine.isOnline {
                        offlineBanner
                    }

                    Text("Feed will show friends' recent logs here")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if syncEngine.isSyncing {
                        ProgressView()
                    }
                }
            }
        }
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("You're offline. Changes will sync when connected.")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .foregroundColor(.orange)
    }
}

struct MapView: View {
    var body: some View {
        NavigationStack {
            Text("Map view will show all logged places")
                .foregroundStyle(.secondary)
            .navigationTitle("Map")
        }
    }
}

struct LogsView: View {
    @Query(sort: \Log.createdAt, order: .reverse) private var logs: [Log]
    @Query private var places: [Place]
    @Query private var trips: [Trip]

    @State private var groupByTrip = false

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "No Logs Yet",
                        systemImage: "book.closed",
                        description: Text("Tap the + button to log your first place")
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
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    // MARK: - Chronological View

    @ViewBuilder
    private var chronologicalContent: some View {
        ForEach(logs, id: \.id) { log in
            LogRow(log: log, place: place(for: log), trip: trip(for: log))
        }
    }

    // MARK: - Grouped by Trip View

    @ViewBuilder
    private var groupedByTripContent: some View {
        // Logs with trips
        let logsByTrip = Dictionary(grouping: logs.filter { $0.tripID != nil }) { $0.tripID! }

        ForEach(trips.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }, id: \.id) { trip in
            if let tripLogs = logsByTrip[trip.id], !tripLogs.isEmpty {
                Section(trip.name) {
                    ForEach(tripLogs.sorted { $0.createdAt > $1.createdAt }, id: \.id) { log in
                        LogRow(log: log, place: place(for: log), trip: nil)
                    }
                }
            }
        }

        // Logs without trips
        let unassignedLogs = logs.filter { $0.tripID == nil }
        if !unassignedLogs.isEmpty {
            Section("No Trip") {
                ForEach(unassignedLogs.sorted { $0.createdAt > $1.createdAt }, id: \.id) { log in
                    LogRow(log: log, place: place(for: log), trip: nil)
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

                // Date, trip, sync status
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

                    if log.syncStatus != .synced {
                        Spacer()
                        SyncStatusIndicator(status: log.syncStatus)
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

    var body: some View {
        NavigationStack {
            List {
                if let user = authService.currentUser {
                    Section("Account") {
                        LabeledContent("Username", value: user.username)
                        LabeledContent("User ID", value: String(user.id.prefix(8)))
                    }
                }

                Section("Sync Status") {
                    HStack {
                        Text("Status")
                        Spacer()
                        if syncEngine.isOnline {
                            Label("Online", systemImage: "wifi")
                                .foregroundColor(.green)
                        } else {
                            Label("Offline", systemImage: "wifi.slash")
                                .foregroundColor(.orange)
                        }
                    }

                    if let lastSync = syncEngine.lastSyncDate {
                        LabeledContent("Last Sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                    }

                    if syncEngine.pendingCount > 0 {
                        HStack {
                            Text("Pending Uploads")
                            Spacer()
                            SyncStatusIndicator(status: .pending)
                            Text("\(syncEngine.pendingCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            try? await authService.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .refreshable {
                await syncEngine.forceSyncNow()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthenticationService())
}
