//
//  LogMapView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import MapKit
import SwiftData

// MARK: - Map Style Options

enum MapStyleOption: String, CaseIterable {
    case minimal
    case standard
    case hybrid
    case imagery

    var name: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .hybrid: return "Hybrid"
        case .imagery: return "Satellite"
        }
    }

    var icon: String {
        switch self {
        case .minimal: return "circle.grid.2x1"
        case .standard: return "map"
        case .hybrid: return "square.2.layers.3d"
        case .imagery: return "globe.americas"
        }
    }

    var style: MapStyle {
        switch self {
        case .minimal:
            // Clean, muted look - no POIs, subdued colors
            return .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .standard:
            return .standard(elevation: .realistic, pointsOfInterest: .including([.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .museum, .nationalPark, .park, .beach]))
        case .hybrid:
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .imagery:
            return .imagery(elevation: .realistic)
        }
    }
}

/// Map view showing all logged places with color-coded pins
struct LogMapView: View {
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query private var places: [Place]
    @Environment(LocationService.self) private var locationService
    @Environment(AuthenticationService.self) private var authService

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedMapLog: Log?
    @State private var navigationLog: Log?
    @State private var mapStyle: MapStyleOption = .minimal

    /// Logs filtered to current user only
    private var logs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
    }

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition, selection: $selectedMapLog) {
                // User location
                UserAnnotation()

                // Log pins
                ForEach(logs, id: \.id) { log in
                    if let place = place(for: log) {
                        Annotation(
                            place.name,
                            coordinate: place.coordinate,
                            anchor: .bottom
                        ) {
                            LogPinView(rating: log.rating)
                        }
                        .tag(log)
                    }
                }
            }
            .mapStyle(mapStyle.style)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("View") {
                            Button {
                                fitAllPins()
                            } label: {
                                Label("Show All", systemImage: "arrow.up.left.and.arrow.down.right")
                            }

                            Button {
                                centerOnUser()
                            } label: {
                                Label("My Location", systemImage: "location")
                            }
                        }

                        Section("Map Style") {
                            ForEach(MapStyleOption.allCases, id: \.self) { style in
                                Button {
                                    withAnimation {
                                        mapStyle = style
                                    }
                                } label: {
                                    HStack {
                                        Label(style.name, systemImage: style.icon)
                                        if mapStyle == style {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(item: $navigationLog) { log in
                if let place = place(for: log) {
                    LogDetailView(log: log, place: place)
                }
            }
            .onChange(of: selectedMapLog) { _, newLog in
                if let log = newLog {
                    navigationLog = log
                    // Clear selection so pin can be tapped again
                    selectedMapLog = nil
                }
            }
            .onAppear {
                if logs.isEmpty {
                    centerOnUser()
                } else {
                    fitAllPins()
                }
            }
        }
    }

    // MARK: - Helpers

    private func place(for log: Log) -> Place? {
        places.first { $0.id == log.placeID }
    }

    private func fitAllPins() {
        let coordinates = logs.compactMap { log -> CLLocationCoordinate2D? in
            guard let place = place(for: log) else { return nil }
            return place.coordinate
        }

        guard !coordinates.isEmpty else {
            centerOnUser()
            return
        }

        let region = MKCoordinateRegion(coordinates: coordinates)
        withAnimation {
            cameraPosition = .region(region)
        }
    }

    private func centerOnUser() {
        if let location = locationService.currentLocation {
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location,
                    latitudinalMeters: 5000,
                    longitudinalMeters: 5000
                ))
            }
        }
    }
}

// MARK: - Log Pin View

struct LogPinView: View {
    let rating: Rating

    var body: some View {
        ZStack {
            // Pin shape
            Circle()
                .fill(pinColor)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Rating emoji
            Text(rating.emoji)
                .font(.system(size: 18))
        }
    }

    private var pinColor: Color {
        switch rating {
        case .skip:
            return SonderColors.ratingSkip
        case .solid:
            return SonderColors.ratingSolid
        case .mustSee:
            return SonderColors.ratingMustSee
        }
    }
}

// MARK: - MKCoordinateRegion Extension

extension MKCoordinateRegion {
    /// Creates a region that fits all given coordinates
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                latitudinalMeters: 10000,
                longitudinalMeters: 10000
            )
            return
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.01
        )

        self = MKCoordinateRegion(center: center, span: span)
    }
}

#Preview {
    LogMapView()
}
