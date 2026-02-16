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
    @Environment(\.dismiss) private var dismiss
    @Query private var allLogs: [Log]
    @Query private var places: [Place]

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    let trip: Trip
    var onDelete: (() -> Void)? = nil

    @State private var showEditTrip = false
    @State private var showCollaborators = false
    @State private var showShareTrip = false
    @State private var showStoryPage = false
    @State private var storyStartIndex = 0
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showImagePicker = false
    @State private var isUploadingCoverPhoto = false
    @State private var logToRemoveFromTrip: Log?
    @State private var showExpandedMap = false
    @State private var dashPhase: CGFloat = 0
    @State private var selectedStopIndex: Int? = nil
    @State private var expandedMapCamera: MapCameraPosition = .automatic
    @State private var cardDragOffset: CGFloat = 0
    @State private var liveMapRegion: MKCoordinateRegion?
    @State private var cardPageIndex: Int = 0
    @State private var isWrapping = false
    @State private var showRouteLogDetail = false
    @State private var routeDetailLog: Log?
    @State private var routeDetailPlace: Place?

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

    /// O(1) place lookups — built once per render, shared by all sub-views
    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    /// Places for trip logs
    private var tripPlaces: [Place] {
        tripLogs.compactMap { placesByID[$0.placeID] }
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

                    Button {
                        showShareTrip = true
                    } label: {
                        Label("Share Trip", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditTrip) {
            CreateEditTripView(mode: .edit(trip), onDelete: {
                // Dismiss the edit sheet first
                showEditTrip = false
                // Then pop the detail view by clearing parent navigation state
                onDelete?()
                dismiss()
            })
        }
        .sheet(isPresented: $showCollaborators) {
            TripCollaboratorsView(trip: trip)
        }
        .sheet(isPresented: $showShareTrip) {
            ShareTripView(trip: trip, tripLogs: tripLogs, places: Array(places))
        }
        .fullScreenCover(isPresented: $showStoryPage) {
            TripStoryPageView(
                logs: tripLogs,
                places: Array(places),
                tripName: trip.name,
                startIndex: storyStartIndex
            )
        }
        .alert("Remove from Trip", isPresented: Binding(
            get: { logToRemoveFromTrip != nil },
            set: { if !$0 { logToRemoveFromTrip = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let log = logToRemoveFromTrip {
                    removeLogFromTrip(log)
                    logToRemoveFromTrip = nil
                }
            }
            Button("Cancel", role: .cancel) {
                logToRemoveFromTrip = nil
            }
        } message: {
            Text("This log will be moved to \"Not in a trip\" in your journal.")
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
        .fullScreenCover(isPresented: $showExpandedMap) {
            expandedMapView
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
            guard let place = placesByID[log.placeID] else { return nil }
            return (index: index, log: log, place: place)
        }
    }

    /// Route coordinates in visit order
    private var routeCoordinates: [CLLocationCoordinate2D] {
        chronologicalMapStops.map { $0.place.coordinate }
    }

    /// Curved route with bezier arcs between each pair of stops
    private var curvedRouteCoordinates: [CLLocationCoordinate2D] {
        let stops = routeCoordinates
        guard stops.count >= 2 else { return stops }

        var curved: [CLLocationCoordinate2D] = []
        for i in 0..<(stops.count - 1) {
            let start = stops[i]
            let end = stops[i + 1]

            // Perpendicular offset for the control point (arc bulge)
            let midLat = (start.latitude + end.latitude) / 2
            let midLng = (start.longitude + end.longitude) / 2
            let dLat = end.latitude - start.latitude
            let dLng = end.longitude - start.longitude

            // Alternate arc direction for a playful zigzag feel
            let sign: Double = i.isMultiple(of: 2) ? 1 : -1
            let controlLat = midLat + sign * dLng * 0.3
            let controlLng = midLng - sign * dLat * 0.3

            // Sample points along the quadratic bezier
            let segments = 20
            for t in 0...segments {
                let f = Double(t) / Double(segments)
                let oneMinusF = 1 - f
                let lat = oneMinusF * oneMinusF * start.latitude + 2 * oneMinusF * f * controlLat + f * f * end.latitude
                let lng = oneMinusF * oneMinusF * start.longitude + 2 * oneMinusF * f * controlLng + f * f * end.longitude
                curved.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }
        return curved
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
                .onTapGesture { showExpandedMap = true }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(SonderSpacing.md + SonderSpacing.xs)
                }
        }
        .padding(.top, SonderSpacing.lg)
    }

    /// Active route coordinates up to the selected stop
    private var activeRouteCoordinates: [CLLocationCoordinate2D] {
        guard let selectedIndex = selectedStopIndex,
              selectedIndex > 0,
              curvedRouteCoordinates.count >= 2 else { return [] }
        // Each segment between consecutive stops uses 21 points (0...20 inclusive)
        let endPoint = min(selectedIndex * 21 + 1, curvedRouteCoordinates.count)
        return Array(curvedRouteCoordinates.prefix(endPoint))
    }

    private var expandedMapView: some View {
        NavigationStack {
            Map(position: $expandedMapCamera, selection: $selectedStopIndex) {
                // Background route (full, faded)
                if curvedRouteCoordinates.count >= 2 {
                    MapPolyline(coordinates: curvedRouteCoordinates)
                        .stroke(SonderColors.terracotta.opacity(0.2), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6], dashPhase: dashPhase))
                }

                // Active segment (brighter, up to selected stop)
                if activeRouteCoordinates.count >= 2 {
                    MapPolyline(coordinates: activeRouteCoordinates)
                        .stroke(SonderColors.terracotta.opacity(0.6), lineWidth: 3)
                }

                ForEach(chronologicalMapStops, id: \.log.id) { stop in
                    let isSelected = selectedStopIndex == stop.index
                    Annotation(stop.place.name, coordinate: stop.place.coordinate) {
                        ZStack(alignment: .topTrailing) {
                            photoPin(log: stop.log, place: stop.place)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .stroke(SonderColors.pinColor(for: stop.log.rating), lineWidth: 2.5)
                                }
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

                            Text("\(stop.index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(SonderColors.pinColor(for: stop.log.rating))
                                .clipShape(Circle())
                                .overlay { Circle().stroke(Color.white, lineWidth: 1.5) }
                                .offset(x: 4, y: -4)
                        }
                        .scaleEffect(isSelected ? 1.25 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                    }
                    .tag(stop.index)
                }
            }
            .overlay(alignment: .bottom) {
                expandedMapBottomCard
                    .animation(.easeOut(duration: 0.2), value: selectedStopIndex)
            }
            .navigationTitle("Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectedStopIndex = nil
                        showExpandedMap = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
                    }
                }
            }
            .onMapCameraChange(frequency: .continuous) { context in
                liveMapRegion = context.region
            }
            .onAppear {
                initExpandedMapCamera()
                if !chronologicalMapStops.isEmpty {
                    cardPageIndex = 0
                    selectedStopIndex = 0
                    panToStop(at: 0)
                }
            }
            .onChange(of: selectedStopIndex) { _, newIndex in
                if let newIndex {
                    if !isWrapping {
                        cardPageIndex = newIndex
                    }
                    panToStop(at: newIndex)
                } else {
                    // Deselected — freeze camera at current position to cancel any in-flight animation
                    if let region = liveMapRegion {
                        withAnimation(nil) {
                            expandedMapCamera = .region(region)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showRouteLogDetail) {
                if let log = routeDetailLog, let place = routeDetailPlace {
                    LogDetailView(log: log, place: place)
                }
            }
        }
    }

    // MARK: - Expanded Map Bottom Card

    @ViewBuilder
    private var expandedMapBottomCard: some View {
        let stops = chronologicalMapStops
        let n = stops.count

        if selectedStopIndex != nil, n > 0 {
            TabView(selection: $cardPageIndex) {
                // Sentinel: clone of last stop (enables backward wrap from first)
                if n > 1, let lastStop = stops.last {
                    stopCard(stop: lastStop)
                        .tag(-1)
                }

                ForEach(stops, id: \.log.id) { stop in
                    stopCard(stop: stop)
                        .tag(stop.index)
                }

                // Sentinel: clone of first stop (enables forward wrap from last)
                if n > 1, let firstStop = stops.first {
                    stopCard(stop: firstStop)
                        .tag(n)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 120)
            .offset(y: max(0, cardDragOffset))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Vertical drag-to-dismiss (only downward)
                        if abs(value.translation.height) > abs(value.translation.width) && value.translation.height > 0 {
                            cardDragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedStopIndex = nil
                                cardDragOffset = 0
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                cardDragOffset = 0
                            }
                        }
                    }
            )
            .onChange(of: cardPageIndex) { _, newPage in
                guard n > 1 else { return }
                if newPage == -1 {
                    // Swiped backward from first → wrap to last
                    isWrapping = true
                    selectedStopIndex = n - 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            cardPageIndex = n - 1
                            isWrapping = false
                        }
                    }
                } else if newPage == n {
                    // Swiped forward from last → wrap to first
                    isWrapping = true
                    selectedStopIndex = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            cardPageIndex = 0
                            isWrapping = false
                        }
                    }
                } else {
                    selectedStopIndex = newPage
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func stopCard(stop: (index: Int, log: Log, place: Place)) -> some View {
        let place = stop.place
        let log = stop.log
        let totalStops = chronologicalMapStops.count
        let showChevrons = totalStops > 1

        return HStack(spacing: SonderSpacing.sm) {
            // Left chevron (always shown with 2+ stops for wrap-around)
            if showChevrons {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SonderColors.inkLight)
            }

            // Photo
            cachedCardPhoto(log: log, place: place)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                .overlay {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                        .stroke(SonderColors.pinColor(for: log.rating), lineWidth: 2)
                }

            // Text column
            VStack(alignment: .leading, spacing: 3) {
                Text("Stop \(stop.index + 1) of \(totalStops)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)

                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .lineLimit(1)

                HStack(spacing: SonderSpacing.xs) {
                    HStack(spacing: 4) {
                        Text(log.rating.emoji)
                            .font(.system(size: 14))
                        Text(log.rating.displayName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, SonderSpacing.xs)
                    .padding(.vertical, 3)
                    .background(SonderColors.pinColor(for: log.rating).opacity(0.15))
                    .foregroundColor(SonderColors.pinColor(for: log.rating))
                    .clipShape(Capsule())

                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // Right chevron (always shown with 2+ stops for wrap-around)
            if showChevrons {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SonderColors.inkLight)
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.sm)
        .background(SonderColors.cream.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
        .contentShape(Rectangle())
        .onTapGesture {
            routeDetailLog = stop.log
            routeDetailPlace = stop.place
            showRouteLogDetail = true
        }
    }

    // MARK: - Cached Card Photo

    /// Synchronous cache lookup for card photos — avoids the async fade-in of DownsampledAsyncImage
    /// so photos appear instantly during swipe transitions. Falls back to async loading if not cached.
    @ViewBuilder
    private func cachedCardPhoto(log: Log, place: Place) -> some View {
        if let image = cachedImage(for: log, place: place) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Not cached yet — fall back to async loading
            photoPin(log: log, place: place)
        }
    }

    private static let cardPhotoPointSize = CGSize(width: 56, height: 56)

    private func cachedImage(for log: Log, place: Place) -> UIImage? {
        let pointSize = Self.cardPhotoPointSize
        // 1. User's log photo
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            let key = ImageDownsampler.cacheKey(for: url, pointSize: pointSize)
            if let cached = ImageDownsampler.cache.object(forKey: key) {
                return cached
            }
        }
        // 2. Google Places photo
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 100) {
            let key = ImageDownsampler.cacheKey(for: url, pointSize: pointSize)
            if let cached = ImageDownsampler.cache.object(forKey: key) {
                return cached
            }
        }
        return nil
    }

    // MARK: - Expanded Map Helpers

    private func initExpandedMapCamera() {
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
        expandedMapCamera = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        ))
    }

    private func panToStop(at index: Int) {
        guard let stop = chronologicalMapStops.first(where: { $0.index == index }) else { return }
        let currentSpan = expandedMapCamera.region?.span ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        let latOffset = currentSpan.latitudeDelta * 0.18
        let offsetCenter = CLLocationCoordinate2D(
            latitude: stop.place.coordinate.latitude - latOffset,
            longitude: stop.place.coordinate.longitude
        )
        withAnimation(.smooth(duration: 0.4)) {
            expandedMapCamera = .region(MKCoordinateRegion(
                center: offsetCenter,
                span: currentSpan
            ))
        }
    }

    private var tripMapContent: some View {
        Map(position: $mapCameraPosition, interactionModes: []) {
            if curvedRouteCoordinates.count >= 2 {
                MapPolyline(coordinates: curvedRouteCoordinates)
                    .stroke(SonderColors.terracotta.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6], dashPhase: dashPhase))
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
        .onAppear {
            updateMapRegion()
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                dashPhase = -28
            }
        }
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
                if let place = placesByID[log.placeID] {
                    NavigationLink {
                        LogDetailView(log: log, place: place)
                    } label: {
                        MomentCard(log: log, place: place)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            logToRemoveFromTrip = log
                        } label: {
                            Label("Remove from Trip", systemImage: "minus.circle")
                        }
                    }
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

    private func removeLogFromTrip(_ log: Log) {
        withAnimation(.easeOut(duration: 0.25)) {
            log.tripID = nil
            log.updatedAt = Date()
            try? modelContext.save()
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Helpers

    private var dateRangeText: String? {
        if let start = trip.startDate, let end = trip.endDate {
            return "\(Self.mediumDateFormatter.string(from: start)) - \(Self.mediumDateFormatter.string(from: end))"
        } else if let start = trip.startDate {
            return "From \(Self.mediumDateFormatter.string(from: start))"
        } else if let end = trip.endDate {
            return "Until \(Self.mediumDateFormatter.string(from: end))"
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
