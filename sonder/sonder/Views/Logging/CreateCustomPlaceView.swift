//
//  CreateCustomPlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData
import MapKit
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "CreateCustomPlaceView")

/// View for creating a custom place that isn't in Google Places
struct CreateCustomPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService

    let onPlaceCreated: (Place) -> Void

    @State private var placeName = ""
    @State private var placeAddress = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showMap = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.xl) {
                    // Name section
                    nameSection

                    // Address section
                    addressSection

                    // Location section
                    locationSection

                    // Create button
                    createButton
                        .padding(.top, SonderSpacing.sm)
                }
                .padding(SonderSpacing.lg)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SonderColors.cream)
            .navigationTitle("Add Your Own Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .sheet(isPresented: $showMap) {
                LocationPickerView(
                    selectedCoordinate: $selectedCoordinate,
                    initialCoordinate: selectedCoordinate ?? locationService.currentLocation
                )
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Name")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("What's this place called?", text: $placeName)
                .font(SonderTypography.body)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .autocorrectionDisabled()
        }
    }

    // MARK: - Address Section

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Address")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("Street address (optional)", text: $placeAddress)
                .font(SonderTypography.body)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .autocorrectionDisabled()
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Location")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            if let coordinate = selectedCoordinate {
                // Location set — warm card with checkmark
                HStack(spacing: SonderSpacing.sm) {
                    Circle()
                        .fill(SonderColors.sage.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(SonderColors.sage)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location pinned")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)

                        Text("\(coordinate.latitude, specifier: "%.4f"), \(coordinate.longitude, specifier: "%.4f")")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }

                    Spacer()

                    Button {
                        showMap = true
                    } label: {
                        Text("Change")
                            .font(SonderTypography.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(SonderColors.terracotta)
                            .padding(.horizontal, SonderSpacing.sm)
                            .padding(.vertical, SonderSpacing.xxs)
                            .background(SonderColors.terracotta.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            } else {
                // Location options — two tappable warm cards
                VStack(spacing: SonderSpacing.sm) {
                    Button {
                        useCurrentLocation()
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Circle()
                                .fill(SonderColors.terracotta.opacity(0.1))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(SonderColors.terracotta)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use Current Location")
                                    .font(SonderTypography.headline)
                                    .foregroundStyle(SonderColors.inkDark)

                                Text("Pin to where you are now")
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SonderColors.inkLight)
                        }
                        .padding(SonderSpacing.md)
                        .background(SonderColors.warmGray)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showMap = true
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Circle()
                                .fill(SonderColors.ochre.opacity(0.1))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "map")
                                        .font(.system(size: 16))
                                        .foregroundStyle(SonderColors.ochre)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Choose on Map")
                                    .font(SonderTypography.headline)
                                    .foregroundStyle(SonderColors.inkDark)

                                Text("Tap anywhere to drop a pin")
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SonderColors.inkLight)
                        }
                        .padding(SonderSpacing.md)
                        .background(SonderColors.warmGray)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)
                }

                Text("Required — helps show this place on your map")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            createPlace()
        } label: {
            Text("Create Place")
                .font(SonderTypography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.md)
                .background(isValid ? SonderColors.terracotta : SonderColors.inkLight.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
    }

    private var isValid: Bool {
        !placeName.trimmingCharacters(in: .whitespaces).isEmpty && selectedCoordinate != nil
    }

    private func useCurrentLocation() {
        if let location = locationService.currentLocation {
            selectedCoordinate = location
        }
    }

    private func createPlace() {
        guard let coordinate = selectedCoordinate else { return }

        let trimmedName = placeName.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = placeAddress.trimmingCharacters(in: .whitespaces)

        // Generate a unique ID for custom places
        let customID = "custom_\(UUID().uuidString)"

        let place = Place(
            id: customID,
            name: trimmedName,
            address: trimmedAddress.isEmpty ? "Custom location" : trimmedAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        // Save to local database
        modelContext.insert(place)
        try? modelContext.save()

        // Callback handles navigation - parent will dismiss
        onPlaceCreated(place)
    }
}

// MARK: - Location Picker View

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    let initialCoordinate: CLLocationCoordinate2D?

    @State private var cameraPosition: MapCameraPosition
    @State private var pinCoordinate: CLLocationCoordinate2D?

    init(selectedCoordinate: Binding<CLLocationCoordinate2D?>, initialCoordinate: CLLocationCoordinate2D?) {
        self._selectedCoordinate = selectedCoordinate
        self.initialCoordinate = initialCoordinate

        let startCoordinate = initialCoordinate ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: startCoordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )))
        _pinCoordinate = State(initialValue: selectedCoordinate.wrappedValue ?? initialCoordinate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Show pin if coordinate is set
                        if let coordinate = pinCoordinate {
                            Annotation("", coordinate: coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(SonderColors.terracotta)
                            }
                        }

                        UserAnnotation()
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onTapGesture { position in
                        if let coordinate = proxy.convert(position, from: .local) {
                            withAnimation {
                                pinCoordinate = coordinate
                            }
                        }
                    }
                }

                // Instruction overlay
                VStack {
                    Text("Tap to place pin")
                        .font(SonderTypography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(SonderColors.inkDark)
                        .padding(.horizontal, SonderSpacing.md)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.cream.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.top, 60)

                    Spacer()
                }
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedCoordinate = pinCoordinate
                        dismiss()
                    }
                    .disabled(pinCoordinate == nil)
                }
            }
        }
    }
}

#Preview {
    CreateCustomPlaceView { place in
        logger.debug("Created place: \(place.name)")
    }
}
