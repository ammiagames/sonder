//
//  OtherUserMapView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import MapKit

/// View another user's logged places on a map (read-only)
struct OtherUserMapView: View {
    let userID: String
    let username: String
    let logs: [FeedItem]

    @Environment(LocationService.self) private var locationService
    @Environment(\.isTabVisible) private var isTabVisible

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 37.7749, longitude: -122.4194), distance: 50000)))
    @State private var selectedPlaceID: String?
    @State private var sheetPin: UnifiedMapPin?  // drives card separately from Map selection
    @State private var mapStyle: MapStyleOption = .minimal
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var hasSetInitialCamera = false
    @State private var cardIsExpanded = false
    @State private var selectedFeedItem: FeedItem?

    /// All log coordinates for fit-all / recenter.
    private var allCoordinates: [CLLocationCoordinate2D] {
        logs.map { CLLocationCoordinate2D(latitude: $0.place.latitude, longitude: $0.place.longitude) }
    }

    /// Logs grouped by place ID, sorted most-recent-first within each group.
    private var groupedLogs: [(placeID: String, place: FeedItem.FeedPlace, items: [FeedItem])] {
        let grouped = Dictionary(grouping: logs) { $0.place.id }
        return grouped.compactMap { (placeID, items) in
            let sorted = items.sorted { $0.log.createdAt > $1.log.createdAt }
            guard let first = sorted.first else { return nil }
            return (placeID: placeID, place: first.place, items: sorted)
        }
    }

    /// Converts a grouped log entry into a UnifiedMapPin.friends for the shared card.
    private func makePin(for group: (placeID: String, place: FeedItem.FeedPlace, items: [FeedItem])) -> UnifiedMapPin {
        let explorePlace = ExploreMapPlace(
            id: group.placeID,
            name: group.place.name,
            address: group.place.address,
            coordinate: CLLocationCoordinate2D(
                latitude: group.place.latitude,
                longitude: group.place.longitude
            ),
            photoReference: group.place.photoReference,
            logs: group.items
        )
        return .friends(place: explorePlace)
    }

    var body: some View {
        ZStack {
            if isTabVisible {
                Map(position: $cameraPosition, selection: $selectedPlaceID) {
                    ForEach(groupedLogs, id: \.placeID) { group in
                        let isSelected = selectedPlaceID == group.placeID
                        let bestItem = group.items[0]
                        Annotation(
                            group.place.name,
                            coordinate: CLLocationCoordinate2D(
                                latitude: group.place.latitude,
                                longitude: group.place.longitude
                            ),
                            anchor: .center
                        ) {
                            LogPinView(
                                rating: bestItem.rating,
                                photoURLs: group.items.compactMap(\.log.photoURL),
                                visitCount: group.items.count
                            )
                            .scaleEffect(isSelected ? 1.25 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: isSelected)
                            .simultaneousGesture(TapGesture().onEnded {
                                if isSelected {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedPlaceID = nil
                                    }
                                }
                            })
                        }
                        .tag(group.placeID)
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
        }
        .safeAreaInset(edge: .top) {
            ownerBanner
        }
        .overlay(alignment: .bottom) {
            if let pin = sheetPin {
                UnifiedBottomCard(
                    pin: pin,
                    onDismiss: {
                        SonderHaptics.selectionChanged()
                        clearSelection()
                    },
                    onNavigateToLog: { _, _ in },
                    onNavigateToFeedItem: { feedItem in
                        withAnimation(.smooth(duration: 0.2)) { sheetPin = nil }
                        selectedPlaceID = nil
                        cardIsExpanded = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            selectedFeedItem = feedItem
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
        .navigationDestination(item: $selectedFeedItem) { feedItem in
            FeedLogDetailView(feedItem: feedItem)
        }
        .navigationTitle("\(username)'s Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    recenterButton
                    mapStyleMenu
                }
            }
        }
        .onAppear {
            if !hasSetInitialCamera {
                hasSetInitialCamera = true
                fitAllPins()
            }
        }
        .onChange(of: selectedPlaceID) { _, newID in
            // Manage card presentation — separate from Map selection
            if let newID,
               let group = groupedLogs.first(where: { $0.placeID == newID }) {
                withAnimation(.smooth(duration: 0.25)) { sheetPin = makePin(for: group) }
                SonderHaptics.impact(.soft)
            } else {
                // Deselected or invalid — dismiss card
                withAnimation(.smooth(duration: 0.25)) { sheetPin = nil }
            }

            cardIsExpanded = false

            // Zoom to selected pin
            guard let newID else { return }
            if let group = groupedLogs.first(where: { $0.placeID == newID }) {
                let coord = CLLocationCoordinate2D(
                    latitude: group.place.latitude,
                    longitude: group.place.longitude
                )
                zoomToSelected(coordinate: coord)
            }
        }
    }

    // MARK: - Selection Management

    /// Recenters camera on pin (removes expansion offset), then clears selection.
    private func clearSelection() {
        if let pin = sheetPin {
            let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span
                ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            withAnimation(.smooth(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: pin.coordinate, span: currentSpan))
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) { selectedPlaceID = nil }
        cardIsExpanded = false
    }

    // MARK: - Owner Banner

    private var ownerBanner: some View {
        Text("\(username)'s Map")
            .font(SonderTypography.caption)
            .fontWeight(.medium)
            .foregroundStyle(SonderColors.inkDark)
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xxs + 2)
            .background(.ultraThinMaterial)
            .background(SonderColors.cream.opacity(0.6))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            .padding(.top, SonderSpacing.xxs)
    }

    // MARK: - Recenter Button

    private var recenterButton: some View {
        Button {
            clearSelection()
            fitAllPins()
            SonderHaptics.impact(.light)
        } label: {
            Image(systemName: "arrow.trianglehead.counterclockwise")
                .toolbarIcon()
        }
        .foregroundStyle(SonderColors.terracotta)
    }

    // MARK: - Camera Helpers

    private func fitAllPins() {
        let coordinates = allCoordinates
        if !coordinates.isEmpty {
            let region = MKCoordinateRegion(coordinates: coordinates)
            if region.span.latitudeDelta > 10 || region.span.longitudeDelta > 10 {
                centerOnUser()
            } else {
                withAnimation(.smooth(duration: 1.5)) { cameraPosition = .region(region) }
            }
        } else {
            centerOnUser()
        }
    }

    private func zoomToSelected(coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span
            ?? cameraPosition.region?.span
            ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)

        withAnimation(.smooth(duration: 1.0)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: currentSpan
            ))
        }
    }

    private func recenterForCardState(coordinate: CLLocationCoordinate2D, expanded: Bool) {
        let currentSpan = visibleRegion?.span ?? cameraPosition.region?.span
            ?? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

        if expanded {
            let latOffset = currentSpan.latitudeDelta * 0.25
            let offsetCenter = CLLocationCoordinate2D(
                latitude: coordinate.latitude - latOffset,
                longitude: coordinate.longitude
            )
            withAnimation(.smooth(duration: 0.8)) {
                cameraPosition = .region(MKCoordinateRegion(center: offsetCenter, span: currentSpan))
            }
        } else {
            withAnimation(.smooth(duration: 0.8)) {
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentSpan))
            }
        }
    }

    private func centerOnUser() {
        if let location = locationService.currentLocation {
            withAnimation(.smooth(duration: 1.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location, latitudinalMeters: 5000, longitudinalMeters: 5000
                ))
            }
        } else {
            withAnimation(.smooth(duration: 1.5)) {
                cameraPosition = .userLocation(fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 37.7749, longitude: -122.4194), distance: 50000)))
            }
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
}

#Preview {
    NavigationStack {
        OtherUserMapView(
            userID: "user123",
            username: "johndoe",
            logs: []
        )
    }
}
