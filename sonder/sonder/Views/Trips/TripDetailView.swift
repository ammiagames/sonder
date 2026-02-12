//
//  TripDetailView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData
import MapKit

/// Detail view for a single trip showing map and logs
struct TripDetailView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [Log]
    @Query private var places: [Place]

    let trip: Trip

    @State private var showEditTrip = false
    @State private var showCollaborators = false
    @State private var selectedLog: Log?
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    /// Logs belonging to this trip
    private var tripLogs: [Log] {
        allLogs
            .filter { $0.tripID == trip.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Places for trip logs
    private var tripPlaces: [Place] {
        let logPlaceIDs = Set(tripLogs.map { $0.placeID })
        return places.filter { logPlaceIDs.contains($0.id) }
    }

    private var isOwner: Bool {
        trip.createdBy == authService.currentUser?.id
    }

    private var hasCoverPhoto: Bool {
        trip.coverPhotoURL != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero section (cover + info)
                heroSection

                // Map section
                if !tripPlaces.isEmpty {
                    mapSection
                }

                // Logs section
                logsSection
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isOwner {
                        Button {
                            showEditTrip = true
                        } label: {
                            Label("Edit Trip", systemImage: "pencil")
                        }
                    }

                    Button {
                        showCollaborators = true
                    } label: {
                        Label("Collaborators", systemImage: "person.2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditTrip) {
            CreateEditTripView(mode: .edit(trip))
        }
        .sheet(isPresented: $showCollaborators) {
            TripCollaboratorsView(trip: trip)
        }
        .navigationDestination(item: $selectedLog) { log in
            if let place = places.first(where: { $0.id == log.placeID }) {
                LogDetailView(log: log, place: place)
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 0) {
            // Cover photo (only if exists)
            if hasCoverPhoto, let urlString = trip.coverPhotoURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color(.systemGray5)
                    default:
                        Color(.systemGray5)
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .id(urlString) // Force refresh when URL changes
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
            }

            // Description
            if let description = trip.tripDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            // Info bar
            HStack {
                // Date range
                if let dateText = dateRangeText {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(dateText)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Log count
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                    Text("\(tripLogs.count) \(tripLogs.count == 1 ? "place" : "places")")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                // Collaborators count
                if !trip.collaboratorIDs.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                        Text("\(trip.collaboratorIDs.count + 1)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map")
                .font(.headline)
                .padding(.horizontal)

            tripMapContent
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
        }
        .padding(.top)
    }

    private var tripMapContent: some View {
        Map(position: $mapCameraPosition) {
            ForEach(tripPlaces, id: \.id) { place in
                if let log = tripLogs.first(where: { $0.placeID == place.id }) {
                    Annotation(place.name, coordinate: place.coordinate) {
                        Circle()
                            .fill(pinColor(for: log.rating))
                            .frame(width: 12, height: 12)
                            .overlay {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            }
                    }
                }
            }
        }
        .onAppear {
            updateMapRegion()
        }
    }

    private func updateMapRegion() {
        guard !tripPlaces.isEmpty else { return }

        let coordinates = tripPlaces.map { $0.coordinate }

        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLng = coordinates.map(\.longitude).min() ?? 0
        let maxLng = coordinates.map(\.longitude).max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )

        let latDelta = max((maxLat - minLat) * 1.5, 0.05)
        let lngDelta = max((maxLng - minLng) * 1.5, 0.05)

        mapCameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        ))
    }

    private func pinColor(for rating: Rating) -> Color {
        switch rating {
        case .skip: return SonderColors.ratingSkip
        case .solid: return SonderColors.ratingSolid
        case .mustSee: return SonderColors.ratingMustSee
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Places")
                .font(.headline)
                .padding(.horizontal)

            if tripLogs.isEmpty {
                emptyLogsState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(tripLogs, id: \.id) { log in
                        if let place = places.first(where: { $0.id == log.placeID }) {
                            Button {
                                selectedLog = log
                            } label: {
                                TripLogRow(log: log, place: place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top)
    }

    private var emptyLogsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No places logged yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Add places to this trip when logging")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private var dateRangeText: String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        if let start = trip.startDate, let end = trip.endDate {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = trip.startDate {
            return "From \(formatter.string(from: start))"
        } else if let end = trip.endDate {
            return "Until \(formatter.string(from: end))"
        }
        return nil
    }
}

// MARK: - Trip Log Row

struct TripLogRow: View {
    let log: Log
    let place: Place

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo
            photoView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(place.name)
                    .font(SonderTypography.body)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .lineLimit(1)

                Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundColor(SonderColors.inkLight)
            }

            Spacer()

            // Rating
            Text(log.rating.emoji)
                .font(.title3)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(SonderColors.inkLight)
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placePhotoView
                }
            }
        } else {
            placePhotoView
        }
    }

    @ViewBuilder
    private var placePhotoView: some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
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
                Image(systemName: "photo")
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(
            trip: Trip(
                name: "Japan 2024",
                startDate: Date(),
                endDate: Date().addingTimeInterval(86400 * 14),
                createdBy: "user1"
            )
        )
    }
}
