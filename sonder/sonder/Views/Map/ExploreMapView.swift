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

    /// When set to true (by ProfileView), focuses the map on personal places only
    var focusMyPlaces: Binding<Bool>?
    /// Reports whether a pin is currently selected (used by MainTabView to hide FAB)
    var hasSelection: Binding<Bool>?

    var body: some View {
        NavigationStack {
            mapContent
                .navigationTitle("Explore")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        filterButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        mapStyleMenu
                    }
                }
                .overlay(alignment: .top) {
                    layerChips
                        .padding(.top, SonderSpacing.xs)
                }
                .overlay(alignment: .bottom) {
                    bottomContent
                        .animation(.easeOut(duration: 0.15), value: mapSelection)
                }
                .sheet(isPresented: $showFilterSheet) {
                    ExploreFilterSheet(filter: $filter)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .task {
                    await loadData()
                }
                .onChange(of: mapSelection) { _, newTag in
                    hasSelection?.wrappedValue = newTag != nil
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
                .onChange(of: wantToGoService.items.count) { _, _ in
                    if !selectionIsValid { clearSelection() }
                }
                .onChange(of: wantToGoMapItems.count) { _, _ in
                    if !selectionIsValid { clearSelection() }
                }
                .onChange(of: allLogs.count) { _, _ in
                    if !selectionIsValid { clearSelection() }
                }
                .onChange(of: filter) { _, _ in
                    if !selectionIsValid { clearSelection() }
                }
                .task(id: wantToGoService.items.count) {
                    // Reload standalone WTG map items on appearance and when items change
                    await loadWantToGoItems()
                }
                .onChange(of: focusMyPlaces?.wrappedValue) { _, newValue in
                    if newValue == true {
                        handleFocusMyPlaces()
                    }
                }
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
                        RatePlaceView(place: place) {
                            let placeID = placeIDToRemove
                            // Pop the preview first (hidden under the cover)
                            selectedPlaceDetails = nil
                            placeIDToRemove = nil
                            // Clear pin selection so the FAB reappears
                            mapSelection = nil
                            // Dismiss the cover on next frame so preview is already gone
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
        }
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
                let isSelected = mapSelection == .unified(item.pin.id)
                let tag = MapPinTag.unified(item.pin.id)
                Annotation(item.pin.placeName, coordinate: item.pin.coordinate, anchor: .bottom) {
                    UnifiedMapPinView(
                        pin: item.pin,
                        isWantToGo: item.isWantToGo
                    )
                    .id(item.identity)
                    .scaleEffect(isSelected ? 1.25 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
                    // simultaneousGesture lets Map handle initial selection while
                    // we handle re-tap-to-deselect (which Map doesn't always do)
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
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Bottom Content

    @ViewBuilder
    private var bottomContent: some View {
        if let tag = mapSelection {
            switch tag {
            case .unified(let id):
                if let pin = filteredPins.first(where: { $0.id == id }) {
                    UnifiedBottomCard(
                        pin: pin,
                        onDismiss: { clearSelection() },
                        onNavigateToLog: { logID, place in
                            detailLogID = logID
                            detailPlace = place
                            showDetail = true
                        },
                        onNavigateToFeedItem: { feedItem in
                            selectedFeedItem = feedItem
                        },
                        onFocusFriend: { friendID, _ in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filter.selectedFriendIDs = [friendID]
                                filter.showFriendsPlaces = true
                                clearSelection()
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            case .wantToGo(let id):
                if let item = standaloneWantToGoItems.first(where: { $0.id == id }) {
                    WantToGoBottomCard(item: item, onDismiss: { clearSelection() }) {
                        fetchPlaceDetails(placeID: item.placeID)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        } else if !friendsLovedPlaces.isEmpty {
            FriendsLovedCarousel(places: friendsLovedPlaces) { place in
                if let pin = unifiedPins.first(where: { $0.placeID == place.id }) {
                    mapSelection = .unified(pin.id)
                }
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) { mapSelection = nil }
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

    /// All unified pins (unfiltered)
    private var unifiedPins: [UnifiedMapPin] {
        exploreMapService.computeUnifiedPins(personalLogs: personalLogs, places: Array(places))
    }

    /// Unified pins after applying filters
    private var filteredPins: [UnifiedMapPin] {
        exploreMapService.filteredUnifiedPins(
            pins: unifiedPins,
            filter: filter,
            bookmarkedPlaceIDs: filter.showWantToGo ? wantToGoPlaceIDs : []
        )
    }

    private var friendsLovedPlaces: [ExploreMapPlace] {
        exploreMapService.friendsLovedPlaces()
    }

    /// Place IDs in the user's Want to Go list.
    /// Computed directly from @Observable WantToGoService so SwiftUI re-evaluates
    /// the body (and Map content) whenever items change — even while offscreen in a tab.
    private var wantToGoPlaceIDs: Set<String> {
        Set(wantToGoService.items.map(\.placeID))
    }

    /// Unified pins paired with their want-to-go state.
    /// Identity is just the pin ID so annotations stay stable and the badge
    /// animates in/out smoothly instead of the whole annotation being recreated.
    private var annotatedPins: [(pin: UnifiedMapPin, isWantToGo: Bool, identity: String)] {
        filteredPins.map { pin in
            let isWtg = filter.showWantToGo && wantToGoPlaceIDs.contains(pin.placeID)
            return (pin: pin, isWantToGo: isWtg, identity: pin.id)
        }
    }

    /// Want to Go items that don't overlap with any unified pin
    private var standaloneWantToGoItems: [WantToGoMapItem] {
        let unifiedPlaceIDs = Set(unifiedPins.map(\.placeID))
        return wantToGoMapItems.filter { item in
            !unifiedPlaceIDs.contains(item.placeID) && filter.matchesCategories(placeName: item.placeName)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let userID = authService.currentUser?.id else { return }
        await wantToGoService.syncWantToGo(for: userID)
        await exploreMapService.loadFriendsPlaces(for: userID)
        await loadWantToGoItems()

        if !hasLoadedOnce {
            fitAllPins()
            hasLoadedOnce = true
            // Backfill photo references for places cached without them
            await cacheService.backfillMissingPhotoReferences(using: placesService)
        }

        prefetchPinPhotos()
    }

    private func loadWantToGoItems() async {
        guard let userID = authService.currentUser?.id else { return }
        do { wantToGoMapItems = try await wantToGoService.fetchWantToGoForMap(for: userID) }
        catch { print("Error loading want to go for map: \(error)") }
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
        let scale = UIScreen.main.scale
        let targetPixelSize = CGSize(width: 56 * scale, height: 56 * scale)

        for ref in photoRefs {
            guard let url = GooglePlacesService.photoURL(for: ref, maxWidth: 112) else { continue }
            let cacheKey = NSString(string: url.absoluteString)
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

    /// Pans/zooms the camera so a selected pin sits in the visible area above the bottom card.
    private func zoomToSelected(coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span

        // Determine the target span based on current zoom level
        let targetSpan: MKCoordinateSpan

        if let span = currentSpan, span.latitudeDelta > 0.15 {
            // Far out (city-level+) → zoom in to neighborhood
            let meters = 3000.0 / 111_000.0
            targetSpan = MKCoordinateSpan(latitudeDelta: meters, longitudeDelta: meters)
        } else {
            // Already at a reasonable zoom → keep current zoom, just pan
            targetSpan = currentSpan ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        }

        let latOffset = targetSpan.latitudeDelta * 0.18
        let offsetCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude - latOffset,
            longitude: coordinate.longitude
        )

        withAnimation(.smooth(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: offsetCenter,
                span: targetSpan
            ))
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

// MARK: - Want to Go Map Item

struct WantToGoMapItem: Identifiable {
    let id: String
    let placeID: String
    let placeName: String
    let placeAddress: String?
    let photoReference: String?
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Want to Go Bottom Card

/// Bottom card for a tapped Want to Go pin — shows place preview with unbookmark option.
struct WantToGoBottomCard: View {
    let item: WantToGoMapItem
    let onDismiss: () -> Void
    let onTap: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(SonderColors.inkLight.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, SonderSpacing.sm)
                .padding(.bottom, SonderSpacing.xs)

            HStack(spacing: SonderSpacing.sm) {
                // Place photo
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

                    // "On your list" label
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

                // Remove bookmark button
                WantToGoButton(placeID: item.placeID)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SonderColors.inkLight)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)
        }
        .background(SonderColors.cream.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.md)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
                        onDismiss()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
        )
    }
}
