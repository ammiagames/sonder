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
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var allLogs: [Log] = []
    @Query private var places: [Place]

    let trip: Trip
    var onDelete: (() -> Void)? = nil

    @State private var showEditTrip = false
    @State private var showShareTrip = false
    @State private var showStoryPage = false
    @State private var storyStartIndex = 0
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showImagePicker = false
    @State private var isUploadingCoverPhoto = false
    @State private var logToRemoveFromTrip: Log?
    @State private var showExpandedMap = false
    @State private var selectedStopIndex: Int? = nil
    @State private var expandedMapCamera: MapCameraPosition = .automatic
    @State private var cardDragOffset: CGFloat = 0
    @State private var liveMapRegion: MKCoordinateRegion?
    @State private var cardPageIndex: Int = 0
    @State private var isWrapping = false
    @State private var showRouteLogDetail = false
    @State private var routeDetailLog: Log?
    @State private var routeDetailPlace: Place?
    @State private var showReorder = false
    @State private var showBulkImport = false
    @State private var cardWrapTask: Task<Void, Never>?
    @State private var measuredViewWidth: CGFloat = 0


    // MARK: - Capsule Spacing Constants
    private let sectionGap: CGFloat = 56
    private let entryGap: CGFloat = 48
    private let contentPadding: CGFloat = 24
    private let narrowColumn: CGFloat = 40
    private let breathingRoom: CGFloat = 80

    // Cached computed data — rebuilt only when inputs change (via refreshLogs)
    @State private var cachedTripLogs: [Log] = []
    @State private var cachedLogsByDay: [(date: Date, logs: [Log])] = []
    @State private var cachedPlacesByID: [String: Place] = [:]
    @State private var cachedTripPlaces: [Place] = []
    @State private var cachedRatingCounts: (mustSee: Int, great: Int, okay: Int, skip: Int) = (0, 0, 0, 0)
    @State private var cachedTripDayCount: Int = 1

    /// Logs belonging to this trip, sorted by user-defined order (tripSortOrder) then visitedAt
    private var tripLogs: [Log] { cachedTripLogs }

    private func refreshLogs() {
        let tripID = trip.id
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.tripID == tripID }
        )
        allLogs = (try? modelContext.fetch(descriptor)) ?? []
        rebuildDerivedCaches()
    }

    private func rebuildDerivedCaches() {
        // Sorted trip logs
        let sorted = allLogs.sorted {
            if let a = $0.tripSortOrder, let b = $1.tripSortOrder {
                return a < b
            }
            return $0.visitedAt < $1.visitedAt
        }
        cachedTripLogs = sorted

        // Logs by day
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { log in
            calendar.startOfDay(for: log.visitedAt)
        }
        cachedLogsByDay = grouped.sorted { $0.key < $1.key }
            .map { (date: $0.key, logs: $0.value) }

        // Place lookup
        let placeMap = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cachedPlacesByID = placeMap

        // Trip places
        cachedTripPlaces = sorted.compactMap { placeMap[$0.placeID] }

        // Rating counts
        var mustSee = 0, great = 0, okay = 0, skip = 0
        for log in sorted {
            switch log.rating {
            case .mustSee: mustSee += 1
            case .great: great += 1
            case .okay: okay += 1
            case .skip: skip += 1
            }
        }
        cachedRatingCounts = (mustSee, great, okay, skip)

        // Day count
        if let start = trip.startDate, let end = trip.endDate {
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            cachedTripDayCount = max(1, days + 1)
        } else {
            cachedTripDayCount = max(1, Set(sorted.map { calendar.startOfDay(for: $0.createdAt) }).count)
        }
    }

    /// Whether any log in this trip has a custom sort order (user reordered)
    private var isCustomOrdered: Bool {
        cachedTripLogs.contains { $0.tripSortOrder != nil }
    }

    /// Logs grouped by calendar day (visitedAt), sorted ascending. Only used in chronological mode.
    private var logsByDay: [(date: Date, logs: [Log])] { cachedLogsByDay }

    /// O(1) place lookups — built once, shared by all sub-views
    private var placesByID: [String: Place] { cachedPlacesByID }

    /// Places for trip logs
    private var tripPlaces: [Place] { cachedTripPlaces }

    private var isOwner: Bool {
        trip.createdBy == authService.currentUser?.id
    }

    private var tripDayCount: Int { cachedTripDayCount }

    private var ratingCounts: (mustSee: Int, great: Int, okay: Int, skip: Int) { cachedRatingCounts }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                capsuleCover
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear { measuredViewWidth = geo.size.width }
                        }
                    )

                if let description = displayTripDescription {
                    tripDescriptionSection(description)
                }

                if !tripLogs.isEmpty {
                    capsuleOverview
                }

                // Trip personality — witty auto-generated insight
                if tripLogs.count >= 3 {
                    tripPersonality
                }

                // Mood arc — emotional shape of the trip
                if tripLogs.count >= 3 {
                    moodArc
                }

                if !tripPlaces.isEmpty {
                    mapSection
                }

                // Pull quote — the most evocative note, blown up
                pullQuote

                // "Your trip began at..." bookend
                firstStopBookend

                timelineSection

                // "Your last stop was..." bookend
                lastStopBookend

                if !tripLogs.isEmpty {
                    capsuleClosing
                }
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isOwner {
                    Button {
                        showBulkImport = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(SonderColors.terracotta)
                            .toolbarIcon()
                    }
                    .accessibilityLabel("Import from Photos")

                    Button {
                        showReorder = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(tripLogs.count >= 2 ? SonderColors.terracotta : SonderColors.inkLight)
                            .toolbarIcon()
                    }
                    .disabled(tripLogs.isEmpty)
                    .accessibilityLabel("Manage stops")

                    Button {
                        showEditTrip = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(SonderColors.terracotta)
                            .toolbarIcon()
                    }
                    .accessibilityLabel("Edit trip")
                }

                Button {
                    showShareTrip = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(SonderColors.terracotta)
                        .toolbarIcon()
                }
                .accessibilityLabel("Share trip")
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
        .sheet(isPresented: $showReorder) {
            ReorderTripLogsSheet(
                tripLogs: tripLogs,
                placesByID: placesByID,
                modelContext: modelContext,
                syncEngine: syncEngine
            )
        }
        .fullScreenCover(isPresented: $showExpandedMap) {
            expandedMapView
        }
        .fullScreenCover(isPresented: $showBulkImport) {
            BulkPhotoImportView(tripID: trip.id, tripName: trip.name)
        }
        .onChange(of: showBulkImport) { _, isShowing in
            if !isShowing { refreshLogs() }
        }
    }

    // MARK: - Act 1: The Cover

    private var capsuleCover: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed hero photo sized to actual screen width
            GeometryReader { geo in
                if let urlString = trip.coverPhotoURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: geo.size.width, height: geo.size.height)) {
                        coverGradientPlaceholder
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .id(urlString)
                } else {
                    coverGradientPlaceholder
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            // Gradient scrim
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.3), .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Title stack
            VStack(spacing: 8) {
                // Location subtitle
                if let location = tripLocationText {
                    Text(location.uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(3.0)
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Trip name
                Text(trip.name)
                    .font(.system(size: 36, weight: .light, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Date stamp
                if let dateText = coverDateStamp {
                    Text(dateText.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(3.0)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.bottom, 48)
        }
        .frame(height: 480)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if isOwner {
                Button {
                    showImagePicker = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(contentPadding)
            }
        }
        .overlay {
            if isUploadingCoverPhoto {
                Color.black.opacity(0.4)
                ProgressView()
                    .tint(.white)
            }
        }
        .task { refreshLogs() }
        .onChange(of: syncEngine.lastSyncDate) { _, _ in refreshLogs() }
        .onChange(of: places.count) { _, _ in rebuildDerivedCaches() }
        .onAppear {
            SonderHaptics.impact(.soft)
        }
    }

    private var coverGradientPlaceholder: some View {
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
            .overlay {
                VStack(spacing: SonderSpacing.sm) {
                    Image(systemName: "suitcase.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.4))
                    if isOwner {
                        Text("Tap camera to add a cover photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
    }

    /// Simplified location text for the cover
    private var tripLocationText: String? {
        // Use first place's simplified address as location
        if let firstPlace = tripPlaces.first {
            let parts = firstPlace.address.components(separatedBy: ", ")
            if parts.count >= 2 {
                return parts.suffix(2).joined(separator: ", ")
            }
            return firstPlace.address
        }
        return nil
    }

    private static let coverDateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Date stamp for cover in a compact format
    private var coverDateStamp: String? {
        let formatter = Self.coverDateStampFormatter
        if let start = trip.startDate {
            return formatter.string(from: start)
        }
        if let firstLog = tripLogs.first {
            return formatter.string(from: firstLog.visitedAt)
        }
        return nil
    }

    private var displayTripDescription: String? {
        guard let raw = trip.tripDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    // MARK: - Description

    private func tripDescriptionSection(_ description: String) -> some View {
        descStyle1(description)
            .padding(.vertical, sectionGap * 0.3)
    }

    // Quote marks style
    private func descStyle1(_ description: String) -> some View {
        Text(description)
            .font(.system(size: 16, design: .serif))
            .foregroundStyle(SonderColors.inkMuted)
            .lineSpacing(7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, narrowColumn + 4)
            .padding(.vertical, sectionGap * 0.45)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Text("\u{201C}")
                    .font(.system(size: 72, weight: .light, design: .serif))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.22))
                    .offset(x: contentPadding, y: -8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\u{201D}")
                    .font(.system(size: 72, weight: .light, design: .serif))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.22))
                    .offset(x: -contentPadding, y: 8)
                    .allowsHitTesting(false)
            }
    }

    // MARK: - Act 2: Overview

    private var capsuleOverview: some View {
        VStack(spacing: sectionGap) {
            // Stats row — Wrapped style
            HStack(spacing: SonderSpacing.xxl) {
                overviewStat(value: "\(tripLogs.count)", label: tripLogs.count == 1 ? "place" : "places")
                overviewStat(value: "\(tripDayCount)", label: tripDayCount == 1 ? "day" : "days")
                if Set(tripPlaces.map { simplifiedCity(from: $0.address) }).count > 1 {
                    overviewStat(value: "\(Set(tripPlaces.map { simplifiedCity(from: $0.address) }).count)", label: "cities")
                }
            }

            // Top-rated highlight pill
            if let topPlace = tripLogs.first(where: { $0.rating == .mustSee }),
               let place = placesByID[topPlace.placeID] {
                Text("Top-rated: \(place.name)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SonderColors.terracotta)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(SonderColors.terracotta.opacity(0.1))
                    .clipShape(Capsule())
            }

        }
        .padding(.vertical, sectionGap)
        .padding(.horizontal, contentPadding)
        .frame(maxWidth: .infinity)
    }


    private func overviewStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 42, weight: .bold, design: .serif))
                .foregroundStyle(SonderColors.inkDark)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(2.0)
                .foregroundStyle(SonderColors.inkLight)
        }
    }

    private func simplifiedCity(from address: String) -> String {
        let parts = address.components(separatedBy: ", ")
        if parts.count >= 2 {
            return parts[parts.count - 2]
        }
        return address
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
                .foregroundStyle(SonderColors.inkDark)
                .padding(.horizontal, SonderSpacing.md)

            Button { showExpandedMap = true } label: {
                tripMapContent
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SonderColors.inkDark)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(SonderSpacing.md + SonderSpacing.xs)
                    }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SonderSpacing.md)
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
                        .stroke(SonderColors.terracotta.opacity(0.2), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6], dashPhase: 0))
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
                                .foregroundStyle(.white)
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
                        cardWrapTask?.cancel()
                        selectedStopIndex = nil
                        showExpandedMap = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SonderColors.inkDark)
                            .toolbarIcon()
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
                    LogViewScreen(log: log, place: place)
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
            .frame(height: 500)
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
                    cardWrapTask?.cancel()
                    cardWrapTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
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
                    cardWrapTask?.cancel()
                    cardWrapTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
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

        let hasPhoto = log.photoURL != nil

        return VStack(spacing: 0) {
            // Pushes card to the bottom of the fixed-height TabView frame
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
            // Hero photo — height based on cached image aspect ratio
            if hasPhoto {
                cachedCardPhoto(log: log, place: place)
                    .frame(height: computedPhotoHeight(for: log, place: place))
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            // Content
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                // Navigation header
                HStack {
                    if showChevrons {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SonderColors.inkLight)
                    }

                    Text("Stop \(stop.index + 1) of \(totalStops)")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)

                    Spacer()

                    Text(log.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)

                    if showChevrons {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SonderColors.inkLight)
                    }
                }

                // Place name + rating pill
                HStack(alignment: .top) {
                    Text(place.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(log.rating.emoji)
                            .font(.system(size: 14))
                        Text(log.rating.displayName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, SonderSpacing.xs)
                    .padding(.vertical, 3)
                    .background(SonderColors.pinColor(for: log.rating).opacity(0.15))
                    .foregroundStyle(SonderColors.pinColor(for: log.rating))
                    .clipShape(Capsule())
                }

                // Address
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                    Text(place.address)
                        .lineLimit(1)
                }
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)

                // Note with terracotta accent bar
                if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    HStack(alignment: .top, spacing: SonderSpacing.xs) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(SonderColors.terracotta.opacity(0.4))
                            .frame(width: 3)

                        Text(note)
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Tags
                if !log.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SonderSpacing.xxs) {
                            ForEach(log.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.terracotta)
                                    .padding(.horizontal, SonderSpacing.xs)
                                    .padding(.vertical, 4)
                                    .background(SonderColors.terracotta.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .padding(SonderSpacing.md)
            }
            .background(SonderColors.cream.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)
            .onTapGesture {
                routeDetailLog = stop.log
                routeDetailPlace = stop.place
                showRouteLogDetail = true
            }
        }
    }

    /// Computes photo display height for stop cards based on cached image aspect ratio.
    /// Uses the image's natural height at card width, capped at 220pt.
    /// Falls back to 160pt for uncached/async images.
    private func computedPhotoHeight(for log: Log, place: Place) -> CGFloat {
        let cardWidth = (measuredViewWidth > 0 ? measuredViewWidth : 390) - SonderSpacing.md * 2
        let maxHeight: CGFloat = 220
        if let image = cachedImage(for: log, place: place) {
            guard image.size.width > 0 else { return maxHeight }
            let ratio = image.size.height / image.size.width
            return min(cardWidth * ratio, maxHeight)
        }
        return 160
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
            // Not cached yet — fall back to async loading at hero size
            heroAsyncPhoto(log: log, place: place)
        }
    }

    /// Async photo loader sized for the hero card (not the tiny 36×36 map pins).
    @ViewBuilder
    private func heroAsyncPhoto(log: Log, place: Place) -> some View {
        let heroSize = Self.cardPhotoPointSize
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: heroSize) {
                Rectangle().fill(SonderColors.warmGray)
            }
        } else {
            heroPlacePhoto(place: place)
        }
    }

    @ViewBuilder
    private func heroPlacePhoto(place: Place) -> some View {
        let heroSize = Self.cardPhotoPointSize
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
            DownsampledAsyncImage(url: url, targetSize: heroSize) {
                Rectangle().fill(SonderColors.warmGray)
            }
        }
    }

    private static let cardPhotoPointSize = CGSize(width: 300, height: 140)

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
        let latOffset = currentSpan.latitudeDelta * 0.30
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
                    .stroke(SonderColors.terracotta.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6], dashPhase: 0))
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
                            .foregroundStyle(.white)
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
                SonderColors.placeholderGradient
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

    // MARK: - Act 3: The Days

    private var timelineSection: some View {
        VStack(spacing: 0) {
            if tripLogs.isEmpty {
                emptyLogsState
            } else if isCustomOrdered {
                // Custom order: numbered stops
                VStack(spacing: 0) {
                    ForEach(Array(tripLogs.enumerated()), id: \.element.id) { index, log in
                        if let place = placesByID[log.placeID] {
                            NavigationLink {
                                LogViewScreen(log: log, place: place)
                            } label: {
                                EditorialRailEntry(log: log, place: place, stopNumber: index + 1)
                            }
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .scrollTransition(.animated(.easeOut(duration: 0.4)).threshold(.visible(0.3))) { content, phase in
                                content
                                    .opacity(phase == .bottomTrailing ? 0 : (phase.isIdentity ? 1 : 0.85))
                                    .offset(y: phase == .bottomTrailing ? 24 : 0)
                            }
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
            } else {
                // Chronological: day-grouped chapters
                VStack(spacing: sectionGap) {
                    ForEach(Array(logsByDay.enumerated()), id: \.element.date) { dayIndex, dayGroup in
                        capsuleDaySection(
                            dayNumber: dayIndex + 1,
                            date: dayGroup.date,
                            logs: dayGroup.logs
                        )
                    }
                }
            }
        }
        .padding(.bottom, sectionGap)
    }

    private func capsuleDaySection(dayNumber: Int, date: Date, logs: [Log]) -> some View {
        VStack(spacing: 0) {
            // Day header — editorial chapter divider
            VStack(spacing: 8) {
                Text(date.formatted(.dateTime.month(.wide).day().year()).uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(4.0)
                    .foregroundStyle(SonderColors.inkLight)

                Text(dayTitle(for: dayNumber))
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, sectionGap)
            .padding(.bottom, SonderSpacing.xxl)
            .scrollTransition(.animated(.easeOut(duration: 0.5))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .offset(y: phase.isIdentity ? 0 : 20)
            }
            .onAppear {
                SonderHaptics.selectionChanged()
            }

            // Place entries with connective tissue
            let sortedDayLogs = logs.sorted { $0.visitedAt < $1.visitedAt }
            ForEach(Array(sortedDayLogs.enumerated()), id: \.element.id) { index, log in
                // Connective tissue — elapsed time between entries
                if index > 0 {
                    railConnector(from: sortedDayLogs[index - 1].visitedAt, to: log.visitedAt)
                }

                if let place = placesByID[log.placeID] {
                    NavigationLink {
                        LogViewScreen(log: log, place: place)
                    } label: {
                        EditorialRailEntry(log: log, place: place)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .scrollTransition(.animated(.easeOut(duration: 0.4)).threshold(.visible(0.3))) { content, phase in
                        content
                            .opacity(phase == .bottomTrailing ? 0 : (phase.isIdentity ? 1 : 0.85))
                            .offset(y: phase == .bottomTrailing ? 24 : 0)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            logToRemoveFromTrip = log
                        } label: {
                            Label("Remove from Trip", systemImage: "minus.circle")
                        }
                    }
                }
            }

            // Photo filmstrip — visual breather at end of each day
            dayPhotoStrip(logs: logs)

            // Day-end summary
            dayEndSummary(logs: logs)
        }
    }

    // MARK: - Day Photo Filmstrip

    /// Collects all photos for a day's logs (user photos + Google Places fallbacks) into a
    /// horizontal filmstrip. Each frame shows the photo with a time-of-day label underneath.
    @ViewBuilder
    private func dayPhotoStrip(logs: [Log]) -> some View {
        let frames = filmstripFrames(for: logs)

        if frames.count >= 2 {
            VStack(spacing: 10) {
                // Thin rule above
                Rectangle()
                    .fill(SonderColors.warmGrayDark.opacity(0.15))
                    .frame(width: 24, height: 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(frames) { frame in
                            filmstripFrame(frame)
                        }
                    }
                    .padding(.horizontal, contentPadding)
                }
                .scrollClipDisabled()

                // Caption
                Text("\(frames.count) moments".uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2.0)
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(.top, SonderSpacing.md)
            .scrollTransition(.animated(.easeOut(duration: 0.4))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
            }
        }
    }

    private func filmstripFrame(_ frame: FilmstripFrame) -> some View {
        VStack(spacing: 4) {
            DownsampledAsyncImage(url: frame.url, targetSize: CGSize(width: 120, height: 160)) {
                Rectangle().fill(SonderColors.warmGray)
            }
            .aspectRatio(3/4, contentMode: .fill)
            .frame(width: 100, height: 133)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(frame.timeLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(SonderColors.inkLight)
        }
    }

    /// Build the ordered list of photo frames for a given day's logs.
    private func filmstripFrames(for logs: [Log]) -> [FilmstripFrame] {
        var frames: [FilmstripFrame] = []

        for log in logs.sorted(by: { $0.visitedAt < $1.visitedAt }) {
            let timeLabel = log.visitedAt.formatted(.dateTime.hour().minute())
            let place = placesByID[log.placeID]

            // User photos first
            for urlString in log.userPhotoURLs {
                if let url = URL(string: urlString) {
                    frames.append(FilmstripFrame(url: url, timeLabel: timeLabel))
                }
            }

            // Google Places fallback if user has no photos
            if log.userPhotoURLs.isEmpty,
               let photoRef = place?.photoReference,
               let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 400) {
                frames.append(FilmstripFrame(url: url, timeLabel: timeLabel))
            }
        }

        return frames
    }

    // MARK: - Connective Tissue (Time Gaps)

    private func timeGapText(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min later"
        } else {
            let hours = minutes / 60
            let remaining = minutes % 60
            if remaining == 0 {
                return "\(hours)h later"
            }
            return "\(hours)h \(remaining)m later"
        }
    }

    // MARK: - Rail Connector

    private let railWidth: CGFloat = 48

    @ViewBuilder
    private func railConnector(from previous: Date, to current: Date) -> some View {
        let minutes = Int(current.timeIntervalSince(previous) / 60)

        HStack(alignment: .center, spacing: 0) {
            // Rail continuation line
            Rectangle()
                .fill(SonderColors.terracotta.opacity(0.25))
                .frame(width: 2, height: 20)
                .frame(width: railWidth)

            // Elapsed time label
            if minutes >= 10 {
                Text(timeGapText(minutes: minutes))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SonderColors.inkLight)
                    .padding(.leading, 4)
            }

            Spacer()
        }
    }

    // MARK: - Day-End Summary

    @ViewBuilder
    private func dayEndSummary(logs: [Log]) -> some View {
        let summary = dayEndSummaryText(logs: logs)

        if logs.count >= 2, !summary.isEmpty {
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SonderColors.inkLight)
                .frame(maxWidth: .infinity)
                .padding(.top, SonderSpacing.sm)
        }
    }

    private func dayEndSummaryText(logs: [Log]) -> String {
        var mustSees = 0, greats = 0, okays = 0, skips = 0
        for log in logs {
            switch log.rating {
            case .mustSee: mustSees += 1
            case .great: greats += 1
            case .okay: okays += 1
            case .skip: skips += 1
            }
        }

        var parts: [String] = []
        if mustSees > 0 { parts.append("\(mustSees) must-\(mustSees == 1 ? "see" : "sees")") }
        if greats > 0 { parts.append("\(greats) great") }
        if okays > 0 { parts.append("\(okays) okay") }
        if skips > 0 { parts.append("\(skips) \(skips == 1 ? "skip" : "skips")") }

        guard !parts.isEmpty else { return "" }
        return "\(logs.count) places \u{2014} \(parts.joined(separator: ", "))"
    }

    // MARK: - Pull Quote

    /// The most evocative note from the trip, displayed as a large editorial quote.
    @ViewBuilder
    private var pullQuote: some View {
        if let quote = bestPullQuote {
            VStack(spacing: 12) {
                Rectangle()
                    .fill(SonderColors.terracotta.opacity(0.3))
                    .frame(width: 24, height: 2)

                Text("\u{201C}\(quote.note)\u{201D}")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .italic()
                    .foregroundStyle(SonderColors.inkDark)
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)

                Text("— \(quote.placeName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SonderColors.inkMuted)
            }
            .padding(.horizontal, narrowColumn)
            .padding(.vertical, sectionGap)
            .frame(maxWidth: .infinity)
            .scrollTransition(.animated(.easeOut(duration: 0.5))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .offset(y: phase.isIdentity ? 0 : 16)
            }
        }
    }

    /// Finds the best note to use as a pull quote — prefers must-see rated, then longest note.
    private var bestPullQuote: (note: String, placeName: String)? {
        let candidates = tripLogs.compactMap { log -> (note: String, placeName: String, rating: Rating)? in
            guard let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  note.count >= 20 else { return nil }
            let name = placesByID[log.placeID]?.name ?? "Unknown"
            return (note: note, placeName: name, rating: log.rating)
        }

        // Prefer must-see notes, then pick the longest
        let mustSeeNotes = candidates.filter { $0.rating == .mustSee }
        let pool = mustSeeNotes.isEmpty ? candidates : mustSeeNotes
        return pool.max(by: { $0.note.count < $1.note.count }).map { (note: $0.note, placeName: $0.placeName) }
    }

    // MARK: - Trip Personality

    /// Auto-generated witty insight about the trip's character.
    @ViewBuilder
    private var tripPersonality: some View {
        let insight = generateTripPersonality()
        if !insight.isEmpty {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(SonderColors.warmGrayDark.opacity(0.15))
                    .frame(width: 24, height: 1)

                Text(insight)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .padding(.horizontal, narrowColumn)
            .padding(.vertical, SonderSpacing.xxl)
            .frame(maxWidth: .infinity)
            .scrollTransition(.animated(.easeOut(duration: 0.4))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
            }
        }
    }

    private func generateTripPersonality() -> String {
        guard tripLogs.count >= 3 else { return "" }

        let sorted = tripLogs.sorted { $0.visitedAt < $1.visitedAt }
        let counts = ratingCounts
        let mustSees = counts.mustSee
        let skips = counts.skip
        let total = tripLogs.count

        // Tag frequency
        let allTags = tripLogs.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: allTags, by: { $0.lowercased() }).mapValues { $0.count }
        let topTag = tagCounts.max(by: { $0.value < $1.value })

        // Time patterns
        let hours = sorted.map { Calendar.current.component(.hour, from: $0.visitedAt) }
        let morningCount = hours.filter { $0 >= 6 && $0 < 12 }.count
        let eveningCount = hours.filter { $0 >= 18 }.count
        let nightCount = hours.filter { $0 >= 21 || $0 < 5 }.count

        // Notes analysis
        let notesCount = tripLogs.filter {
            ($0.note?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 10
        }.count

        // Build personality string from the most interesting pattern
        var insights: [String] = []

        // Must-see ratio personality
        let mustSeeRatio = Double(mustSees) / Double(total)
        if mustSeeRatio >= 0.6 {
            insights.append("A trip where almost everything hit. You have great taste — or great luck.")
        } else if mustSeeRatio == 0 && total >= 4 {
            insights.append("Not a single must-see, but the journey was the point, wasn't it?")
        } else if skips > mustSees && skips >= 2 {
            insights.append("More skips than must-sees. An honest trip — not everything needs to be perfect.")
        }

        // Tag-based personality
        if let tag = topTag, tag.value >= 3 {
            insights.append("You visited \(tag.value) \(tag.key) spots. Committed to the theme.")
        } else if let tag = topTag, tag.value >= 2 {
            insights.append("A \(tag.key)-forward trip, with range.")
        }

        // Time-based personality
        if nightCount >= 3 {
            insights.append("A late-night trip. The best things happen after dark.")
        } else if morningCount > eveningCount && morningCount >= 3 {
            insights.append("An early riser's trip. First in line, best light.")
        } else if eveningCount >= total / 2 && eveningCount >= 3 {
            insights.append("An evening person's trip. Golden hour and beyond.")
        }

        // Note-writing personality
        if notesCount >= total / 2 && notesCount >= 3 {
            insights.append("You wrote notes at most stops. A trip worth remembering in detail.")
        }

        // Pick the most interesting one (prefer tag-based or time-based over generic ratio)
        if insights.count > 1 {
            // Prefer the middle entries (tag/time) over the first (ratio)
            return insights.count > 2 ? insights[1] : insights.last ?? ""
        }
        return insights.first ?? ""
    }

    // MARK: - Mood Arc

    /// A minimal dot-graph showing the emotional shape of the trip — ratings plotted over time.
    private var moodArc: some View {
        VStack(spacing: 12) {
            Text("YOUR TRIP'S MOOD")
                .font(.system(size: 10, weight: .medium))
                .tracking(2.0)
                .foregroundStyle(SonderColors.inkLight)

            GeometryReader { geo in
                let points = moodArcPoints(in: geo.size)
                let linePoints = points.map { $0.point }

                ZStack {
                    // Connecting line
                    if linePoints.count >= 2 {
                        Path { path in
                            path.move(to: linePoints[0])
                            for i in 1..<linePoints.count {
                                // Smooth curve between points
                                let prev = linePoints[i - 1]
                                let curr = linePoints[i]
                                let midX = (prev.x + curr.x) / 2
                                path.addCurve(
                                    to: curr,
                                    control1: CGPoint(x: midX, y: prev.y),
                                    control2: CGPoint(x: midX, y: curr.y)
                                )
                            }
                        }
                        .stroke(
                            SonderColors.terracotta.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                    }

                    // Dots
                    ForEach(points) { point in
                        Circle()
                            .fill(point.color)
                            .frame(width: 8, height: 8)
                            .position(point.point)
                    }
                }
            }
            .frame(height: 60)
            .padding(.horizontal, contentPadding)
        }
        .padding(.vertical, sectionGap / 2)
        .frame(maxWidth: .infinity)
        .scrollTransition(.animated(.easeOut(duration: 0.4))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
        }
    }

    private func moodArcPoints(in size: CGSize) -> [MoodArcPoint] {
        guard !tripLogs.isEmpty else { return [] }

        let sorted = tripLogs.sorted { $0.visitedAt < $1.visitedAt }
        let count = sorted.count
        let insetX: CGFloat = 16
        let usableWidth = size.width - insetX * 2
        let topPad: CGFloat = 8
        let bottomPad: CGFloat = 8
        let usableHeight = size.height - topPad - bottomPad

        return sorted.enumerated().map { index, log in
            let x = count == 1 ? size.width / 2 : insetX + usableWidth * CGFloat(index) / CGFloat(count - 1)

            // Map rating to y position: mustSee = top, skip = bottom
            let yNormalized: CGFloat = switch log.rating {
            case .mustSee: 0.0
            case .great: 0.3
            case .okay: 0.6
            case .skip: 1.0
            }

            let y = topPad + usableHeight * yNormalized
            let color = SonderColors.pinColor(for: log.rating)

            return MoodArcPoint(
                id: log.id,
                point: CGPoint(x: x, y: y),
                color: color
            )
        }
    }

    // MARK: - First & Last Bookends

    @ViewBuilder
    private var firstStopBookend: some View {
        if let firstLog = tripLogs.sorted(by: { $0.visitedAt < $1.visitedAt }).first,
           let place = placesByID[firstLog.placeID] {
            VStack(spacing: 6) {
                Text("Your trip began at")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(SonderColors.inkMuted)

                Text(place.name)
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.xxl)
            .scrollTransition(.animated(.easeOut(duration: 0.4))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .offset(y: phase.isIdentity ? 0 : 12)
            }
        }
    }

    @ViewBuilder
    private var lastStopBookend: some View {
        let sorted = tripLogs.sorted { $0.visitedAt < $1.visitedAt }
        if sorted.count >= 2,
           let lastLog = sorted.last,
           let place = placesByID[lastLog.placeID] {
            VStack(spacing: 6) {
                Text("Your last stop was")
                    .font(.system(size: 14, weight: .light, design: .serif))
                    .foregroundStyle(SonderColors.inkMuted)

                Text(place.name)
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.xxl)
            .scrollTransition(.animated(.easeOut(duration: 0.4))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .offset(y: phase.isIdentity ? 0 : 12)
            }
        }
    }

    private func dayTitle(for dayNumber: Int) -> String {
        let words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven",
                     "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen"]
        let number = dayNumber <= words.count ? words[dayNumber - 1] : "\(dayNumber)"
        return "Day \(number)"
    }

    private var emptyLogsState: some View {
        VStack(spacing: SonderSpacing.sm) {
            Image(systemName: "book.pages")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.inkLight)
            Text("No moments yet")
                .font(.system(size: 20, weight: .light, design: .serif))
                .foregroundStyle(SonderColors.inkMuted)
            Text("Log places and add them to this trip to build your story")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, breathingRoom)
        .padding(.horizontal, contentPadding)
    }

    // MARK: - Act 5: The Closing

    private var capsuleClosing: some View {
        VStack(spacing: SonderSpacing.xxl) {
            // Thin divider
            Rectangle()
                .fill(SonderColors.warmGrayDark.opacity(0.3))
                .frame(width: 40, height: 1)

            // Date + location
            VStack(spacing: 6) {
                if let dateText = coverDateStamp {
                    Text(dateText.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(3.0)
                        .foregroundStyle(SonderColors.inkLight)
                }
                if let location = tripLocationText {
                    Text(location)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }

            // Stats
            VStack(spacing: SonderSpacing.lg) {
                Text("\(tripLogs.count)")
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                Text("places explored".uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2.0)
                    .foregroundStyle(SonderColors.inkLight)
            }

            // Rating breakdown
            VStack(spacing: SonderSpacing.xs) {
                if ratingCounts.mustSee > 0 {
                    closingRatingRow(emoji: Rating.mustSee.emoji, count: ratingCounts.mustSee, label: "must-sees")
                }
                if ratingCounts.great > 0 {
                    closingRatingRow(emoji: Rating.great.emoji, count: ratingCounts.great, label: "great finds")
                }
                if ratingCounts.okay > 0 {
                    closingRatingRow(emoji: Rating.okay.emoji, count: ratingCounts.okay, label: "okay")
                }
                if ratingCounts.skip > 0 {
                    closingRatingRow(emoji: Rating.skip.emoji, count: ratingCounts.skip, label: ratingCounts.skip == 1 ? "skip" : "skips")
                }
            }

            // Closing text
            Text("Until next time.")
                .font(.system(size: 18, weight: .light, design: .serif))
                .italic()
                .foregroundStyle(SonderColors.inkMuted)
                .padding(.top, SonderSpacing.md)

            // Sonder wordmark
            Text("sonder")
                .font(.system(size: 13, weight: .light, design: .serif))
                .tracking(4.0)
                .foregroundStyle(SonderColors.inkLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, breathingRoom)
        .scrollTransition(.animated(.easeOut(duration: 0.6))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .offset(y: phase.isIdentity ? 0 : 30)
        }
        .onAppear {
            SonderHaptics.notification(.success)
        }
    }

    private func closingRatingRow(emoji: String, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            Text("\(count) \(label)")
                .font(.system(size: 15))
                .foregroundStyle(SonderColors.inkDark)
        }
    }

    // MARK: - Cover Photo Upload

    private func uploadCoverPhoto(_ image: UIImage) async {
        guard let userID = authService.currentUser?.id else { return }
        isUploadingCoverPhoto = true
        defer { isUploadingCoverPhoto = false }

        if let url = await photoService.uploadPhoto(image, for: userID) {
            trip.coverPhotoURL = url
            trip.updatedAt = Date()
            trip.syncStatus = .pending
            try? modelContext.save()
        }
    }

    private func removeLogFromTrip(_ log: Log) {
        withAnimation(.easeOut(duration: 0.25)) {
            log.tripID = nil
            log.updatedAt = Date()
            try? modelContext.save()
        }

        SonderHaptics.notification(.success)
    }

    // MARK: - Helpers

    private var dateRangeText: String? {
        ProfileShared.tripMediumDateRange(trip)
    }
}

// MARK: - Capsule Place Entry (Editorial Style)

// MARK: - Editorial Rail Entry

private struct EditorialRailEntry: View {
    let log: Log
    let place: Place
    var stopNumber: Int? = nil

    @State private var photoPageIndex = 0

    private let railColumnWidth: CGFloat = 48
    private let nodeSize: CGFloat = 12

    private var hasPhoto: Bool {
        !log.userPhotoURLs.isEmpty
    }

    private var shortAddress: String {
        let parts = place.address.components(separatedBy: ", ")
        if parts.count >= 2 {
            return parts.prefix(2).joined(separator: ", ")
        }
        return place.address
    }

    private var timeOfDayText: String {
        log.visitedAt.formatted(.dateTime.hour().minute())
    }

    /// Time-of-day atmosphere tint (from editorial style)
    private var atmosphereTint: (color: Color, opacity: Double) {
        let hour = Calendar.current.component(.hour, from: log.visitedAt)
        switch hour {
        case 5..<8:   return (Color(red: 1.0, green: 0.85, blue: 0.5), 0.12)
        case 8..<12:  return (Color(red: 1.0, green: 0.92, blue: 0.7), 0.08)
        case 12..<15: return (Color(red: 1.0, green: 0.95, blue: 0.85), 0.05)
        case 15..<18: return (Color(red: 1.0, green: 0.78, blue: 0.45), 0.10)
        case 18..<21: return (Color(red: 0.95, green: 0.6, blue: 0.3), 0.15)
        case 21..<24, 0..<5: return (Color(red: 0.2, green: 0.25, blue: 0.45), 0.18)
        default:      return (Color.clear, 0)
        }
    }

    private var nodeColor: Color {
        SonderColors.pinColor(for: log.rating)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left rail column
            ZStack(alignment: .top) {
                // Vertical line — full height
                Rectangle()
                    .fill(SonderColors.terracotta.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                // Node circle
                ZStack {
                    if log.rating == .mustSee {
                        Circle()
                            .fill(nodeColor)
                            .frame(width: nodeSize, height: nodeSize)
                    } else {
                        Circle()
                            .strokeBorder(nodeColor, lineWidth: 1.5)
                            .frame(width: nodeSize, height: nodeSize)
                            .background(Circle().fill(SonderColors.cream))
                    }

                    if let num = stopNumber {
                        Text("\(num)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(log.rating == .mustSee ? .white : nodeColor)
                    }
                }
                .padding(.top, SonderSpacing.md)
            }
            .frame(width: railColumnWidth)

            // Right content — editorial style
            VStack(alignment: .leading, spacing: 0) {
                // Photo with atmospheric tint
                if hasPhoto {
                    ZStack(alignment: .topLeading) {
                        // Photo content: carousel for multi-photo, single image otherwise
                        Group {
                            if log.userPhotoURLs.count > 1 {
                                FeedItemCardShared.photoCarousel(
                                    photoURLs: log.userPhotoURLs,
                                    pageIndex: $photoPageIndex,
                                    height: 200,
                                    targetImageWidth: 300
                                )
                            } else {
                                photoView
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        // Time-of-day atmospheric tint
                        LinearGradient(
                            colors: [
                                atmosphereTint.color.opacity(atmosphereTint.opacity),
                                atmosphereTint.color.opacity(atmosphereTint.opacity * 0.3),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)

                        // Frosted place name overlay — always visible
                        HStack(spacing: SonderSpacing.xxs) {
                            Text(place.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(log.rating.emoji)
                                .font(.system(size: 13))
                        }
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(SonderSpacing.xs)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }

                // Text content
                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    // Place name + rating (shown when no photo, since overlay handles the photo case)
                    if !hasPhoto {
                        HStack(alignment: .firstTextBaseline) {
                            Text(place.name)
                                .font(.system(.title3, design: .serif).weight(.semibold))
                                .foregroundStyle(SonderColors.inkDark)
                                .lineLimit(2)

                            Spacer()

                            Text(log.rating.emoji)
                                .font(.system(size: 16))
                        }
                    }

                    // Address + time
                    HStack(spacing: 6) {
                        Text(shortAddress)
                        Text("\u{00B7}")
                        Text(timeOfDayText)
                    }
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .padding(.top, hasPhoto ? SonderSpacing.xxs : 0)

                    // Note
                    if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        Text(note)
                            .font(.system(size: 14))
                            .foregroundStyle(SonderColors.inkDark)
                            .lineSpacing(4)
                    }

                    // Tags
                    if !log.tags.isEmpty {
                        HStack(spacing: SonderSpacing.xxs) {
                            ForEach(log.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11))
                                    .foregroundStyle(SonderColors.terracotta)
                                    .padding(.horizontal, SonderSpacing.xs)
                                    .padding(.vertical, 3)
                                    .background(SonderColors.terracotta.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(hasPhoto ? 0 : SonderSpacing.md)
                .padding(.top, hasPhoto ? SonderSpacing.xxs : 0)
                .background {
                    if !hasPhoto {
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                            .fill(SonderColors.warmGray)
                    }
                }
            }
            .padding(.trailing, SonderSpacing.md)
            .padding(.top, SonderSpacing.xxs)
            .padding(.bottom, SonderSpacing.xs)
        }
    }

    // MARK: - Photo Chain

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 200), contentMode: .fit) {
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
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 200), contentMode: .fit) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
            .fill(SonderColors.warmGray)
            .frame(height: 100)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                    Text(place.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(SonderColors.inkLight)
            }
    }
}

// MARK: - Filmstrip Frame

private struct FilmstripFrame: Identifiable {
    let id = UUID()
    let url: URL
    let timeLabel: String
}

// MARK: - Mood Arc Point

private struct MoodArcPoint: Identifiable {
    let id: String
    let point: CGPoint
    let color: Color
}

// MARK: - Reorder Trip Logs Sheet

private struct ReorderTripLogsSheet: View {
    let tripLogs: [Log]
    let placesByID: [String: Place]
    let modelContext: ModelContext
    let syncEngine: SyncEngine

    @Environment(\.dismiss) private var dismiss
    @State private var orderedLogs: [Log] = []
    @State private var pendingRemovals: [Log] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedLogs, id: \.id) { log in
                    HStack(spacing: SonderSpacing.sm) {
                        logThumbnail(log: log)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(placesByID[log.placeID]?.name ?? "Unknown Place")
                                .font(SonderTypography.headline)
                                .foregroundStyle(SonderColors.inkDark)
                                .lineLimit(1)

                            HStack(spacing: SonderSpacing.xs) {
                                Text(log.rating.emoji)
                                    .font(.system(size: 12))
                                Text(log.visitedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkMuted)
                            }
                        }

                        Spacer()
                    }
                }
                .onMove { source, destination in
                    orderedLogs.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    for index in offsets {
                        stageRemoval(of: orderedLogs[index])
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage Stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        withAnimation {
                            orderedLogs.sort { $0.visitedAt < $1.visitedAt }
                        }
                    } label: {
                        Label("Sort by Date", systemImage: "calendar")
                            .font(.system(size: 14))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNewOrder() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                orderedLogs = tripLogs
            }
        }
    }

    private func stageRemoval(of log: Log) {
        orderedLogs.removeAll { $0.id == log.id }
        pendingRemovals.append(log)
    }

    @ViewBuilder
    private func logThumbnail(log: Log) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 40, height: 40)) {
                thumbnailPlaceholder(log: log)
            }
        } else {
            thumbnailPlaceholder(log: log)
        }
    }

    @ViewBuilder
    private func thumbnailPlaceholder(log: Log) -> some View {
        if let place = placesByID[log.placeID],
           let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 100) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 40, height: 40)) {
                defaultPlaceholder
            }
        } else {
            defaultPlaceholder
        }
    }

    private var defaultPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
            .fill(SonderColors.terracotta.opacity(0.2))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.5))
            }
    }

    private func saveNewOrder() {
        let now = Date()
        for (i, log) in orderedLogs.enumerated() {
            log.tripSortOrder = i
            log.syncStatus = .pending
            log.updatedAt = now
        }
        for log in pendingRemovals {
            log.tripID = nil
            log.tripSortOrder = nil
            log.syncStatus = .pending
            log.updatedAt = now
        }
        try? modelContext.save()
        Task { await syncEngine.syncNow() }
        SonderHaptics.notification(.success)
        dismiss()
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
