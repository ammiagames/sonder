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

    @Query private var trips: [Trip]

    private let maxNoteLength = 280

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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
            .padding()
        }
        .overlay(alignment: .bottom) {
            saveButton
                .padding(.bottom, 20)
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
        HStack(spacing: 12) {
            // Rating emoji
            Text(rating.emoji)
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(rating.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            .padding(8)
                        }
                } else {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                        Text("Add Photo")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(Color(.systemGray6))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(note.count)/\(maxNoteLength)")
                    .font(.caption)
                    .foregroundColor(note.count > maxNoteLength ? .red : .secondary)
            }

            TextEditor(text: $note)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: note) { _, newValue in
                    if newValue.count > maxNoteLength {
                        note = String(newValue.prefix(maxNoteLength))
                    }
                }
        }
    }

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            TagInputView(selectedTags: $tags)
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Menu {
                Button("None") {
                    selectedTrip = nil
                }

                ForEach(trips, id: \.id) { trip in
                    Button(trip.name) {
                        selectedTrip = trip
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
                        .foregroundColor(selectedTrip != nil ? .primary : .secondary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                    Text("Save")
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
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
