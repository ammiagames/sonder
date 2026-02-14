//
//  MapHelpers.swift
//  sonder
//
//  Shared map utilities extracted from LogMapView.
//

import SwiftUI
import MapKit

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
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .standard:
            return .standard(elevation: .flat, pointsOfInterest: .including([.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .museum, .nationalPark, .park, .beach]))
        case .hybrid:
            return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        case .imagery:
            return .imagery(elevation: .flat)
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
