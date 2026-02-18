//
//  CreateEditTripView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData

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
    @Environment(SyncEngine.self) private var syncEngine

    @Query(sort: \Log.visitedAt, order: .reverse) private var allLogs: [Log]
    @Query private var allPlaces: [Place]
    @Query private var allTrips: [Trip]

    let mode: TripFormMode
    var onTripCreated: ((Trip) -> Void)?
    var onDelete: (() -> Void)?

    @State private var name = ""
    @State private var tripDescription = ""
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var coverPhotoURL: String?
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploadingPhoto = false
    @State private var isSaving = false
    @State private var showSavedToast = false
    @State private var showStartDatePicker = false
    @State private var showEndDatePicker = false
    @State private var showDeleteAlert = false
    @State private var selectedLogIDs: Set<String> = []
    @State private var showLogPicker = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingTrip: Trip? {
        if case .edit(let trip) = mode { return trip }
        return nil
    }

    private var orphanedLogs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        let tripIDs = Set(allTrips.map(\.id))
        return allLogs.filter { $0.userID == userID && ($0.hasNoTrip || !tripIDs.contains($0.tripID!)) }
    }

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: allPlaces.map { ($0.id, $0) })
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

                // Add Logs section
                if !orphanedLogs.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showLogPicker) {
                            HStack {
                                Spacer()
                                Button(selectedLogIDs.count == orphanedLogs.count ? "Deselect All" : "Select All") {
                                    if selectedLogIDs.count == orphanedLogs.count {
                                        selectedLogIDs.removeAll()
                                    } else {
                                        selectedLogIDs = Set(orphanedLogs.map(\.id))
                                        autoFillDatesIfNeeded()
                                    }
                                }
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(SonderColors.terracotta)
                            }

                            ForEach(orphanedLogs, id: \.id) { log in
                                if let place = placesByID[log.placeID] {
                                    logPickerRow(log: log, place: place)
                                }
                            }
                        } label: {
                            HStack(spacing: SonderSpacing.xs) {
                                Text("Add Logs")
                                if !selectedLogIDs.isEmpty {
                                    Text("\(selectedLogIDs.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                        .background(SonderColors.terracotta)
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
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
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.colorScheme, .light)
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
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(SonderColors.sage)
                        Text("Saved")
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.inkDark)
                    }
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.warmGray)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
                    .padding(.bottom, SonderSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSavedToast)
            .alert("Delete Trip", isPresented: $showDeleteAlert) {
                Button("Delete Trip & Logs", role: .destructive) {
                    deleteTrip(keepLogs: false)
                }
                Button("Delete Trip, Keep Logs") {
                    deleteTrip(keepLogs: true)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you also want to delete all logs in this trip?")
            }
            .onAppear {
                loadExistingData()
            }
            .sheet(isPresented: $showImagePicker) {
                EditableImagePicker { image in
                    selectedImage = image
                    showImagePicker = false
                    Task { await uploadSelectedImage(image) }
                } onCancel: {
                    showImagePicker = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Cover Photo Section

    private var coverPhotoSection: some View {
        VStack(spacing: 12) {
            // Photo preview — show local image first, then remote URL
            Group {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = coverPhotoURL,
                          let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 150)) {
                        coverPlaceholder
                    }
                    .id(urlString)
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
                Button {
                    showImagePicker = true
                } label: {
                    Label(
                        coverPhotoURL == nil && selectedImage == nil ? "Add Cover Photo" : "Change Photo",
                        systemImage: "photo"
                    )
                }
                .disabled(isUploadingPhoto)

                if coverPhotoURL != nil || selectedImage != nil {
                    Button(role: .destructive) {
                        selectedImage = nil
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
        TripCoverPlaceholderView(
            seedKey: coverPhotoURL ?? name,
            title: name.isEmpty ? "New Trip" : name,
            caption: "Add a cover photo"
        )
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

    private func uploadSelectedImage(_ image: UIImage) async {
        guard let userID = authService.currentUser?.id else { return }

        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        if let url = await photoService.uploadPhoto(image, for: userID) {
            coverPhotoURL = url
        }
    }

    private func saveTrip() {
        guard let userID = authService.currentUser?.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true

        Task {
            do {
                let trimmedDescription = tripDescription.trimmingCharacters(in: .whitespaces)

                let savedTrip: Trip

                if let trip = existingTrip {
                    // Update existing
                    trip.name = trimmedName
                    trip.tripDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
                    trip.startDate = startDate
                    trip.endDate = endDate
                    trip.coverPhotoURL = coverPhotoURL
                    try await tripService.updateTrip(trip)
                    savedTrip = trip
                } else {
                    // Create new
                    let newTrip = try await tripService.createTrip(
                        name: trimmedName,
                        description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                        startDate: startDate,
                        endDate: endDate,
                        coverPhotoURL: coverPhotoURL,
                        createdBy: userID
                    )
                    onTripCreated?(newTrip)
                    savedTrip = newTrip
                }

                // Assign selected logs to the trip
                if !selectedLogIDs.isEmpty {
                    try await tripService.associateLogs(ids: selectedLogIDs, with: savedTrip)
                }

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                if isEditing {
                    isSaving = false
                    showSavedToast = true
                    try? await Task.sleep(for: .seconds(1.0))
                    dismiss()
                } else {
                    dismiss()
                }
            } catch {
                print("Error saving trip: \(error)")
            }

            isSaving = false
        }
    }

    // MARK: - Log Picker

    private func logPickerRow(log: Log, place: Place) -> some View {
        let isSelected = selectedLogIDs.contains(log.id)

        return Button {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            if isSelected {
                selectedLogIDs.remove(log.id)
            } else {
                selectedLogIDs.insert(log.id)
                autoFillDatesIfNeeded()
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? SonderColors.terracotta : SonderColors.inkLight)

                logPickerPhoto(log: log, place: place)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(place.name)
                            .font(SonderTypography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(SonderColors.inkDark)
                            .lineLimit(1)

                        Spacer()

                        Text(log.rating.emoji)
                            .font(.system(size: 14))
                    }

                    Text(log.visitedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundColor(SonderColors.inkLight)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func logPickerPhoto(log: Log, place: Place) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) {
                logPickerPlacePhoto(place: place)
            }
        } else {
            logPickerPlacePhoto(place: place)
        }
    }

    @ViewBuilder
    private func logPickerPlacePhoto(place: Place) -> some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) {
                logPickerPhotoPlaceholder
            }
        } else {
            logPickerPhotoPlaceholder
        }
    }

    private var logPickerPhotoPlaceholder: some View {
        Rectangle()
            .fill(SonderColors.warmGrayDark)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundColor(SonderColors.inkLight)
            }
    }

    private func autoFillDatesIfNeeded() {
        guard startDate == nil && endDate == nil else { return }

        let selectedLogs = orphanedLogs.filter { selectedLogIDs.contains($0.id) }
        guard !selectedLogs.isEmpty else { return }

        let dates = selectedLogs.map(\.visitedAt)
        startDate = dates.min()
        endDate = dates.max()
    }

    private func deleteTrip(keepLogs: Bool) {
        guard let trip = existingTrip else { return }

        Task {
            do {
                if keepLogs {
                    try await tripService.deleteTrip(trip)
                } else {
                    try await tripService.deleteTripAndLogs(trip, syncEngine: syncEngine)
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                dismiss()
                onDelete?()
            } catch {
                print("Error deleting trip: \(error)")
            }
        }
    }
}

#Preview {
    CreateEditTripView(mode: .create)
}
