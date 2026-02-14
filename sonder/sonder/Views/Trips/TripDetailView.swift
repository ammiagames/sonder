//
//  TripDetailView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData
import MapKit

/// Detail view for a single trip — chronological timeline with story experience
struct TripDetailView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(PhotoService.self) private var photoService
    @Environment(\.modelContext) private var modelContext
    @Query private var allLogs: [Log]
    @Query private var places: [Place]

    let trip: Trip

    @State private var showEditTrip = false
    @State private var showCollaborators = false
    @State private var showStoryPage = false
    @State private var storyStartIndex = 0
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showImagePicker = false
    @State private var isUploadingCoverPhoto = false

    /// Logs belonging to this trip, sorted chronologically (oldest first)
    private var tripLogs: [Log] {
        allLogs
            .filter { $0.tripID == trip.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Logs grouped by calendar day, sorted ascending
    private var logsByDay: [(date: Date, logs: [Log])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: tripLogs) { log in
            calendar.startOfDay(for: log.createdAt)
        }
        return grouped.sorted { $0.key < $1.key }
            .map { (date: $0.key, logs: $0.value) }
    }

    /// Places for trip logs
    private var tripPlaces: [Place] {
        let logPlaceIDs = Set(tripLogs.map { $0.placeID })
        return places.filter { logPlaceIDs.contains($0.id) }
    }

    private var isOwner: Bool {
        trip.createdBy == authService.currentUser?.id
    }

    private var tripDayCount: Int {
        if let start = trip.startDate, let end = trip.endDate {
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            return max(1, days + 1)
        }
        return max(1, Set(tripLogs.map { Calendar.current.startOfDay(for: $0.createdAt) }).count)
    }

    private var ratingCounts: (mustSee: Int, solid: Int, skip: Int) {
        (
            mustSee: tripLogs.filter { $0.rating == .mustSee }.count,
            solid: tripLogs.filter { $0.rating == .solid }.count,
            skip: tripLogs.filter { $0.rating == .skip }.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                storyHeroHeader

                if !tripLogs.isEmpty {
                    tripStatsBar
                }

                if !tripPlaces.isEmpty {
                    mapSection
                }

                timelineSection
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
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
        .fullScreenCover(isPresented: $showStoryPage) {
            TripStoryPageView(
                logs: tripLogs,
                places: Array(places),
                tripName: trip.name,
                startIndex: storyStartIndex
            )
        }
        .sheet(isPresented: $showImagePicker) {
            EditableImagePicker { image in
                showImagePicker = false
                Task { await uploadCoverPhoto(image) }
            } onCancel: {
                showImagePicker = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Story Hero Header

    private var storyHeroHeader: some View {
        VStack(spacing: 0) {
            // Cover photo with overlaid title
            ZStack(alignment: .bottomLeading) {
                // Photo or gradient placeholder
                if let urlString = trip.coverPhotoURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 280)) {
                        heroGradientPlaceholder
                    }
                    .id(urlString)
                } else {
                    heroGradientPlaceholder
                }

                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Overlaid text
                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    Text(trip.name)
                        .font(SonderTypography.largeTitle)
                        .foregroundColor(.white)

                    HStack(spacing: SonderSpacing.sm) {
                        if let dateText = dateRangeText {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(dateText)
                            }
                            .font(SonderTypography.caption)
                            .foregroundColor(.white.opacity(0.85))
                        }

                        if !trip.collaboratorIDs.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                Text("\(trip.collaboratorIDs.count + 1)")
                            }
                            .font(SonderTypography.caption)
                            .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(SonderSpacing.lg)
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if isOwner {
                    Button {
                        showImagePicker = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(SonderColors.terracotta)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(SonderColors.cream, lineWidth: 2)
                            }
                    }
                    .padding(SonderSpacing.md)
                }
            }
            .overlay {
                if isUploadingCoverPhoto {
                    Color.black.opacity(0.4)
                    ProgressView()
                        .tint(.white)
                }
            }

            // Description + View Story button
            VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                if let description = trip.tripDescription, !description.isEmpty {
                    Text(description)
                        .font(SonderTypography.body)
                        .foregroundColor(SonderColors.inkMuted)
                }

                if !tripLogs.isEmpty {
                    Button {
                        storyStartIndex = 0
                        showStoryPage = true
                    } label: {
                        HStack(spacing: SonderSpacing.xs) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                            Text("View Story")
                                .font(SonderTypography.headline)
                        }
                        .padding(.horizontal, SonderSpacing.lg)
                        .padding(.vertical, SonderSpacing.sm)
                        .background(SonderColors.terracotta)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(SonderSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroGradientPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        SonderColors.terracotta.opacity(0.6),
                        SonderColors.ochre.opacity(0.4),
                        SonderColors.warmGrayDark
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    // MARK: - Stats Bar

    private var tripStatsBar: some View {
        HStack(spacing: SonderSpacing.sm) {
            statItem("\(tripLogs.count)", label: tripLogs.count == 1 ? "place" : "places")

            Text("·")
                .foregroundColor(SonderColors.inkLight)

            statItem("\(tripDayCount)", label: tripDayCount == 1 ? "day" : "days")

            Spacer()

            if ratingCounts.mustSee > 0 {
                Text("\(Rating.mustSee.emoji)\(ratingCounts.mustSee)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }
            if ratingCounts.solid > 0 {
                Text("\(Rating.solid.emoji)\(ratingCounts.solid)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }
            if ratingCounts.skip > 0 {
                Text("\(Rating.skip.emoji)\(ratingCounts.skip)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .padding(.horizontal, SonderSpacing.md)
        .padding(.top, SonderSpacing.xs)
    }

    private func statItem(_ value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
            Text(label)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    // MARK: - Map Section

    /// Logs in chronological order with their corresponding places, for map route
    private var chronologicalMapStops: [(index: Int, log: Log, place: Place)] {
        tripLogs.enumerated().compactMap { index, log in
            guard let place = places.first(where: { $0.id == log.placeID }) else { return nil }
            return (index: index, log: log, place: place)
        }
    }

    /// Route coordinates in visit order
    private var routeCoordinates: [CLLocationCoordinate2D] {
        chronologicalMapStops.map { $0.place.coordinate }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Route")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
                .padding(.horizontal, SonderSpacing.md)

            tripMapContent
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
                .padding(.horizontal, SonderSpacing.md)
        }
        .padding(.top, SonderSpacing.lg)
    }

    private var tripMapContent: some View {
        Map(position: $mapCameraPosition) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(SonderColors.terracotta.opacity(0.35), lineWidth: 2)
            }

            ForEach(chronologicalMapStops, id: \.log.id) { stop in
                Annotation(stop.place.name, coordinate: stop.place.coordinate) {
                    ZStack(alignment: .topTrailing) {
                        // Photo circle
                        photoPin(log: stop.log, place: stop.place)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(SonderColors.pinColor(for: stop.log.rating), lineWidth: 2.5)
                            }
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

                        // Number badge
                        Text("\(stop.index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(SonderColors.pinColor(for: stop.log.rating))
                            .clipShape(Circle())
                            .overlay { Circle().stroke(Color.white, lineWidth: 1.5) }
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .onAppear { updateMapRegion() }
    }

    @ViewBuilder
    private func photoPin(log: Log, place: Place) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 36, height: 36)) {
                placePinPhoto(place: place)
            }
        } else {
            placePinPhoto(place: place)
        }
    }

    @ViewBuilder
    private func placePinPhoto(place: Place) -> some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 100) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 36, height: 36)) {
                pinPhotoPlaceholder
            }
        } else {
            pinPhotoPlaceholder
        }
    }

    private var pinPhotoPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.md) {
            Text("The Story")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)
                .padding(.horizontal, SonderSpacing.md)

            if tripLogs.isEmpty {
                emptyLogsState
            } else {
                LazyVStack(spacing: SonderSpacing.lg) {
                    ForEach(Array(logsByDay.enumerated()), id: \.element.date) { _, dayGroup in
                        daySection(date: dayGroup.date, logs: dayGroup.logs)
                    }
                }
                .padding(.horizontal, SonderSpacing.md)
            }
        }
        .padding(.top, SonderSpacing.lg)
        .padding(.bottom, SonderSpacing.xxl)
    }

    private func daySection(date: Date, logs: [Log]) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Day header
            HStack(spacing: SonderSpacing.xs) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.terracotta)
                Text(date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(SonderTypography.subheadline)
                    .foregroundColor(SonderColors.inkMuted)
            }
            .padding(.leading, SonderSpacing.xxs)

            ForEach(logs, id: \.id) { log in
                if let place = places.first(where: { $0.id == log.placeID }) {
                    Button {
                        if let index = tripLogs.firstIndex(where: { $0.id == log.id }) {
                            storyStartIndex = index
                            showStoryPage = true
                        }
                    } label: {
                        MomentCard(log: log, place: place)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyLogsState: some View {
        VStack(spacing: SonderSpacing.sm) {
            Image(systemName: "book.pages")
                .font(.system(size: 40))
                .foregroundColor(SonderColors.inkLight)
            Text("No moments yet")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkMuted)
            Text("Log places and add them to this trip to build your story")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, SonderSpacing.lg)
    }

    // MARK: - Cover Photo Upload

    private func uploadCoverPhoto(_ image: UIImage) async {
        guard let userID = authService.currentUser?.id else { return }
        isUploadingCoverPhoto = true
        defer { isUploadingCoverPhoto = false }

        if let url = await photoService.uploadPhoto(image, for: userID) {
            trip.coverPhotoURL = url
            try? modelContext.save()
        }
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

// MARK: - Moment Card

private struct MomentCard: View {
    let log: Log
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo
            photoView
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()

            // Content
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                // Place name + rating pill
                HStack(alignment: .top) {
                    Text(place.name)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    ratingPill
                }

                // Address
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                    Text(place.address)
                        .lineLimit(1)
                }
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)

                // Note
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(SonderTypography.body)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                // Tags
                if !log.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SonderSpacing.xxs) {
                            ForEach(log.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.terracotta)
                                    .padding(.horizontal, SonderSpacing.xs)
                                    .padding(.vertical, 4)
                                    .background(SonderColors.terracotta.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Time
                Text(log.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(SonderColors.inkLight)
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
    }

    // MARK: - Rating Pill

    private var ratingPill: some View {
        HStack(spacing: 4) {
            Text(log.rating.emoji)
                .font(.system(size: 14))
            Text(log.rating.displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, SonderSpacing.xs)
        .padding(.vertical, 4)
        .background(SonderColors.pinColor(for: log.rating).opacity(0.15))
        .foregroundColor(SonderColors.pinColor(for: log.rating))
        .clipShape(Capsule())
    }

    // MARK: - Photo Chain

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 200)) {
                placePhotoView
            }
        } else {
            placePhotoView
        }
    }

    @ViewBuilder
    private var placePhotoView: some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 200)) {
                photoPlaceholder
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
                    .font(.title2)
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
