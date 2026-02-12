//
//  CreateEditTripView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import PhotosUI

enum TripFormMode {
    case create
    case edit(Trip)
}

/// Form for creating or editing a trip
struct CreateEditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(PhotoService.self) private var photoService

    let mode: TripFormMode

    @State private var name = ""
    @State private var tripDescription = ""
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var coverPhotoURL: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var isSaving = false
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false
    @State private var showDeleteAlert = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingTrip: Trip? {
        if case .edit(let trip) = mode { return trip }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Cover photo section
                Section {
                    coverPhotoSection
                }

                // Name section
                Section {
                    TextField("Trip Name", text: $name)
                } header: {
                    Text("Name")
                }

                // Description section
                Section {
                    TextField("What's this trip about?", text: $tripDescription, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description (Optional)")
                }

                // Date section
                Section {
                    // Start date
                    HStack {
                        Text("Start Date")
                        Spacer()
                        if let start = startDate {
                            Button(start.formatted(date: .abbreviated, time: .omitted)) {
                                showStartDatePicker.toggle()
                            }
                            .foregroundColor(.accentColor)

                            Button {
                                startDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button("Add") {
                                startDate = Date()
                                showStartDatePicker = true
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                    if showStartDatePicker, startDate != nil {
                        DatePicker(
                            "Start",
                            selection: Binding(
                                get: { startDate ?? Date() },
                                set: { startDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }

                    // End date
                    HStack {
                        Text("End Date")
                        Spacer()
                        if let end = endDate {
                            Button(end.formatted(date: .abbreviated, time: .omitted)) {
                                showEndDatePicker.toggle()
                            }
                            .foregroundColor(.accentColor)

                            Button {
                                endDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button("Add") {
                                endDate = Date()
                                showEndDatePicker = true
                            }
                            .foregroundColor(.accentColor)
                        }
                    }

                    if showEndDatePicker, endDate != nil {
                        DatePicker(
                            "End",
                            selection: Binding(
                                get: { endDate ?? Date() },
                                set: { endDate = $0 }
                            ),
                            in: (startDate ?? .distantPast)...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                } header: {
                    Text("Dates (Optional)")
                }

                // Delete section (edit mode only)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Trip")
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveTrip()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("Delete Trip", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTrip()
                }
            } message: {
                Text("Are you sure? This will remove all logs from this trip but won't delete the logs themselves.")
            }
            .onAppear {
                loadExistingData()
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    await uploadPhoto(from: newValue)
                }
            }
        }
    }

    // MARK: - Cover Photo Section

    private var coverPhotoSection: some View {
        VStack(spacing: 12) {
            // Photo preview
            Group {
                if let urlString = coverPhotoURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            coverPlaceholder
                        }
                    }
                    .id(urlString) // Force refresh when URL changes
                } else {
                    coverPlaceholder
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isUploadingPhoto {
                    Color.black.opacity(0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    ProgressView()
                        .tint(.white)
                }
            }

            // Photo buttons
            HStack {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(coverPhotoURL == nil ? "Add Cover Photo" : "Change Photo", systemImage: "photo")
                }
                .disabled(isUploadingPhoto)

                if coverPhotoURL != nil {
                    Button(role: .destructive) {
                        coverPhotoURL = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .disabled(isUploadingPhoto)
                }
            }
            .font(.subheadline)
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                    Text("Add a cover photo")
                        .font(SonderTypography.caption)
                }
                .foregroundColor(SonderColors.terracotta.opacity(0.6))
            }
    }

    // MARK: - Actions

    private func loadExistingData() {
        if let trip = existingTrip {
            name = trip.name
            tripDescription = trip.tripDescription ?? ""
            startDate = trip.startDate
            endDate = trip.endDate
            coverPhotoURL = trip.coverPhotoURL
        }
    }

    private func uploadPhoto(from item: PhotosPickerItem?) async {
        guard let item = item,
              let userID = authService.currentUser?.id else { return }

        isUploadingPhoto = true

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                if let url = await photoService.uploadPhoto(image, for: userID) {
                    coverPhotoURL = url
                }
            }
        } catch {
            print("Error uploading photo: \(error)")
        }

        isUploadingPhoto = false
        selectedPhotoItem = nil
    }

    private func saveTrip() {
        guard let userID = authService.currentUser?.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true

        Task {
            do {
                let trimmedDescription = tripDescription.trimmingCharacters(in: .whitespaces)

                if let trip = existingTrip {
                    // Update existing
                    trip.name = trimmedName
                    trip.tripDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
                    trip.startDate = startDate
                    trip.endDate = endDate
                    trip.coverPhotoURL = coverPhotoURL
                    try await tripService.updateTrip(trip)
                } else {
                    // Create new
                    _ = try await tripService.createTrip(
                        name: trimmedName,
                        description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                        startDate: startDate,
                        endDate: endDate,
                        coverPhotoURL: coverPhotoURL,
                        createdBy: userID
                    )
                }

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                dismiss()
            } catch {
                print("Error saving trip: \(error)")
            }

            isSaving = false
        }
    }

    private func deleteTrip() {
        guard let trip = existingTrip else { return }

        Task {
            do {
                try await tripService.deleteTrip(trip)

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                dismiss()
            } catch {
                print("Error deleting trip: \(error)")
            }
        }
    }
}

#Preview {
    CreateEditTripView(mode: .create)
}
