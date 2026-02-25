//
//  StyledMapView.swift
//  sonder
//
//  UIViewRepresentable wrapper around MKMapView with custom raster tile overlays.
//  Renders Carto (or other) tiles while hosting existing SwiftUI pin views.
//

import SwiftUI
import MapKit

// MARK: - Tile Style (placeholder for future custom map tiles)

enum TileStyleOption: String, CaseIterable {
    case standard
    case carto

    var name: String {
        switch self {
        case .standard: return "Apple"
        case .carto: return "Carto"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "apple.logo"
        case .carto: return "map.fill"
        }
    }

    var tileURLTemplate: String? {
        switch self {
        case .standard: return nil
        case .carto: return "https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png"
        }
    }
}

// MARK: - Pin Annotation Model

/// Bridges SwiftUI pin data into MKAnnotation for UIKit's MKMapView.
final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let tag: MapPinTag
    let pinID: String
    let isWantToGo: Bool
    let pin: UnifiedMapPin?
    let wtgItem: WantToGoMapItem?

    var title: String? { pin?.placeName ?? wtgItem?.placeName }

    init(pin: UnifiedMapPin, isWantToGo: Bool) {
        self.coordinate = pin.coordinate
        self.tag = .unified(pin.id)
        self.pinID = pin.id
        self.isWantToGo = isWantToGo
        self.pin = pin
        self.wtgItem = nil
    }

    init(wtgItem: WantToGoMapItem) {
        self.coordinate = wtgItem.coordinate
        self.tag = .wantToGo(wtgItem.id)
        self.pinID = wtgItem.id
        self.isWantToGo = true
        self.pin = nil
        self.wtgItem = wtgItem
    }
}

// MARK: - StyledMapView

struct StyledMapView: UIViewRepresentable {
    let tileStyle: TileStyleOption
    @Binding var cameraPosition: MapCameraPosition
    @Binding var mapSelection: MapPinTag?
    @Binding var visibleRegion: MKCoordinateRegion?
    @Binding var currentCameraDistance: CLLocationDistance
    @Binding var currentCameraHeading: CLLocationDirection
    @Binding var currentCameraPitch: Double

    let annotatedPins: [(pin: UnifiedMapPin, isWantToGo: Bool, identity: String)]
    let standaloneWTGItems: [WantToGoMapItem]
    let onCameraChanged: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true

