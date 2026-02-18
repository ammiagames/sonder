//
//  ExploreMapView.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI
import MapKit
import SwiftData

// MARK: - Map Pin Tag (for Map's built-in selection)

/// Lightweight Hashable tag for Map's selection binding.
/// Each annotation is tagged with one of these; Map handles tap-to-select,
/// tap-to-deselect, and background-tap-to-dismiss natively.
enum MapPinTag: Hashable {
    case unified(String)   // UnifiedMapPin.id
    case wantToGo(String)  // WantToGoMapItem.id
}

/// Unified map on Tab 1 — shows personal pins, friends' pins, and want to go.
/// Three toggleable layers with smart overlap handling via UnifiedMapPin.
struct ExploreMapView: View {
    @Environment(ExploreMapService.self) private var exploreMapService
    @Environment(AuthenticationService.self) private var authService
    @Environment(LocationService.self) private var locationService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService

    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query private var places: [Place]

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 37.7749, longitude: -122.4194), distance: 50000)))
    @State private var mapSelection: MapPinTag?
    @State private var showDetail = false
    @State private var detailLogID: String?
    @State private var detailPlace: Place?
    @State private var mapStyle: MapStyleOption = .minimal
    @State private var filter = ExploreMapFilter()
    @State private var wantToGoMapItems: [WantToGoMapItem] = []
    @State private var showFilterSheet = false
    @State private var selectedFeedItem: FeedItem?
    @State private var selectedPlaceDetails: PlaceDetails?
    @State private var placeToLog: Place?
    @State private var placeIDToRemove: String?
    @State private var isLoadingDetails = false
    @State private var hasLoadedOnce = false
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var newPinPlaceID: String?
    @State private var pinDropSettled = true
    @State private var showPulseRings = false
    @State private var pinDropToast: PinDropToastInfo?
    @State private var cardIsExpanded = false
    @State private var sheetPin: UnifiedMapPin?

    // Memoized pin data — recomputed only when inputs change
    @State private var cachedUnifiedPins: [UnifiedMapPin] = []
    @State private var cachedFilteredPins: [UnifiedMapPin] = []
    @State private var cachedAnnotatedPins: [(pin: UnifiedMapPin, isWantToGo: Bool, identity: String)] = []
    @State private var cachedStandaloneWTG: [WantToGoMapItem] = []

    // Debounce & throttle state
    @State private var recomputeTask: Task<Void, Never>?
    @State private var prefetchTask: Task<Void, Never>?
    @State private var lastFullLoadAt: Date?
    @State private var wtgGeneration: UInt64 = 0
    @State private var previousWTGPlaceIDs: Set<String> = []

    /// When set to true (by ProfileView), focuses the map on personal places only
    var focusMyPlaces: Binding<Bool>?
    /// Reports whether a pin is currently selected (used by MainTabView to hide FAB)
    var hasSelection: Binding<Bool>?
    /// Coordinate of a newly-created log pin to animate on screen
    var pendingPinDrop: Binding<CLLocationCoordinate2D?>?

    var body: some View {
        NavigationStack {
            coreMapView
                .navigationDestination(isPresented: $showDetail) {
                    if let logID = detailLogID,
                       let log = allLogs.first(where: { $0.id == logID }),
                       let place = detailPlace {
                        LogDetailView(log: log, place: place, onDelete: {
                            showDetail = false
                            detailLogID = nil
                            detailPlace = nil
                        })
                    }
                }
                .navigationDestination(item: $selectedFeedItem) { feedItem in
                    FeedLogDetailView(feedItem: feedItem)
                }
                .navigationDestination(item: $selectedPlaceDetails) { details in
                    PlacePreviewView(details: details) {
                        let place = cacheService.cachePlace(from: details)
                        placeIDToRemove = place.id
                        placeToLog = place
                    }
                }
                .fullScreenCover(item: $placeToLog) { place in
                    NavigationStack {
                        RatePlaceView(place: place) { _ in
                            let placeID = placeIDToRemove
                            selectedPlaceDetails = nil
                            placeIDToRemove = nil
                            mapSelection = nil
                            DispatchQueue.main.async {
                                placeToLog = nil
                                if let placeID {
                                    removeFromWantToGo(placeID: placeID)
                                }
                            }
                        }
                    }
                }
                .overlay {
                    if isLoadingDetails {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .overlay {
                                ProgressView("Loading place...")
                                    .tint(SonderColors.terracotta)
                                    .padding(SonderSpacing.lg)
                                    .background(SonderColors.warmGray)
                                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                            }
                    }
                }
        }
        .overlay(alignment: .bottom) {
            wantToGoBottomContent
                .animation(.easeOut(duration: 0.2), value: mapSelection != nil)
        }
        .overlay(alignment: .bottom) {
            if let pin = sheetPin {
                UnifiedBottomCard(
                    pin: pin,
                    onDismiss: {
                        UISelectionFeedbackGenerator().selectionChanged()
                        clearSelection()
                    },
                    onNavigateToLog: { logID, place in
                        detailLogID = logID
                        detailPlace = place
                        withAnimation(.smooth(duration: 0.2)) { sheetPin = nil }
                        mapSelection = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showDetail = true
                        }
                    },
                    onNavigateToFeedItem: { feedItem in
                        withAnimation(.smooth(duration: 0.2)) { sheetPin = nil }
                        mapSelection = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            selectedFeedItem = feedItem
                        }
                    },
                    onFocusFriend: { friendID, _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter.selectedFriendIDs = [friendID]
                            filter.showFriendsPlaces = true
                            sheetPin = nil
                            clearSelection()
                        }
                    },
                    onExpandedChanged: { expanded in
                        cardIsExpanded = expanded
                        recenterForCardState(coordinate: pin.coordinate, expanded: expanded)
                    }
                )
                .id(pin.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: sheetPin?.id)
    }

    // MARK: - Core Map View (split to help type-checker)

    private var coreMapView: some View {
        coreMapWithDataHandlers
            .onChange(of: wantToGoMapItems.count) { _, _ in
                scheduleRecomputePins()
                if !selectionIsValid { clearSelection() }
            }
            .onChange(of: focusMyPlaces?.wrappedValue) { _, newValue in
                if newValue == true { handleFocusMyPlaces() }
            }
            .onChange(of: pendingPinDrop?.wrappedValue?.latitude) { _, newValue in
                guard newValue != nil, let coord = pendingPinDrop?.wrappedValue else { return }
                pendingPinDrop?.wrappedValue = nil
                handlePinDrop(at: coord)
            }
    }

    private var coreMapWithDataHandlers: some View {
        mapWithOverlays
            .task {
                await loadData()
                recomputePins()
            }
            .onChange(of: wantToGoService.items.count) { oldCount, newCount in
                guard oldCount != 0 || newCount != 0 else { return }
                // Initial load uses full fetch in loadData(); incremental for subsequent changes
                if hasLoadedOnce {
                    incrementalWTGUpdate()
                }
            }
            .onChange(of: mapSelection) { _, newTag in
                hasSelection?.wrappedValue = newTag != nil
                // Manage unified card presentation
                if case .unified(let id) = newTag,
                   let pin = filteredPins.first(where: { $0.id == id }) {
                    withAnimation(.smooth(duration: 0.25)) { sheetPin = pin }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } else {
                    // Not a unified pin — dismiss if showing
                    withAnimation(.smooth(duration: 0.25)) { sheetPin = nil }
                }
                // Zoom to selected pin
                guard let newTag else { return }
                let coordinate: CLLocationCoordinate2D?
                switch newTag {
                case .unified(let id):
                    coordinate = filteredPins.first(where: { $0.id == id })?.coordinate
                case .wantToGo(let id):
                    coordinate = standaloneWantToGoItems.first(where: { $0.id == id })?.coordinate
                }
                if let coordinate {
                    zoomToSelected(coordinate: coordinate)
                }
            }
            .onChange(of: allLogs.count) { _, _ in
                scheduleRecomputePins()
                if !selectionIsValid { clearSelection() }
            }
            .onChange(of: personalLogPhotoFingerprint) { _, _ in
                scheduleRecomputePins()
            }
            .onChange(of: places.count) { _, _ in scheduleRecomputePins() }
            .onChange(of: exploreMapService.hasLoaded) { _, _ in scheduleRecomputePins() }
            .onChange(of: filter) { _, _ in
                scheduleRecomputePins()
                if !selectionIsValid { clearSelection() }
            }
    }

    private var mapWithOverlays: some View {
        mapContent
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterButton }
                ToolbarItem(placement: .topBarTrailing) { mapStyleMenu }
            }
            .overlay(alignment: .top) { topOverlay }
            .overlay(alignment: .top) {
                if let toast = pinDropToast {
                    PinDropToastView(info: toast)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(.top, 60)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: pinDropToast != nil)
            .sheet(isPresented: $showFilterSheet) {
                ExploreFilterSheet(filter: $filter)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    // MARK: - Filter Button (toolbar)

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18))
                    .foregroundColor(filter.isActive ? SonderColors.terracotta : SonderColors.inkDark)

                if filter.isActive {
                    Text("\(filter.activeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(SonderColors.terracotta)
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
            .toolbarIcon()
        }
    }

    // MARK: - Top Overlay (chips + loading)

    private var topOverlay: some View {
        VStack(spacing: SonderSpacing.xs) {
            layerChips

            if exploreMapService.isLoading && !hasLoadedOnce {
                friendsLoadingPill
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, SonderSpacing.xs)
        .animation(.easeInOut(duration: 0.3), value: exploreMapService.isLoading)
    }

    private var friendsLoadingPill: some View {
        HStack(spacing: SonderSpacing.xs) {
            ProgressView()
                .tint(SonderColors.terracotta)
                .scaleEffect(0.8)
            Text("Loading friends' places…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(SonderColors.inkMuted)
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xxs + 2)
        .background(SonderColors.warmGray.opacity(0.95))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: - Layer Chips

    private var layerChips: some View {
        HStack(spacing: SonderSpacing.xs) {
            layerChip(
                label: "Mine",
                icon: "mappin.circle.fill",
                isOn: filter.showMyPlaces
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    filter.showMyPlaces.toggle()
                }
            }

            layerChip(
                label: friendsChipLabel,
                icon: "person.2.fill",
                isOn: filter.showFriendsPlaces
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if !filter.selectedFriendIDs.isEmpty {
                        // Clear friend filter first, restore to all friends
                        filter.selectedFriendIDs = []
                    } else {
                        filter.showFriendsPlaces.toggle()
                    }
                }
            }

            layerChip(
                label: "Saved",
                icon: "bookmark.fill",
                isOn: filter.showWantToGo
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    filter.showWantToGo.toggle()
                }
            }
        }
        .padding(.horizontal, SonderSpacing.md)
    }

    private func layerChip(label: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xxs + 2)
            .background(isOn ? SonderColors.terracotta : SonderColors.warmGray.opacity(0.9))
            .foregroundColor(isOn ? .white : SonderColors.inkMuted)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Map

    private var mapContent: some View {
        Map(position: $cameraPosition, selection: $mapSelection) {
            UserAnnotation()

            // Unified pins — stable identity per pin; .id() on the content view
            // prevents annotation recycling from mixing up async-loaded photos.
            ForEach(annotatedPins, id: \.identity) { item in
                unifiedPinAnnotation(item: item)
            }

            // Standalone Want to Go pins (places not in any unified pin)
            if filter.showWantToGo {
                ForEach(standaloneWantToGoItems, id: \.id) { item in
                    let isSelected = mapSelection == .wantToGo(item.id)
                    let tag = MapPinTag.wantToGo(item.id)
                    Annotation(item.placeName, coordinate: item.coordinate, anchor: .bottom) {
                        WantToGoMapPin()
                            .scaleEffect(isSelected ? 1.25 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: isSelected)
                            .simultaneousGesture(TapGesture().onEnded {
                                if isSelected {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        mapSelection = nil
                                    }
                                }
                            })
                    }
                    .tag(tag)
                }
            }
        }
        .mapStyle(mapStyle.style)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            schedulePrefetch()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Pin Annotation Helpers

    private func unifiedPinAnnotation(item: (pin: UnifiedMapPin, isWantToGo: Bool, identity: String)) -> some MapContent {
        let isSelected = mapSelection == .unified(item.pin.id)
        let isNewPin = newPinPlaceID == item.pin.placeID
        let isDropping = isNewPin && !pinDropSettled
        let tag = MapPinTag.unified(item.pin.id)
        let scale: CGFloat = isDropping ? 1.3 : (isSelected ? 1.25 : 1.0)
        let yOffset: CGFloat = isDropping ? -50 : 0
        return Annotation(item.pin.placeName, coordinate: item.pin.coordinate, anchor: .bottom) {
            ZStack {
                // Pulse rings behind the pin — only for newly dropped pins
                if isNewPin && showPulseRings {
                    PinDropPulseRings()
                        .offset(y: 20) // Center rings on the pin's base, not its center
                }

                UnifiedMapPinView(
                    pin: item.pin,
                    isWantToGo: item.isWantToGo
                )
                .id(item.identity)
                .offset(y: yOffset)
                .scaleEffect(scale)
                .animation(.easeOut(duration: 0.15), value: isSelected)
                .simultaneousGesture(TapGesture().onEnded {
                    if isSelected {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mapSelection = nil
                        }
                    }
                })
            }
        }
        .tag(tag)
    }

    // MARK: - Bottom Content

    @ViewBuilder
    private var wantToGoBottomContent: some View {
        if case .wantToGo(let id) = mapSelection,
           let item = standaloneWantToGoItems.first(where: { $0.id == id }) {
            WantToGoSheetContent(item: item) {
                fetchPlaceDetails(placeID: item.placeID)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func clearSelection() {
        // Recenter camera on the pin before dismissing
        if let tag = mapSelection {
            let coordinate: CLLocationCoordinate2D?
            switch tag {
            case .unified(let id):
                coordinate = filteredPins.first(where: { $0.id == id })?.coordinate
            case .wantToGo(let id):
                coordinate = standaloneWantToGoItems.first(where: { $0.id == id })?.coordinate
            }
            if let coordinate {
                let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span
                    ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                withAnimation(.smooth(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentSpan))
                }
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) { mapSelection = nil }
        cardIsExpanded = false
    }

    /// Returns true when the currently-selected pin still exists in the data.
    private var selectionIsValid: Bool {
        guard let tag = mapSelection else { return true }
        switch tag {
        case .unified(let id):
            return filteredPins.contains { $0.id == id }
        case .wantToGo(let id):
            return standaloneWantToGoItems.contains { $0.id == id }
        }
    }

    // MARK: - Map Style Menu

    private var mapStyleMenu: some View {
        Menu {
            Section("Map Style") {
                ForEach(MapStyleOption.allCases, id: \.self) { style in
                    Button {
                        withAnimation { mapStyle = style }
                    } label: {
                        HStack {
                            Label(style.name, systemImage: style.icon)
                            if mapStyle == style { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .toolbarIcon()
        }
    }

    // MARK: - Computed

    private var friendsChipLabel: String {
        if filter.selectedFriendIDs.count == 1,
           let friend = exploreMapService.allFriends.first(where: { filter.selectedFriendIDs.contains($0.id) }) {
            return friend.username
        }
        if filter.selectedFriendIDs.count > 1 {
            return "\(filter.selectedFriendIDs.count) Friends"
        }
        return "Friends"
    }

    /// Logs filtered to current user only
    private var personalLogs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    /// Changes when a personal log's photo becomes available (e.g. background upload completes).
    /// Triggers pin recomputation so the map icon updates from emoji to photo.
    private var personalLogPhotoFingerprint: Int {
        personalLogs.reduce(0) { $0 + ($1.photoURL != nil ? 1 : 0) }
    }

    /// Place IDs in the user's Want to Go list.
    private var wantToGoPlaceIDs: Set<String> {
        Set(wantToGoService.items.map(\.placeID))
    }

    /// Accessors for memoized pin data
    private var unifiedPins: [UnifiedMapPin] { cachedUnifiedPins }
    private var filteredPins: [UnifiedMapPin] { cachedFilteredPins }
    private var annotatedPins: [(pin: UnifiedMapPin, isWantToGo: Bool, identity: String)] { cachedAnnotatedPins }
    private var standaloneWantToGoItems: [WantToGoMapItem] { cachedStandaloneWTG }

    /// Schedules a debounced pin recomputation (batches multiple calls within one frame).
    private func scheduleRecomputePins() {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            recomputePins()
        }
    }

    /// Recomputes all pin data from current inputs.
    private func recomputePins() {
        let unified = exploreMapService.computeUnifiedPins(personalLogs: personalLogs, places: Array(places))
        cachedUnifiedPins = unified

        let bookmarked = filter.showWantToGo ? wantToGoPlaceIDs : Set<String>()
        let filtered = exploreMapService.filteredUnifiedPins(pins: unified, filter: filter, bookmarkedPlaceIDs: bookmarked)
        cachedFilteredPins = filtered

        cachedAnnotatedPins = filtered.map { pin in
            let isWtg = filter.showWantToGo && wantToGoPlaceIDs.contains(pin.placeID)
            return (pin: pin, isWantToGo: isWtg, identity: pin.id)
        }

        let unifiedPlaceIDs = Set(unified.map(\.placeID))
        cachedStandaloneWTG = wantToGoMapItems.filter { item in
            !unifiedPlaceIDs.contains(item.placeID) && filter.matchesCategories(placeName: item.placeName)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let userID = authService.currentUser?.id else { return }

        // Skip full reload if we loaded recently (< 30s) — WTG changes
        // are handled incrementally via onChange/task(id:)
        if let lastLoad = lastFullLoadAt, Date().timeIntervalSince(lastLoad) < 30 {
            return
        }

        await wantToGoService.syncWantToGo(for: userID)
        await exploreMapService.loadFriendsPlaces(for: userID)
        await loadWantToGoItems()
        lastFullLoadAt = Date()

        if !hasLoadedOnce {
            fitAllPins()
            hasLoadedOnce = true
            await cacheService.backfillMissingPhotoReferences(using: placesService)
        }

        prefetchPinPhotos()
    }

    private func loadWantToGoItems() async {
        guard let userID = authService.currentUser?.id else { return }
        do {
            wantToGoMapItems = try await wantToGoService.fetchWantToGoForMap(for: userID)
            previousWTGPlaceIDs = Set(wantToGoMapItems.map(\.placeID))
        }
        catch { print("Error loading want to go for map: \(error)") }
    }

    /// Incrementally add/remove WTG map items based on what changed in the service.
    /// Uses a generation counter to safely handle rapid add→remove sequences.
    private func incrementalWTGUpdate() {
        let currentPlaceIDs = Set(wantToGoService.items.map(\.placeID))
        let added = currentPlaceIDs.subtracting(previousWTGPlaceIDs)
        let removed = previousWTGPlaceIDs.subtracting(currentPlaceIDs)

        // Immediately remove items (always safe, no async needed)
        if !removed.isEmpty {
            wantToGoMapItems.removeAll { removed.contains($0.placeID) }
        }

        // For added items, try to construct from local cache first
        if !added.isEmpty {
            wtgGeneration &+= 1
            let capturedGeneration = wtgGeneration

            for placeID in added {
                // Try local cache for instant pin placement
                if let cachedPlace = cacheService.getPlace(by: placeID) {
                    let item = wantToGoService.items.first { $0.placeID == placeID }
                    wantToGoMapItems.append(WantToGoMapItem(
                        id: item?.id ?? UUID().uuidString,
                        placeID: placeID,
                        placeName: item?.placeName ?? cachedPlace.name,
                        placeAddress: item?.placeAddress ?? cachedPlace.address,
                        photoReference: item?.photoReference ?? cachedPlace.photoReference,
                        coordinate: cachedPlace.coordinate
                    ))
                } else {
                    // Need to fetch coordinates — do it async with generation check
                    Task {
                        guard let userID = authService.currentUser?.id else { return }
                        do {
                            let freshItems = try await wantToGoService.fetchWantToGoForMap(for: userID)
                            // Only apply if no newer update has superseded this one
                            guard wtgGeneration == capturedGeneration else { return }
                            // Only apply if the place is still in the WTG list (wasn't removed while we fetched)
                            let stillWanted = Set(wantToGoService.items.map(\.placeID))
                            wantToGoMapItems = freshItems.filter { stillWanted.contains($0.placeID) }
                        } catch {
                            print("Error fetching WTG map items: \(error)")
                        }
                    }
                }
            }
        }

        previousWTGPlaceIDs = currentPlaceIDs
        scheduleRecomputePins()
    }

    /// Schedules a debounced photo prefetch (500ms after last camera move).
    private func schedulePrefetch() {
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            prefetchPinPhotos()
        }
    }

    /// Pre-fetch place photos for visible pins into the image cache.
    /// Only fetches up to 20 at a time to stay lightweight at scale.
    private func prefetchPinPhotos() {
        // Only prefetch pins in (or near) the current viewport
        let visiblePins: [UnifiedMapPin]
        if let region = visibleRegion ?? cameraPosition.region {
            let latBuffer = region.span.latitudeDelta * 0.5
            let lonBuffer = region.span.longitudeDelta * 0.5
            visiblePins = filteredPins.filter { pin in
                abs(pin.coordinate.latitude - region.center.latitude) < (region.span.latitudeDelta / 2 + latBuffer) &&
                abs(pin.coordinate.longitude - region.center.longitude) < (region.span.longitudeDelta / 2 + lonBuffer)
            }
        } else {
            visiblePins = filteredPins
        }

        let photoRefs = Array(Set(visiblePins.compactMap(\.photoReference)).prefix(20))
        let pinPointSize = CGSize(width: 56, height: 56)
        let scale = UIScreen.main.scale
        let targetPixelSize = CGSize(width: 56 * scale, height: 56 * scale)

        for ref in photoRefs {
            guard let url = GooglePlacesService.photoURL(for: ref, maxWidth: 112) else { continue }
            let cacheKey = ImageDownsampler.cacheKey(for: url, pointSize: pinPointSize)
            guard ImageDownsampler.cache.object(forKey: cacheKey) == nil else { continue }

            Task.detached(priority: .utility) {
                do {
                    let (data, _) = try await ImageDownsampler.session.data(from: url)
                    if let downsampled = ImageDownsampler.downsample(data: data, to: targetPixelSize) {
                        ImageDownsampler.cache.setObject(downsampled, forKey: cacheKey)
                    }
                } catch { }
            }
        }
    }

    // MARK: - Focus Mode

    private func handleFocusMyPlaces() {
        filter.showMyPlaces = true
        filter.showFriendsPlaces = false

        // Keep the map where the user last left it — don't reposition the camera.
        focusMyPlaces?.wrappedValue = false
    }

    // MARK: - Pin Drop Animation

    private func handlePinDrop(at coord: CLLocationCoordinate2D) {
        // Ensure "My Places" layer is visible so the new pin shows
        filter.showMyPlaces = true

        // Find the matching pin by coordinate proximity
        let match = ExploreMapService.findPinByProximity(
            coordinate: coord,
            in: filteredPins
        )

        // Set up the two-phase drop animation
        pinDropSettled = false
        showPulseRings = false
        newPinPlaceID = match?.placeID

        // Zoom camera to the new pin location
        zoomToSelected(coordinate: coord)

        // Animate to settled on next frame (spring drop effect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                pinDropSettled = true
            }
        }

        // Trigger pulse rings right after pin lands
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showPulseRings = true
        }

        // Show context toast with place name + rating
        if let match {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pinDropToast = PinDropToastInfo(
                    placeName: match.placeName,
                    ratingEmoji: match.userRating?.emoji ?? "📍"
                )
            }
            // Dismiss toast
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                pinDropToast = nil
            }
        }

        // Clear the drop animation state after it completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            newPinPlaceID = nil
            showPulseRings = false
        }
    }

    private func fitAllPins() {
        let coordinates = filteredPins.map(\.coordinate)
        if !coordinates.isEmpty {
            let region = MKCoordinateRegion(coordinates: coordinates)
            // Cap zoom-out: if pins are spread across > ~10 degrees (continent-scale),
            // just center on user instead of showing the whole globe
            if region.span.latitudeDelta > 10 || region.span.longitudeDelta > 10 {
                centerOnUser()
            } else {
                withAnimation(.smooth(duration: 1.2)) { cameraPosition = .region(region) }
            }
        } else {
            centerOnUser()
        }
    }

    /// Pans/zooms the camera so a selected pin is centered on screen.
    /// The compact sheet (90pt) is small enough that no offset is needed.
    private func zoomToSelected(coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span

        let targetSpan: MKCoordinateSpan

        if let span = currentSpan, span.latitudeDelta > 0.15 {
            let meters = 3000.0 / 111_000.0
            targetSpan = MKCoordinateSpan(latitudeDelta: meters, longitudeDelta: meters)
        } else {
            targetSpan = currentSpan ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        }

        withAnimation(.smooth(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: targetSpan
            ))
        }
    }

    /// Recenter pin when the sheet detent changes.
    /// Expanded sheet covers ~half the screen — offset pin upward so it stays visible.
    /// Compact sheet — center pin on screen, no offset needed.
    private func recenterForCardState(coordinate: CLLocationCoordinate2D, expanded: Bool) {
        let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span
            ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

        if expanded {
            let latOffset = currentSpan.latitudeDelta * 0.25
            let offsetCenter = CLLocationCoordinate2D(
                latitude: coordinate.latitude - latOffset,
                longitude: coordinate.longitude
            )
            withAnimation(.smooth(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: offsetCenter, span: currentSpan))
            }
        } else {
            withAnimation(.smooth(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentSpan))
            }
        }
    }

    private func fetchPlaceDetails(placeID: String) {
        Task {
            isLoadingDetails = true
            if let details = await placesService.getPlaceDetails(placeId: placeID) {
                selectedPlaceDetails = details
            }
            isLoadingDetails = false
        }
    }

    private func removeFromWantToGo(placeID: String) {
        guard let userID = authService.currentUser?.id else { return }
        Task {
            do {
                try await wantToGoService.removeFromWantToGo(placeID: placeID, userID: userID)
            } catch {
                print("Error removing from want to go: \(error)")
            }
        }
    }

    private func centerOnUser() {
        if let location = locationService.currentLocation {
            withAnimation(.smooth(duration: 1.0)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location, latitudinalMeters: 5000, longitudinalMeters: 5000
                ))
            }
        } else {
            withAnimation(.smooth(duration: 1.0)) {
                cameraPosition = .userLocation(fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 37.7749, longitude: -122.4194), distance: 50000)))
            }
        }
    }
}

