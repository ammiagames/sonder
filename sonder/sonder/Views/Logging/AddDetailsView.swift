//
//  AddDetailsView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Screen 3: Add optional details (photo, note, tags, trip)
struct AddDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine

    let place: Place
    let rating: Rating
    let onLogComplete: () -> Void

    @State private var note = ""
    @State private var tags: [String] = []
    @State private var selectedTrip: Trip?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showConfirmation = false
    @State private var isSaving = false
    @State private var showNewTripAlert = false
    @State private var newTripName = ""

    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]

    private let maxNoteLength = 280

    /// Trips the user can add logs to (owned + collaborating)
    private var availableTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.xl) {
                // Place header (condensed)
                placeHeader

                // Photo picker
                photoSection

                // Note input
                noteSection

                // Tags
                tagSection

                // Trip selector
                tripSection
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) {
            saveButton
                .padding(.bottom, SonderSpacing.lg)
        }
        .navigationTitle("Add Details")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showConfirmation) {
            LogConfirmationView {
                showConfirmation = false
                onLogComplete()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }

    // MARK: - Place Header

    private var placeHeader: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Rating emoji
            Text(rating.emoji)
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                Text(rating.displayName)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }

            Spacer()
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Photo")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                selectedImage = nil
                                selectedPhotoItem = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .padding(SonderSpacing.xs)
                        }
                } else {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                        Text("Add Photo")
                            .font(SonderTypography.body)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(SonderColors.warmGray)
                    .foregroundColor(SonderColors.inkMuted)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }
            }
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("Note")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(note.count)/\(maxNoteLength)")
                    .font(SonderTypography.caption)
                    .foregroundColor(note.count > maxNoteLength ? .red : SonderColors.inkLight)
            }

            TextEditor(text: $note)
                .font(SonderTypography.body)
                .frame(minHeight: 100)
                .padding(SonderSpacing.xs)
                .scrollContentBackground(.hidden)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .onChange(of: note) { _, newValue in
                    if newValue.count > maxNoteLength {
                        note = String(newValue.prefix(maxNoteLength))
                    }
                }
        }
    }

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Tags")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TagInputView(selectedTags: $tags)
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Trip")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                Button("None") {
                    selectedTrip = nil
                }

                if !availableTrips.isEmpty {
                    ForEach(availableTrips, id: \.id) { trip in
                        Button(trip.name) {
                            selectedTrip = trip
                        }
                    }
                }

                Divider()

                Button {
                    newTripName = ""
                    showNewTripAlert = true
                } label: {
                    Label("Create New Trip", systemImage: "plus")
                }
            } label: {
                HStack {
                    Text(selectedTrip?.name ?? "Select a trip")
                        .font(SonderTypography.body)
                        .foregroundColor(selectedTrip != nil ? SonderColors.inkDark : SonderColors.inkMuted)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .foregroundColor(SonderColors.inkLight)
                }
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }
        }
        .alert("New Trip", isPresented: $showNewTripAlert) {
            TextField("Trip name", text: $newTripName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                createNewTrip()
            }
            .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for your trip")
        }
    }

    private func createNewTrip() {
        guard let userId = authService.currentUser?.id else { return }
        let trimmedName = newTripName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let trip = Trip(
            name: trimmedName,
            createdBy: userId
        )

        modelContext.insert(trip)
        try? modelContext.save()

        selectedTrip = trip
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: SonderSpacing.xs) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                    Text("Save")
                        .font(SonderTypography.headline)
                }
            }
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.vertical, SonderSpacing.sm)
            .background(SonderColors.terracotta)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(isSaving)
    }

    // MARK: - Actions

    private func save() {
        guard let userId = authService.currentUser?.id else { return }

        isSaving = true

        Task {
            // Upload photo if selected
            var photoURL: String?
            if let image = selectedImage {
                photoURL = await photoService.uploadPhoto(image, for: userId)
                print("Photo upload result: \(photoURL ?? "nil")")
            }

            // Create log
            let log = Log(
                userID: userId,
                placeID: place.id,
                rating: rating,
                photoURL: photoURL,
                note: note.isEmpty ? nil : note,
                tags: tags,
                tripID: selectedTrip?.id,
                syncStatus: .pending
            )

            modelContext.insert(log)

            do {
                try modelContext.save()

                // Haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)

                // Trigger immediate sync
                await syncEngine.syncNow()

                await MainActor.run {
                    showConfirmation = true
                }
            } catch {
                print("Failed to save log: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddDetailsView(
            place: Place(
                id: "test_place_id",
                name: "Blue Bottle Coffee",
                address: "123 Main St, San Francisco, CA",
                latitude: 37.7749,
                longitude: -122.4194
            ),
            rating: .solid
        ) {
            print("Log complete")
        }
    }
}