        // Add tile overlay
        if let template = tileStyle.tileURLTemplate {
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = true
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        // Apply initial camera from the binding
        applyCamera(to: mapView, animated: false)

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Update tile overlay if style changed
        if coordinator.currentTileStyle != tileStyle {
            // Remove old tile overlays
            let tileOverlays = mapView.overlays.filter { $0 is MKTileOverlay }
            mapView.removeOverlays(tileOverlays)

            // Add new tile overlay
            if let template = tileStyle.tileURLTemplate {
                let overlay = MKTileOverlay(urlTemplate: template)
                overlay.canReplaceMapContent = true
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
            coordinator.currentTileStyle = tileStyle
        }

        // Sync camera position from SwiftUI → MKMapView
        if coordinator.pendingCameraUpdate {
            coordinator.pendingCameraUpdate = false
            applyCamera(to: mapView, animated: true)
        }

        // Diff annotations
        diffAnnotations(mapView: mapView, coordinator: coordinator)

        // Sync selection
        syncSelection(mapView: mapView, coordinator: coordinator)
    }

    // MARK: - Camera

    private func applyCamera(to mapView: MKMapView, animated: Bool) {
        if let camera = cameraPosition.camera {
            let mkCamera = MKMapCamera(
                lookingAtCenter: camera.centerCoordinate,
                fromDistance: camera.distance,
                pitch: CGFloat(camera.pitch),
                heading: camera.heading
            )
            mapView.setCamera(mkCamera, animated: animated)
        } else if let region = cameraPosition.region {
            mapView.setRegion(region, animated: animated)
        } else {
            // .userLocation or .automatic — follow user
            mapView.setUserTrackingMode(.follow, animated: animated)
        }
    }

    // MARK: - Annotation Diffing

    private func diffAnnotations(mapView: MKMapView, coordinator: Coordinator) {
        let existingAnnotations = mapView.annotations.compactMap { $0 as? PinAnnotation }
        let existingIDs = Set(existingAnnotations.map(\.pinID))

        // Build desired annotations
        var desiredIDs = Set<String>()
        var desiredByID = [String: PinAnnotation]()

        for item in annotatedPins {
            let annotation = PinAnnotation(pin: item.pin, isWantToGo: item.isWantToGo)
            desiredIDs.insert(annotation.pinID)
            desiredByID[annotation.pinID] = annotation
        }
        for item in standaloneWTGItems {
            let annotation = PinAnnotation(wtgItem: item)
            desiredIDs.insert(annotation.pinID)
            desiredByID[annotation.pinID] = annotation
        }

        // Remove annotations no longer needed
        let toRemove = existingAnnotations.filter { !desiredIDs.contains($0.pinID) }
        if !toRemove.isEmpty {
            mapView.removeAnnotations(toRemove)
        }

        // Add new annotations
        let toAdd = desiredIDs.subtracting(existingIDs)
        let newAnnotations = toAdd.compactMap { desiredByID[$0] }
        if !newAnnotations.isEmpty {
            mapView.addAnnotations(newAnnotations)
        }

        // Update coordinate for existing annotations that moved
        for existing in existingAnnotations {
            if let desired = desiredByID[existing.pinID] {
                if existing.coordinate.latitude != desired.coordinate.latitude ||
                   existing.coordinate.longitude != desired.coordinate.longitude {
                    mapView.removeAnnotation(existing)
                    mapView.addAnnotation(desired)
                }
            }
        }
    }

    // MARK: - Selection Sync

    private func syncSelection(mapView: MKMapView, coordinator: Coordinator) {
        guard !coordinator.isUpdatingSelection else { return }

        let annotations = mapView.annotations.compactMap { $0 as? PinAnnotation }

        if let tag = mapSelection {
            if let match = annotations.first(where: { $0.tag == tag }) {
                if mapView.selectedAnnotations.first as? PinAnnotation !== match {
                    mapView.selectAnnotation(match, animated: true)
                }
            }
        } else {
            if !mapView.selectedAnnotations.isEmpty {
                for selected in mapView.selectedAnnotations {
                    mapView.deselectAnnotation(selected, animated: true)
                }
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: StyledMapView
        var currentTileStyle: TileStyleOption
        var pendingCameraUpdate = false
        var isUpdatingSelection = false
        var isUserInteracting = false
        weak var mapView: MKMapView?

        // Track hosting controllers to avoid leaks
        private var hostingControllers = [String: UIHostingController<AnyView>]()

        init(parent: StyledMapView) {
            self.parent = parent
            self.currentTileStyle = parent.tileStyle
        }

        func update(parent: StyledMapView) {
            self.parent = parent
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let camera = mapView.camera

            Task { @MainActor in
                self.parent.visibleRegion = region
                self.parent.currentCameraDistance = camera.altitude
                self.parent.currentCameraHeading = camera.heading
                self.parent.currentCameraPitch = Double(camera.pitch)
                self.parent.onCameraChanged()
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let pinAnnotation = annotation as? PinAnnotation else { return }
            // Set directly — delegate is always called on the main thread, so no
            // Task hop needed. Skipping the async dispatch eliminates ~16ms of
            // latency between the tap and mapSelection being set.
            isUpdatingSelection = true
            parent.mapSelection = pinAnnotation.tag
            isUpdatingSelection = false
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            guard annotation is PinAnnotation else { return }
            isUpdatingSelection = true
            if mapView.selectedAnnotations.isEmpty {
                parent.mapSelection = nil
            }
            isUpdatingSelection = false
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pinAnnotation = annotation as? PinAnnotation else { return nil }

            let identifier: String
            let swiftUIView: AnyView

            if let pin = pinAnnotation.pin {
                identifier = "unified-\(pinAnnotation.pinID)"
                swiftUIView = AnyView(
                    UnifiedMapPinView(pin: pin, isWantToGo: pinAnnotation.isWantToGo)
                )
            } else if pinAnnotation.wtgItem != nil {
                identifier = "wtg-\(pinAnnotation.pinID)"
                swiftUIView = AnyView(WantToGoMapPin())
            } else {
                return nil
            }

            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            annotationView.annotation = annotation
            annotationView.canShowCallout = false

            // Clean up previous hosting controller
            if let existing = hostingControllers[pinAnnotation.pinID] {
                existing.view.removeFromSuperview()
                existing.removeFromParent()
                hostingControllers.removeValue(forKey: pinAnnotation.pinID)
            }

            // Remove any existing subviews
            annotationView.subviews.forEach { $0.removeFromSuperview() }

            // Host SwiftUI pin view inside UIKit annotation view
            let hostingController = UIHostingController(rootView: swiftUIView)
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false

            annotationView.addSubview(hostingController.view)

            // Size the hosting view
            let targetSize = hostingController.sizeThatFits(in: CGSize(width: 200, height: 200))
            hostingController.view.frame = CGRect(origin: .zero, size: targetSize)
            annotationView.frame = CGRect(origin: .zero, size: targetSize)

            // Center the anchor at the bottom of the pin
            annotationView.centerOffset = CGPoint(x: 0, y: -targetSize.height / 2)

            hostingControllers[pinAnnotation.pinID] = hostingController

            return annotationView
        }
    }
}
