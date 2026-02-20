//
//  ProximityNotificationService.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import Foundation
import CoreLocation
import UserNotifications
import SwiftData
import os

/// Service that monitors user location and sends notifications when near saved "Want to Go" places
@MainActor
@Observable
final class ProximityNotificationService: NSObject {
    private let logger = Logger(subsystem: "com.sonder.app", category: "ProximityNotificationService")
    private var locationManager: CLLocationManager?
    private var wantToGoService: WantToGoService?
    private var currentUserID: String?

    // Configuration
    private let proximityRadius: CLLocationDistance = 500 // meters
    private let minimumTimeBetweenNotifications: TimeInterval = 3600 // 1 hour

    // State
    var isMonitoring = false
    private var lastNotificationTimes: [String: Date] = [:] // placeID -> last notification time
    private var cachedPlaces: [WantToGoWithPlace] = []

    override init() {
        super.init()
    }

    // MARK: - Setup

    func configure(wantToGoService: WantToGoService, userID: String) {
        self.wantToGoService = wantToGoService
        self.currentUserID = userID
    }

    // MARK: - Notification Permissions

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            logger.error("Error requesting notification permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Monitoring Control

    /// Starts monitoring and prompts for notification + location permissions if needed.
    /// Only call this from an explicit user action (e.g. Settings toggle).
    func startMonitoring() async {
        guard !isMonitoring else { return }

        // Request notification permission
        let notificationGranted = await requestNotificationPermission()
        guard notificationGranted else {
            logger.warning("Notification permission not granted")
            return
        }

        // Setup location manager
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager?.allowsBackgroundLocationUpdates = false // Only when app is active for now
        locationManager?.pausesLocationUpdatesAutomatically = true

        // Request location permission
        let authStatus = locationManager?.authorizationStatus ?? .notDetermined
        if authStatus == .notDetermined {
            locationManager?.requestWhenInUseAuthorization()
        } else if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            await refreshCachedPlaces()
            locationManager?.startUpdatingLocation()
            isMonitoring = true
        }
    }

    /// Silently resumes monitoring if permissions were already granted.
    /// Does NOT prompt the user — safe to call on app launch.
    func resumeMonitoringIfAuthorized() async {
        guard !isMonitoring else { return }

        // Check notification permission without prompting
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Check location permission without prompting
        let locationManager = CLLocationManager()
        let authStatus = locationManager.authorizationStatus
        guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else { return }

        // Both permissions already granted — start silently
        self.locationManager = locationManager
        self.locationManager?.delegate = self
        self.locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.locationManager?.allowsBackgroundLocationUpdates = false
        self.locationManager?.pausesLocationUpdatesAutomatically = true

        await refreshCachedPlaces()
        self.locationManager?.startUpdatingLocation()
        isMonitoring = true
    }

    func stopMonitoring() {
        locationManager?.stopUpdatingLocation()
        isMonitoring = false
    }

    // MARK: - Cache Management

    func refreshCachedPlaces() async {
        guard let service = wantToGoService, let userID = currentUserID else { return }

        do {
            cachedPlaces = try await service.fetchWantToGoWithPlaces(for: userID)
        } catch {
            logger.error("Error refreshing cached places: \(error.localizedDescription)")
        }
    }

    // MARK: - Proximity Check

    private func checkProximity(to location: CLLocation) {
        for item in cachedPlaces {
            let placeLocation = CLLocation(
                latitude: item.place.latitude,
                longitude: item.place.longitude
            )

            let distance = location.distance(from: placeLocation)

            if distance <= proximityRadius {
                // Check if we've notified recently
                if shouldNotify(for: item.place.id) {
                    sendProximityNotification(for: item, distance: distance)
                }
            }
        }
    }

    private func shouldNotify(for placeID: String) -> Bool {
        guard let lastTime = lastNotificationTimes[placeID] else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= minimumTimeBetweenNotifications
    }

    // MARK: - Notifications

    private func sendProximityNotification(for item: WantToGoWithPlace, distance: CLLocationDistance) {
        let content = UNMutableNotificationContent()
        content.title = "You're near a saved place!"

        let distanceText = distance < 100 ? "very close to" : "near"

        let listSuffix = item.listName.map { " (\($0))" } ?? ""
        if let sourceUser = item.sourceUser {
            content.body = "You're \(distanceText) \(item.place.name)\(listSuffix) - saved from @\(sourceUser.username)"
        } else {
            content.body = "You're \(distanceText) \(item.place.name)\(listSuffix)"
        }

        content.sound = .default
        content.userInfo = ["placeID": item.place.id]

        // Add category for actions
        content.categoryIdentifier = "PROXIMITY_ALERT"

        let request = UNNotificationRequest(
            identifier: "proximity-\(item.place.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Error sending notification: \(error.localizedDescription)")
            } else {
                // Record notification time
                Task { @MainActor in
                    self.lastNotificationTimes[item.place.id] = Date()
                }
            }
        }
    }

    // MARK: - Notification Categories Setup

    func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_PLACE",
            title: "View Details",
            options: .foreground
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )

        let category = UNNotificationCategory(
            identifier: "PROXIMITY_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - CLLocationManagerDelegate

extension ProximityNotificationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Only process if location is recent and accurate enough
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < 60, location.horizontalAccuracy < 100 else { return }

        Task { @MainActor in
            self.checkProximity(to: location)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if !self.isMonitoring {
                    await self.refreshCachedPlaces()
                    manager.startUpdatingLocation()
                    self.isMonitoring = true
                }
            } else {
                self.stopMonitoring()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Logger is Sendable so safe to access from nonisolated context
        let log = self.logger
        log.error("Location manager error: \(error.localizedDescription)")
    }
}
