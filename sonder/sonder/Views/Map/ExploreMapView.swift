//
//  ExploreMapView.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI
import MapKit
import SwiftData
import os

// MARK: - Map Pin Tag (for Map's built-in selection)

/// Lightweight Hashable tag for Map's selection binding.
/// Each annotation is tagged with one of these; Map handles tap-to-select,
/// tap-to-deselect, and background-tap-to-dismiss natively.
enum MapPinTag: Hashable {
    case unified(String)   // UnifiedMapPin.id
    case wantToGo(String)  // WantToGoMapItem.id
}

private let logger = Logger(subsystem: "com.sonder.app", category: "ExploreMapView")

/// Unified map on Tab 1 — shows personal pins, friends' pins, and want to go.
/// Three toggleable layers with smart overlap handling via UnifiedMapPin.
struct ExploreMapView: View {
    @Environment(ExploreMapService.self) private var exploreMapService
    @Environment(AuthenticationService.self) private var authService
    @Environment(LocationService.self) private var locationService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext

    @Environment(\.isTabVisible) private var isTabVisible

    @State private var userLogs: [Log] = []
    @Query private var places: [Place]

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 37.7749, longitude: -122.4194), distance: 50000)))
    @State private var mapSelection: MapPinTag?
    @State private var showDetail = false
    @State private var detailLogID: String?
    @State private var detailPlace: Place?
    @State private var mapStyle: MapStyleOption = .minimal
    @AppStorage("exploreTileStyle") private var tileStyleRaw: String = TileStyleOption.standard.rawValue
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
    @State private var currentCameraDistance: CLLocationDistance = 50000
    @State private var currentCameraHeading: CLLocationDirection = 0
    @State private var currentCameraPitch: Double = 0
    @State private var kenBurnsTask: Task<Void, Never>?
    @State private var newPinPlaceID: String?
    @State private var pinDropSettled = true
    @State private var pinDropLanded = true
    @State private var showPulseRings = false
    @State private var pinDropToast: PinDropToastInfo?
    @State private var cardIsExpanded = false
    @State private var sheetPin: UnifiedMapPin?
    @State private var removingPinIDs: Set<String> = []
    @State private var removingWTGIDs: Set<String> = []
    @State private var isDetailEditing = false

    // Memoized pin data — recomputed only when inputs change
    @State private var cachedUnifiedPins: [UnifiedMapPin] = []
    @State private var cachedFilteredPins: [UnifiedMapPin] = []
    @State private var cachedAnnotatedPins: [(pin: UnifiedMapPin, isWantToGo: Bool, identity: String)] = []
    @State private var cachedStandaloneWTG: [WantToGoMapItem] = []
    @State private var cachedAvailableTags: [String] = []
    @State private var cachedWantToGoPlaceIDs: Set<String> = []

    private let loadingStyle: Int = 2

    @State private var shimmerPhase: CGFloat = -1
    @State private var breatheScale: CGFloat = 1.0

    // Map snapshot — shown as placeholder while live Map reloads tiles
    @State private var mapSnapshot: UIImage?
    @State private var snapshotProgress: CGFloat = 0
    // Dissolve animation handle — stored to cancel on rapid tab switching
    @State private var dissolveTask: Task<Void, Never>?
    @State private var snapshotGeneration: UInt64 = 0

    // Debounce & throttle state
    @State private var recomputeTask: Task<Void, Never>?
    @State private var prefetchTask: Task<Void, Never>?
    @State private var activePrefetchDownloads: [Task<Void, Never>] = []
    @State private var lastFullLoadAt: Date?
    @State private var wtgGeneration: UInt64 = 0
    @State private var pinDropCleanupTask: Task<Void, Never>?
    @State private var removalCleanupTasks: [Task<Void, Never>] = []
    @State private var previousWTGPlaceIDs: Set<String> = []

    /// When set to true (by ProfileView), focuses the map on personal places only
    var focusMyPlaces: Binding<Bool>?
    /// Reports whether a pin is currently selected (used by MainTabView to hide FAB)
    var hasSelection: Binding<Bool>?
    /// Coordinate of a newly-created log pin to animate on screen
    var pendingPinDrop: Binding<CLLocationCoordinate2D?>?
    /// Pop-to-root trigger — when this UUID changes, dismiss all pushed views
    var popToRoot: UUID = UUID()

    var body: some View {
        NavigationStack {
            coreMapView
                .navigationDestination(isPresented: $showDetail) {
                    if let logID = detailLogID,
                       let log = userLogs.first(where: { $0.id == logID }),
                       let place = detailPlace {
                        LogViewScreen(log: log, place: place, onDelete: {
                            showDetail = false
                            detailLogID = nil
                            detailPlace = nil
                            mapSelection = nil
                        }, externalIsEditing: $isDetailEditing)
                    } else {
                        // Data became stale (deleted/synced) — dismiss gracefully
                        Color.clear.onAppear { showDetail = false }
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
                            Task { @MainActor in
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
        .overlay(alignment: .top) { topOverlay }
        .overlay(alignment: .bottom) {
            wantToGoBottomContent
                .animation(.easeOut(duration: 0.2), value: mapSelection != nil)
        }
        .overlay(alignment: .bottom) {
            Group {
                if let pin = sheetPin, !isShowingDetail {
                    UnifiedBottomCard(
                        pin: pin,
                        onDismiss: {
                            SonderHaptics.selectionChanged()
                            clearSelection()
                        },
                        onNavigateToLog: { logID, place in
                            detailLogID = logID
                            detailPlace = place
                            cardIsExpanded = false
                            showDetail = true
                        },
                        onNavigateToFeedItem: { feedItem in
                            cardIsExpanded = false
                            selectedFeedItem = feedItem
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
            .animation(.smooth(duration: 0.18), value: sheetPin?.id)
            .animation(.smooth(duration: 0.18), value: isShowingDetail)
        }
        // Snapshot overlay — placed at the outermost level so the Map's
        // internal layout settling cannot shift it. Fully covers the screen
        // while the live Map reloads tiles after a tab switch.
        .overlay {
            if let snapshot = mapSnapshot, snapshotProgress < 1 {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .opacity(1 - Double(snapshotProgress))
                    .allowsHitTesting(false)
            }
        }
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
            .onChange(of: isTabVisible) { _, visible in
                if !visible {
                    // Cancel in-flight prefetch downloads to free networking resources
                    for task in activePrefetchDownloads { task.cancel() }
                    activePrefetchDownloads.removeAll()
                    prefetchTask?.cancel()
                    kenBurnsTask?.cancel()
                    recomputeTask?.cancel()
                    pinDropCleanupTask?.cancel()
                    for task in removalCleanupTasks { task.cancel() }
                    removalCleanupTasks.removeAll()

                    // Snapshot camera region so the Map restores to the same spot
                    if let region = visibleRegion {
                        cameraPosition = .region(region)
                    }

                    // Capture a static snapshot before the Map is destroyed
                    snapshotProgress = 0
                    captureMapSnapshot()
                } else if mapSnapshot != nil {
                    // Tab visible again — dissolve snapshot after map has had time to load
                    dissolveTask?.cancel()
                    dissolveTask = Task { @MainActor in
                        snapshotProgress = 0
                        try? await Task.sleep(for: .milliseconds(800))
                        guard !Task.isCancelled else { return }
                        guard snapshotProgress < 1 else { return }
                        withAnimation(.easeInOut(duration: 0.6)) {
                            snapshotProgress = 1
                        }
                        try? await Task.sleep(for: .milliseconds(700))
                        guard !Task.isCancelled else { return }
                        mapSnapshot = nil
                    }
                }
            }
            .onChange(of: pendingPinDrop?.wrappedValue?.latitude) { _, newValue in
                guard newValue != nil, let coord = pendingPinDrop?.wrappedValue else { return }
                pendingPinDrop?.wrappedValue = nil
                handlePinDrop(at: coord)
            }
            .onDisappear {
                // Clean up in-flight tasks when the view is removed entirely
                for task in activePrefetchDownloads { task.cancel() }
                activePrefetchDownloads.removeAll()
                prefetchTask?.cancel()
                kenBurnsTask?.cancel()
                recomputeTask?.cancel()
                pinDropCleanupTask?.cancel()
                dissolveTask?.cancel()
                for task in removalCleanupTasks { task.cancel() }
                removalCleanupTasks.removeAll()
            }
    }

    private var coreMapWithDataHandlers: some View {
        mapWithOverlays
            .task {
                refreshUserLogs()
                requestLocationPermissionIfNeeded()
                await loadData()
                recomputePins()
            }
            .onChange(of: syncEngine.lastSyncDate) { _, _ in
                refreshUserLogs()
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
                    withAnimation(.smooth(duration: 0.18)) { sheetPin = pin }
                    SonderHaptics.impact(.soft)
                } else {
                    // Not a unified pin — dismiss if showing
                    withAnimation(.smooth(duration: 0.18)) { sheetPin = nil }
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
            .onChange(of: userLogs.count) { _, _ in
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
            .onChange(of: popToRoot) {
                // Don't pop while the user is editing a log
                guard !isDetailEditing else { return }
                showDetail = false
                detailLogID = nil
                detailPlace = nil
                selectedFeedItem = nil
                selectedPlaceDetails = nil
                placeToLog = nil
                // Keep mapSelection and sheetPin so the bottom card stays visible
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
            .overlay(alignment: .top) {
                Group {
                    if let toast = pinDropToast {
                        PinDropToastView(info: toast)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .padding(.top, 10)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: pinDropToast != nil)
            }
            .overlay(alignment: .center) {
                if loadingStyle == 2 && exploreMapService.isLoading && !hasLoadedOnce && !isShowingDetail {
                    breathingMappinOverlay
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: exploreMapService.isLoading)
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                ExploreFilterSheet(filter: $filter, availableTags: availableTags)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    // MARK: - Filter Button (toolbar)

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: filter.isActive
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
                .foregroundStyle(filter.isActive ? SonderColors.terracotta : SonderColors.inkDark)
                .overlay(alignment: .topTrailing) {
                    if filter.isActive {
                        Text("\(filter.activeCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(SonderColors.terracotta)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .toolbarIcon()
        }
    }

    // MARK: - Top Overlay (chips + loading)

    /// Whether the NavigationStack has pushed a detail view (hides top overlay)
    private var isShowingDetail: Bool {
        showDetail || selectedFeedItem != nil || selectedPlaceDetails != nil
    }

    private var topOverlay: some View {
        VStack(spacing: SonderSpacing.xs) {
            if !isShowingDetail {
                layerChips
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        // Drive shimmer animation for pulsing chip loading
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                            shimmerPhase = 1
                        }
                    }
                    .onDisappear {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { shimmerPhase = -1 }
                    }
            }
        }
        .padding(.top, SonderSpacing.xs)
        .animation(.easeInOut(duration: 0.25), value: isShowingDetail)
        .animation(.easeInOut(duration: 0.3), value: exploreMapService.isLoading)
    }

    private var friendsLoadingPill: some View {
        HStack(spacing: SonderSpacing.xs) {
            ProgressView()
                .tint(SonderColors.terracotta)
                .scaleEffect(0.8)
            Text("Loading friends' places…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SonderColors.inkMuted)
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xxs + 2)
        .background(SonderColors.warmGray.opacity(0.95))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var breathingMappinOverlay: some View {
        VStack(spacing: SonderSpacing.sm) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(SonderColors.terracotta)
                .scaleEffect(breatheScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        breatheScale = 1.06
                    }
                }
                .onDisappear {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { breatheScale = 1.0 }
                }

            Text("Loading friends' places…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SonderColors.inkMuted)
        }
        .padding(SonderSpacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Layer Chips

    private var layerChips: some View {
        HStack(spacing: 3) {
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
                isOn: filter.showFriendsPlaces,
                isLoading: loadingStyle == 1 && exploreMapService.isLoading && !hasLoadedOnce
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if !filter.selectedFriendIDs.isEmpty {
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
        .padding(3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func layerChip(label: String, icon: String, isOn: Bool, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                if isOn {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, isOn ? 8 : 10)
            .padding(.vertical, isOn ? 5 : 8)
            .frame(minWidth: 36, minHeight: 32)
            .background(isOn ? SonderColors.terracotta : Color.clear)
            .foregroundStyle(isOn ? .white : SonderColors.inkMuted)
            .clipShape(Capsule())
            .overlay {
                if isLoading {
                    // Warm shimmer sweep
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: SonderColors.terracotta.opacity(0.35), location: 0.4),
                                .init(color: SonderColors.terracotta.opacity(0.5), location: 0.5),
                                .init(color: SonderColors.terracotta.opacity(0.35), location: 0.6),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 1.5)
                        .offset(x: shimmerPhase * geo.size.width * 1.5)
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if isLoading {
                    Capsule()
                        .strokeBorder(SonderColors.terracotta.opacity(0.6), lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }

    // MARK: - Tile Style

    private var selectedTileStyle: TileStyleOption {
        TileStyleOption(rawValue: tileStyleRaw) ?? .standard
    }

    // MARK: - Map

    private var mapContent: some View {
        ZStack {
            if isTabVisible {
                if selectedTileStyle == .standard {
                    appleMapContent
                } else {
                    StyledMapView(
                        tileStyle: selectedTileStyle,
                        cameraPosition: $cameraPosition,
                        mapSelection: $mapSelection,
                        visibleRegion: $visibleRegion,
                        currentCameraDistance: $currentCameraDistance,
                        currentCameraHeading: $currentCameraHeading,
                        currentCameraPitch: $currentCameraPitch,
                        annotatedPins: cachedAnnotatedPins,
                        standaloneWTGItems: filter.showWantToGo ? cachedStandaloneWTG : [],
                        onCameraChanged: { schedulePrefetch() }
                    )
                }
            }
        }
    }

    private var appleMapContent: some View {
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
                    let isRemoving = removingWTGIDs.contains(item.id)
                    let tag = MapPinTag.wantToGo(item.id)
                    Annotation(item.placeName, coordinate: item.coordinate, anchor: .bottom) {
                        WantToGoMapPin()
                            .scaleEffect(isRemoving ? 0.01 : (isSelected ? 1.25 : 1.0))
                            .opacity(isRemoving ? 0 : 1)
                            .animation(.easeOut(duration: 0.15), value: isSelected)
                            .animation(.easeIn(duration: 0.3), value: isRemoving)
                            .simultaneousGesture(TapGesture().onEnded {
                                if isSelected {
                                    withAnimation(.easeOut(duration: 0.15)) {
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
            currentCameraDistance = context.camera.distance
            currentCameraHeading = context.camera.heading
            currentCameraPitch = context.camera.pitch
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
        let isRemoving = removingPinIDs.contains(item.pin.id)
        let tag = MapPinTag.unified(item.pin.id)
        let scale: CGFloat = isRemoving ? 0.01 : (isDropping ? 1.3 : (isSelected ? 1.25 : 1.0))
        let yOffset: CGFloat = isDropping ? -50 : 0
        // Squash on landing: briefly compress, then snap back
        let squashX: CGFloat = (isNewPin && pinDropSettled && !pinDropLanded) ? 1.1 : 1.0
        let squashY: CGFloat = (isNewPin && pinDropSettled && !pinDropLanded) ? 0.85 : 1.0
        return Annotation(item.pin.placeName, coordinate: item.pin.coordinate, anchor: .bottom) {
            ZStack {
                // Water ripple rings behind the pin — only for newly dropped pins
                if isNewPin && showPulseRings {
                    PinDropEffect(ratingColor: SonderColors.pinColor(for: item.pin.bestRating))
                        .offset(y: 20)
                }

                UnifiedMapPinView(
                    pin: item.pin,
                    isWantToGo: item.isWantToGo
                )
                .id(item.identity)
                .offset(y: yOffset)
                .scaleEffect(x: scale * squashX, y: scale * squashY)
                .opacity(isRemoving ? 0 : 1)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: pinDropSettled)
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: pinDropLanded)
                .animation(.easeOut(duration: 0.15), value: isSelected)
                .animation(.easeIn(duration: 0.3), value: isRemoving)
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
                kenBurnsPan(to: coordinate, duration: 0.6)
            }
        }
        withAnimation(.easeOut(duration: 0.15)) { mapSelection = nil }
        cardIsExpanded = false
    }

    /// Returns true when the currently-selected pin still exists in the data.
    private var selectionIsValid: Bool {
        guard let tag = mapSelection else { return true }
        switch tag {
        case .unified(let id):
            return filteredPins.contains { $0.id == id } && !removingPinIDs.contains(id)
        case .wantToGo(let id):
            return standaloneWantToGoItems.contains { $0.id == id } && !removingWTGIDs.contains(id)
        }
    }

    // MARK: - Map Style Menu

    private var mapStyleMenu: some View {
        Menu {
            if selectedTileStyle == .standard {
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
            }

            Section("Map Tiles") {
                ForEach(TileStyleOption.allCases, id: \.self) { style in
                    Button {
                        withAnimation { tileStyleRaw = style.rawValue }
                    } label: {
                        HStack {
                            Label(style.name, systemImage: style.icon)
                            if selectedTileStyle == style { Image(systemName: "checkmark") }
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

    /// All unique tags across every unfiltered unified pin — rebuilt in recomputePins().
    private var availableTags: [String] { cachedAvailableTags }

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
    private var personalLogs: [Log] { userLogs }

    private func refreshUserLogs() {
        guard let userID = authService.currentUser?.id else { return }
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        userLogs = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Changes when a personal log's photo becomes available (e.g. background upload completes).
    /// Triggers pin recomputation so the map icon updates from emoji to photo.
    private var personalLogPhotoFingerprint: Int {
        personalLogs.reduce(0) { $0 + ($1.photoURL != nil ? 1 : 0) }
    }

    /// Place IDs in the user's Want to Go list — rebuilt in recomputePins().
    private var wantToGoPlaceIDs: Set<String> { cachedWantToGoPlaceIDs }

    /// Accessors for memoized pin data
    private var unifiedPins: [UnifiedMapPin] { cachedUnifiedPins }
    private var filteredPins: [UnifiedMapPin] { cachedFilteredPins }
    private var annotatedPins: [(pin: UnifiedMapPin, isWantToGo: Bool, identity: String)] { cachedAnnotatedPins }
    private var standaloneWantToGoItems: [WantToGoMapItem] { cachedStandaloneWTG }

    /// Schedules a debounced pin recomputation (coalesces cascading onChange triggers on startup).
    private func scheduleRecomputePins() {
        recomputeTask?.cancel()
        recomputeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            recomputePins()
        }
    }

    /// Recomputes all pin data from current inputs.
    private func recomputePins() {
        let unified = exploreMapService.computeUnifiedPins(personalLogs: personalLogs, places: Array(places))
        cachedUnifiedPins = unified

        // Rebuild WantToGo place IDs
        cachedWantToGoPlaceIDs = Set(wantToGoService.items.map(\.placeID))

        // Rebuild available tags from all unified pins
        var seenTags = Set<String>()
        for pin in unified {
            let tags: [String]
            switch pin {
            case .personal(let logs, _):
                tags = logs.flatMap { $0.tags }
            case .friends(let place):
                tags = place.logs.flatMap { $0.log.tags }
            case .combined(let logs, _, let fp):
                tags = logs.flatMap { $0.tags } + fp.logs.flatMap { $0.log.tags }
            }
            tags.forEach { seenTags.insert($0) }
        }
        cachedAvailableTags = seenTags.sorted()

        let bookmarked = filter.showWantToGo ? cachedWantToGoPlaceIDs : Set<String>()
        let filtered = exploreMapService.filteredUnifiedPins(pins: unified, filter: filter, bookmarkedPlaceIDs: bookmarked)

        // Detect removed unified pins for shrink-fade animation
        let newIDs = Set(filtered.map(\.id))
        let liveOldIDs = Set(cachedFilteredPins.map(\.id)).subtracting(removingPinIDs)
        let newlyRemoved = liveOldIDs.subtracting(newIDs)

        if !newlyRemoved.isEmpty {
            let ghosts = cachedFilteredPins.filter { newlyRemoved.contains($0.id) }
            removingPinIDs.formUnion(newlyRemoved)
            cachedFilteredPins = filtered + ghosts
            scheduleRemovalCleanup(ids: newlyRemoved, isWTG: false)
        } else {
            let activeGhosts = cachedFilteredPins.filter { removingPinIDs.contains($0.id) }
            cachedFilteredPins = filtered + activeGhosts
        }

        cachedAnnotatedPins = cachedFilteredPins.map { pin in
            let isWtg = filter.showWantToGo && wantToGoPlaceIDs.contains(pin.placeID)
            return (pin: pin, isWantToGo: isWtg, identity: pin.id)
        }

        // Standalone WTG pins (filtered by selected saved list IDs if any)
        let unifiedPlaceIDs = Set(unified.map(\.placeID))
        let selectedListIDs = filter.selectedSavedListIDs
        let newStandaloneWTG = wantToGoMapItems.filter { item in
            guard !unifiedPlaceIDs.contains(item.placeID) && filter.matchesCategories(placeName: item.placeName) else { return false }
            if !selectedListIDs.isEmpty, let listID = item.listID {
                return selectedListIDs.contains(listID)
            }
            return true
        }

        let newWTGIDs = Set(newStandaloneWTG.map(\.id))
        let liveOldWTGIDs = Set(cachedStandaloneWTG.map(\.id)).subtracting(removingWTGIDs)
        let newlyRemovedWTG = liveOldWTGIDs.subtracting(newWTGIDs)

        if !newlyRemovedWTG.isEmpty {
            let wtgGhosts = cachedStandaloneWTG.filter { newlyRemovedWTG.contains($0.id) }
            removingWTGIDs.formUnion(newlyRemovedWTG)
            cachedStandaloneWTG = newStandaloneWTG + wtgGhosts
            scheduleRemovalCleanup(ids: newlyRemovedWTG, isWTG: true)
        } else {
            let activeWTGGhosts = cachedStandaloneWTG.filter { removingWTGIDs.contains($0.id) }
            cachedStandaloneWTG = newStandaloneWTG + activeWTGGhosts
        }
    }

    /// Removes ghost pins from cached arrays after the shrink-fade animation completes.
    private func scheduleRemovalCleanup(ids: Set<String>, isWTG: Bool) {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if isWTG {
                removingWTGIDs.subtract(ids)
                cachedStandaloneWTG.removeAll { ids.contains($0.id) }
            } else {
                removingPinIDs.subtract(ids)
                cachedFilteredPins.removeAll { ids.contains($0.id) }
                cachedAnnotatedPins.removeAll { ids.contains($0.pin.id) }
            }
        }
        removalCleanupTasks.append(task)
        // Prune completed tasks to prevent unbounded growth
        removalCleanupTasks.removeAll { $0.isCancelled }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let userID = authService.currentUser?.id else { return }

        // Skip full reload if we loaded recently (< 30s) — WTG changes
        // are handled incrementally via onChange/task(id:)
        if let lastLoad = lastFullLoadAt, Date().timeIntervalSince(lastLoad) < 30 {
            return
        }

        // Run independent network calls concurrently — no data dependencies between them
        async let wtgSync: Void = wantToGoService.syncWantToGo(for: userID)
        async let friendsLoad: Void = exploreMapService.loadFriendsPlaces(for: userID)
        async let wtgItems: Void = loadWantToGoItems()
        _ = await (wtgSync, friendsLoad, wtgItems)
        lastFullLoadAt = Date()

        if !hasLoadedOnce {
            fitAllPins()
            hasLoadedOnce = true
            await cacheService.backfillMissingPhotoReferences(using: placesService)
        }

        prefetchPinPhotos()
    }

    /// Prompts on first Explore visit so user location is available for map centering.
    /// System dialog only appears when status is `.notDetermined`.
    private func requestLocationPermissionIfNeeded() {
        guard locationService.authorizationStatus == .notDetermined else { return }
        locationService.requestPermission()
    }

    private func loadWantToGoItems() async {
        guard let userID = authService.currentUser?.id else { return }
        do {
            wantToGoMapItems = try await wantToGoService.fetchWantToGoForMap(for: userID)
            previousWTGPlaceIDs = Set(wantToGoMapItems.map(\.placeID))
        }
        catch { logger.error("Error loading want to go for map: \(error.localizedDescription)") }
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
                            logger.error("Error fetching WTG map items: \(error.localizedDescription)")
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
    /// Cancels any in-flight downloads from a previous batch before starting new ones.
    private func prefetchPinPhotos() {
        // Cancel previous batch — those pins may no longer be visible
        for task in activePrefetchDownloads { task.cancel() }
        activePrefetchDownloads.removeAll()

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
        let scale = UITraitCollection.current.displayScale
        let targetPixelSize = CGSize(
            width: PinPhotoConstants.pointSize.width * scale,
            height: PinPhotoConstants.pointSize.height * scale
        )

        for ref in photoRefs {
            guard let url = GooglePlacesService.photoURL(for: ref, maxWidth: PinPhotoConstants.maxWidth) else { continue }
            let cacheKey = ImageDownsampler.cacheKey(for: url, pointSize: PinPhotoConstants.pointSize)
            guard ImageDownsampler.cache.object(forKey: cacheKey) == nil else { continue }

            let download = Task.detached(priority: .utility) {
                do {
                    let (data, _) = try await ImageDownsampler.session.data(from: url)
                    guard !Task.isCancelled else { return }
                    if let downsampled = ImageDownsampler.downsample(data: data, to: targetPixelSize) {
                        ImageDownsampler.cache.setObject(downsampled, forKey: cacheKey)
                    }
                } catch { }
            }
            activePrefetchDownloads.append(download)
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

        // Set up the drop animation states
        pinDropSettled = false
        pinDropLanded = false
        showPulseRings = false
        newPinPlaceID = match?.placeID

        // Zoom camera to the new pin location
        zoomToSelected(coordinate: coord)

        // Show context toast immediately (Supabase insertion already complete)
        if let match {
            pinDropToast = PinDropToastInfo(
                placeName: match.placeName,
                ratingEmoji: match.userRating?.emoji ?? "📍"
            )
        }

        // Run the sequenced animation in a single cancellable task
        // (replaces 4 DispatchQueue.main.asyncAfter calls that couldn't be cancelled)
        pinDropCleanupTask?.cancel()
        pinDropCleanupTask = Task { @MainActor in
            // Phase 1: settle the pin (50ms delay for spring to start from dropped position)
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                pinDropSettled = true
            }

            // Phase 1b: squash-and-stretch on landing (~300ms after settle starts)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            SonderHaptics.impact(.medium)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                pinDropLanded = true
            }

            // Phase 2: water ripple rings after pin lands
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            SonderHaptics.impact(.light, intensity: 0.5)
            showPulseRings = true

            // Phase 3: dismiss toast
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            pinDropToast = nil

            // Phase 4: clean up animation state
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            newPinPlaceID = nil
            pinDropLanded = true
            showPulseRings = false
        }
    }

    private func fitAllPins() {
        kenBurnsTask?.cancel()
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
    /// When already zoomed in, drives a Ken Burns cinematic drift frame-by-frame
    /// (bypasses MapKit's internal animation which snaps for small panning distances).
    /// When zoomed out, zooms in to neighborhood level.
    private func zoomToSelected(coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span

        if let span = currentSpan, span.latitudeDelta > 0.15 {
            // Zoomed out — zoom in to neighborhood level
            kenBurnsTask?.cancel()
            let meters = 3000.0 / 111_000.0
            let targetSpan = MKCoordinateSpan(latitudeDelta: meters, longitudeDelta: meters)
            withAnimation(.smooth(duration: 1.2)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: targetSpan
                ))
            }
        } else {
            // Already zoomed in — Ken Burns with subtle 3% push-in
            kenBurnsPan(to: coordinate, duration: 1.2, pushIn: 0.97)
        }
    }

    /// Recenter pin when the bottom card expands or collapses.
    /// Expanded sheet covers ~half the screen — offset pin upward so it stays visible.
    /// Compact sheet — center pin on screen, no offset needed.
    private func recenterForCardState(coordinate: CLLocationCoordinate2D, expanded: Bool) {
        if expanded {
            let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span
                ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            let latOffset = currentSpan.latitudeDelta * 0.25
            let offsetCenter = CLLocationCoordinate2D(
                latitude: coordinate.latitude - latOffset,
                longitude: coordinate.longitude
            )
            kenBurnsPan(to: offsetCenter, duration: 0.8)
        } else {
            kenBurnsPan(to: coordinate, duration: 0.8)
        }
    }

    // MARK: - Ken Burns Camera Drift

    /// Drives a cinematic camera drift from the current position to the target coordinate.
    /// Manually interpolates frame-by-frame at ~60fps using cubic ease-in-out.
    /// This bypasses MapKit's internal animation engine which snaps for small pan distances.
    private func kenBurnsPan(
        to target: CLLocationCoordinate2D,
        duration: TimeInterval = 1.2,
        pushIn: Double = 1.0
    ) {
        kenBurnsTask?.cancel()

        let startCenter = visibleRegion?.center ?? target
        let startDistance = currentCameraDistance > 0 ? currentCameraDistance : 5000
        let targetDistance = startDistance * pushIn
        let heading = currentCameraHeading
        let pitch = currentCameraPitch

        kenBurnsTask = Task { @MainActor in
            let startTime = CACurrentMediaTime()

            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let t = min(elapsed / duration, 1.0)
                // Cubic ease-in-out for film-like acceleration/deceleration
                let eased = t < 0.5
                    ? 4 * t * t * t
                    : 1 - pow(-2 * t + 2, 3) / 2

                let lat = startCenter.latitude + (target.latitude - startCenter.latitude) * eased
                let lng = startCenter.longitude + (target.longitude - startCenter.longitude) * eased
                let dist = startDistance + (targetDistance - startDistance) * eased

                cameraPosition = .camera(MapCamera(
                    centerCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    distance: dist,
                    heading: heading,
                    pitch: pitch
                ))

                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
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
                logger.error("Error removing from want to go: \(error.localizedDescription)")
            }
        }
    }

    private func centerOnUser() {
        kenBurnsTask?.cancel()
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

    // MARK: - Map Snapshot

    /// Captures a static image of the current map region using MKMapSnapshotter,
    /// then composites pin dots at the correct positions so the placeholder
    /// visually matches what the user was just looking at.
    private func captureMapSnapshot() {
        guard let region = visibleRegion ?? cameraPosition.region else { return }
        let capturedGeneration = snapshotGeneration

        let screenBounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        let size = screenBounds.size
        let snapshotScale = min(UITraitCollection.current.displayScale, 2)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = snapshotScale

        // Match the current map style
        switch mapStyle {
        case .minimal:
            options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        case .standard:
            options.preferredConfiguration = MKStandardMapConfiguration()
        case .hybrid:
            options.preferredConfiguration = MKHybridMapConfiguration()
        case .imagery:
            options.preferredConfiguration = MKImageryMapConfiguration()
        }

        // Capture current pin data before the async snapshot starts
        let pins = cachedFilteredPins
        let wtgItems = cachedStandaloneWTG
        let showWTG = filter.showWantToGo

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { result, _ in
            guard let result else { return }

            let format = UIGraphicsImageRendererFormat()
            format.scale = result.image.scale
            let renderer = UIGraphicsImageRenderer(size: size, format: format)

            let composited = renderer.image { _ in
                // Draw base map tiles
                result.image.draw(at: .zero)

                // Draw unified pin dots
                for pin in pins {
                    let point = result.point(for: pin.coordinate)
                    let color: UIColor
                    switch pin {
                    case .personal(let logs, _), .combined(let logs, _, _):
                        let rating = logs.first?.rating
                        switch rating {
                        case .mustSee: color = UIColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1)
                        case .great:   color = UIColor(red: 0.82, green: 0.68, blue: 0.38, alpha: 1)
                        case .okay:    color = UIColor(red: 0.55, green: 0.65, blue: 0.52, alpha: 1)
                        case .skip:    color = UIColor(red: 0.62, green: 0.60, blue: 0.56, alpha: 1)
                        case .none:    color = UIColor(red: 0.80, green: 0.45, blue: 0.35, alpha: 1)
                        }
                    case .friends:
                        color = UIColor(red: 0.55, green: 0.65, blue: 0.52, alpha: 1)
                    }
                    Self.drawPinDot(at: point, color: color, radius: 7)
                }

                // Draw standalone Want to Go pin dots
                if showWTG {
                    let wtgColor = UIColor(red: 0.30, green: 0.58, blue: 0.62, alpha: 1)
                    for item in wtgItems {
                        let point = result.point(for: item.coordinate)
                        Self.drawPinDot(at: point, color: wtgColor, radius: 5)
                    }
                }
            }

            Task { @MainActor in
                guard self.snapshotGeneration == capturedGeneration else { return }
                self.mapSnapshot = composited
            }
        }
    }

    /// Draws a filled circle with a white border at the given point.
    private static func drawPinDot(at point: CGPoint, color: UIColor, radius: CGFloat) {
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        color.setFill()
        UIColor.white.setStroke()
        let path = UIBezierPath(ovalIn: rect)
        path.lineWidth = 1.5
        path.fill()
        path.stroke()
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
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(1)

            Text("logged")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.sm)
        .background(.ultraThinMaterial)
        .background(SonderColors.cream.opacity(0.7))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Pin Drop Effect

/// Concentric water-ripple rings that expand outward when a new pin lands on the map.
struct PinDropEffect: View {
    let ratingColor: Color

    @State private var ring1Active = false
    @State private var ring2Active = false
    @State private var ring3Active = false

    var body: some View {
        ZStack {
            // Ring 1 — first, thickest
            Circle()
                .stroke(ratingColor, lineWidth: 2.5)
                .frame(width: 40, height: 40)
                .scaleEffect(ring1Active ? 3.0 : 0.3)
                .opacity(ring1Active ? 0 : 0.5)

            // Ring 2 — 150ms delay, medium stroke
            Circle()
                .stroke(ratingColor, lineWidth: 2.0)
                .frame(width: 40, height: 40)
                .scaleEffect(ring2Active ? 3.0 : 0.3)
                .opacity(ring2Active ? 0 : 0.45)

            // Ring 3 — 300ms delay, thinnest
            Circle()
                .stroke(ratingColor, lineWidth: 1.5)
                .frame(width: 40, height: 40)
                .scaleEffect(ring3Active ? 3.0 : 0.3)
                .opacity(ring3Active ? 0 : 0.4)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                ring1Active = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 1.0)) {
                    ring2Active = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 1.0)) {
                    ring3Active = true
                }
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
    var listID: String?
    var listName: String?
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
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    if let address = item.placeAddress, !address.isEmpty {
                        Text(address)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SonderColors.wantToGoPin)
                        Text("On your \(item.listName ?? "Want to Go") list")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }

                Spacer()

                WantToGoButton(placeID: item.placeID, placeName: item.placeName, placeAddress: item.placeAddress, photoReference: item.photoReference)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SonderColors.inkLight)
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
