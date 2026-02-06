//
//  CreateCustomPlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData
import MapKit

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
            Form {
                // Name section
                Section {
                    TextField("Place name", text: $placeName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Required")
                }

                // Address section
                Section {
                    TextField("Address (optional)", text: $placeAddress)
                } header: {
                    Text("Address")
                }

                // Location section
                Section {
                    if let coordinate = selectedCoordinate {
                        // Show selected location
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text("Location set")
                                    .font(.subheadline)
                                Text("\(coordinate.latitude, specifier: "%.4f"), \(coordinate.longitude, specifier: "%.4f")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Change") {
                                showMap = true
                            }
                            .font(.subheadline)
                        }
                    } else {
                        // Options to set location
                        Button {
                            useCurrentLocation()
                        } label: {
                            Label("Use Current Location", systemImage: "location.fill")
                        }

                        Button {
                            showMap = true
                        } label: {
                            Label("Choose on Map", systemImage: "map")
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if selectedCoordinate == nil {
                        Text("Required - helps show this place on the map")
                    }
                }
            }
            .navigationTitle("Add Your Own Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createPlace()
                    }
                    .disabled(!isValid)
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
                                    .foregroundColor(.red)
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
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
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
        print("Created place: \(place.name)")
    }
}
