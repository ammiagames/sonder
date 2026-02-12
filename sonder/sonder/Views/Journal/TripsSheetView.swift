//
//  TripsSheetView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData

/// Sheet view for managing trips, accessible from Journal toolbar
struct TripsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]

    @State private var showCreateTrip = false
    @State private var showInvitations = false
    @State private var selectedTrip: Trip?
    @State private var isLoading = false

    let pendingInvitationCount: Int
    let onInvitationsViewed: () -> Void

    /// Trips filtered to current user (owned + collaborating)
    private var trips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.md) {
                    // Pending invitations banner
                    if pendingInvitationCount > 0 {
                        pendingInvitationsBanner
                    }

                    // Trips list
                    if trips.isEmpty && pendingInvitationCount == 0 {
                        emptyState
                    } else {
                        LazyVStack(spacing: SonderSpacing.sm) {
                            ForEach(trips, id: \.id) { trip in
                                Button {
                                    selectedTrip = trip
                                } label: {
                                    TripRowCard(
                                        trip: trip,
                                        logCount: logCount(for: trip),
                                        isOwner: isOwner(trip)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(SonderSpacing.md)
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(SonderColors.inkMuted)
                }

                ToolbarItem(placement: .primaryAction) {
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
            .sheet(isPresented: $showInvitations) {
                PendingInvitationsView()
            }
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
            }
            .onChange(of: showInvitations) { _, isShowing in
                if !isShowing {
                    onInvitationsViewed()
                }
            }
            .refreshable {
                await loadTrips()
            }
            .task {
                await loadTrips()
            }
        }
    }

    // MARK: - Pending Invitations Banner

    private var pendingInvitationsBanner: some View {
        Button {
            showInvitations = true
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: "envelope.badge")
                    .font(.title2)
                    .foregroundColor(SonderColors.terracotta)
                    .frame(width: 40, height: 40)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip Invitations")
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)

                    Text("\(pendingInvitationCount) pending")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SonderColors.inkLight)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "suitcase")
                .font(.system(size: 48))
                .foregroundColor(SonderColors.inkLight)

            Text("No Trips Yet")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text("Create a trip to organize your logs by journey")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
                .multilineTextAlignment(.center)

            Button {
                showCreateTrip = true
            } label: {
                Text("Create Trip")
                    .font(SonderTypography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, SonderSpacing.lg)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
            }
            .padding(.top, SonderSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SonderSpacing.xxl)
    }

    // MARK: - Helpers

    private func logCount(for trip: Trip) -> Int {
        allLogs.filter { $0.tripID == trip.id }.count
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
            print("Error loading trips: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Trip Row Card

struct TripRowCard: View {
    let trip: Trip
    let logCount: Int
    let isOwner: Bool

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Cover photo or placeholder
            coverPhoto
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                // Trip name
                HStack {
                    Text(trip.name)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    if !isOwner {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }

                // Description or dates
                if let description = trip.tripDescription, !description.isEmpty {
                    Text(description)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                } else if let startDate = trip.startDate {
                    Text(formatDateRange(start: startDate, end: trip.endDate))
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }

                // Log count
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10))
                    Text("\(logCount) \(logCount == 1 ? "place" : "places")")
                        .font(SonderTypography.caption)
                }
                .foregroundColor(SonderColors.inkLight)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(SonderColors.inkLight)
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    @ViewBuilder
    private var coverPhoto: some View {
        if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    photoPlaceholder
                }
            }
            .id(urlString)
        } else {
            photoPlaceholder
        }
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
            .overlay {
                Image(systemName: "suitcase.fill")
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    private func formatDateRange(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        if let end = end {
            let startStr = formatter.string(from: start)
            let endStr = formatter.string(from: end)
            return "\(startStr) - \(endStr)"
        } else {
            return formatter.string(from: start)
        }
    }
}

#Preview {
    TripsSheetView(pendingInvitationCount: 2) { }
}