// MARK: - Pin Drop Toast Info

struct PinDropToastInfo: Equatable {
    let placeName: String
    let ratingEmoji: String
}

// MARK: - Pin Drop Toast View

/// Floating pill that shows the place name + rating emoji after a pin drop.
struct PinDropToastView: View {
    let info: PinDropToastInfo

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            Text(info.ratingEmoji)
                .font(.system(size: 20))

            Text(info.placeName)
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
                .lineLimit(1)

            Text("logged")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.sm)
        .background(.ultraThinMaterial)
        .background(SonderColors.cream.opacity(0.7))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Pin Drop Pulse Rings

/// Concentric rings that expand and fade from the pin drop point.
struct PinDropPulseRings: View {
    @State private var ring1Scale: CGFloat = 0.3
    @State private var ring2Scale: CGFloat = 0.3
    @State private var ring3Scale: CGFloat = 0.3
    @State private var ring1Opacity: Double = 0.6
    @State private var ring2Opacity: Double = 0.5
    @State private var ring3Opacity: Double = 0.4

    var body: some View {
        ZStack {
            Circle()
                .stroke(SonderColors.terracotta, lineWidth: 2)
                .frame(width: 80, height: 80)
                .scaleEffect(ring1Scale)
                .opacity(ring1Opacity)

            Circle()
                .stroke(SonderColors.terracotta.opacity(0.7), lineWidth: 1.5)
                .frame(width: 80, height: 80)
                .scaleEffect(ring2Scale)
                .opacity(ring2Opacity)

            Circle()
                .stroke(SonderColors.ochre.opacity(0.5), lineWidth: 1)
                .frame(width: 80, height: 80)
                .scaleEffect(ring3Scale)
                .opacity(ring3Opacity)
        }
        .allowsHitTesting(false)
        .onAppear {
            // Ring 1: fast
            withAnimation(.easeOut(duration: 0.8)) {
                ring1Scale = 1.8
                ring1Opacity = 0
            }
            // Ring 2: medium, slightly delayed
            withAnimation(.easeOut(duration: 1.0).delay(0.15)) {
                ring2Scale = 2.2
                ring2Opacity = 0
            }
            // Ring 3: slow, more delayed
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                ring3Scale = 2.6
                ring3Opacity = 0
            }
        }
    }
}

// MARK: - Want to Go Map Item

struct WantToGoMapItem: Identifiable {
    let id: String
    let placeID: String
    let placeName: String
    let placeAddress: String?
    let photoReference: String?
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Want to Go Sheet Content

/// Bottom card for a tapped Want to Go pin.
struct WantToGoSheetContent: View {
    let item: WantToGoMapItem
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(SonderColors.inkLight.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.vertical, 6)

            HStack(spacing: SonderSpacing.sm) {
                PlacePhotoView(photoReference: item.photoReference, size: 56, cornerRadius: SonderSpacing.radiusSm)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.placeName)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    if let address = item.placeAddress, !address.isEmpty {
                        Text(address)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.wantToGoPin)
                        Text("On your Want to Go list")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }

                Spacer()

                WantToGoButton(placeID: item.placeID, placeName: item.placeName, placeAddress: item.placeAddress, photoReference: item.photoReference)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SonderColors.inkLight)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.sm)
    }
}
