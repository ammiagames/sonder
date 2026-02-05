//
//  LocationService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import CoreLocation

/// CoreLocation wrapper for managing user location
@Observable
@MainActor
final class LocationService: NSObject {
    private let locationManager = CLLocationManager()

    var currentLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    var error: LocationError?

    enum LocationError: LocalizedError {
        case denied
        case restricted
        case unableToDetermineLocation
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access denied. Please enable in Settings."
            case .restricted:
                return "Location access is restricted on this device."
            case .unableToDetermineLocation:
                return "Unable to determine your location."
            case .unknown(let error):
                return error.localizedDescription
            }
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Request location permission
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request a single location update
    func requestLocation() {
        error = nil

        switch authorizationStatus {
        case .notDetermined:
            requestPermission()
        case .denied:
            error = .denied
        case .restricted:
            error = .restricted
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        @unknown default:
            break
        }
    }

    /// Start continuous location updates
    func startUpdatingLocation() {
        guard isAuthorized else {
            requestPermission()
            return
        }
        locationManager.startUpdatingLocation()
    }

    /// Stop continuous location updates
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.error = .denied
                case .locationUnknown:
                    self.error = .unableToDetermineLocation
                default:
                    self.error = .unknown(error)
                }
            } else {
                self.error = .unknown(error)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            // Automatically request location when authorized
            if self.isAuthorized && self.currentLocation == nil {
                manager.requestLocation()
            }
        }
    }
}
