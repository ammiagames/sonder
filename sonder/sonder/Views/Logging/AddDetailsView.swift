//
//  AddDetailsView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData

/// Screen 3: Add optional details (photo, note, tags, trip)
struct AddDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(WantToGoService.self) private var wantToGoService

    let place: Place
    let rating: Rating
    var initialTrip: Trip? = nil
    let onLogComplete: () -> Void

    @State private var note = ""
    @State private var tags: [String] = []
    @State private var selectedTrip: Trip?
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showConfirmation = false
    @State private var isSaving = false
    @State private var showNewTripAlert = false
    @State private var newTripName = ""
    @State private var showAllTrips = false

    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]

    private let maxNoteLength = 280

    /// Trips the user can add logs to (owned + collaborating),
    /// sorted by most recently used (latest log added), then by creation date.
    private var availableTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        let accessible = allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
        let latestLogByTrip: [String: Date] = allLogs.reduce(into: [:]) { map, log in
            guard let tripID = log.tripID else { return }
            if map[tripID] == nil || log.createdAt > map[tripID]! {
                map[tripID] = log.createdAt
            }
        }
        return accessible.sorted { a, b in
            let aDate = latestLogByTrip[a.id] ?? a.createdAt
            let bDate = latestLogByTrip[b.id] ?? b.createdAt
            return aDate > bDate
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
        .toolbar(showImagePicker ? .hidden : .automatic, for: .tabBar)
        .fullScreenCover(isPresented: $showConfirmation) {
            LogConfirmationView {
                showConfirmation = false
                onLogComplete()
            }
        }
        .onAppear {
            if selectedTrip == nil, let initialTrip {
                selectedTrip = initialTrip
            }
        }
        .sheet(isPresented: $showImagePicker) {
            EditableImagePicker { image in
                selectedImage = image
                showImagePicker = false
            } onCancel: {
                showImagePicker = false
            }
            .ignoresSafeArea()
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

            if let image = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        .onTapGesture { showImagePicker = true }

                    Button {
                        selectedImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .padding(SonderSpacing.xs)
                }
            } else {
                Button { showImagePicker = true } label: {
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
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Trip")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(availableTrips.prefix(3), id: \.id) { trip in
                        tripChip(trip)
                    }

                    if availableTrips.count > 3 {
                        Button {
                            showAllTrips = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("More")
                                    .font(SonderTypography.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, SonderSpacing.sm)
                            .padding(.vertical, SonderSpacing.xs)
                            .background(SonderColors.warmGray)
                            .foregroundColor(SonderColors.inkMuted)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(SonderColors.inkLight.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        newTripName = ""
                        showNewTripAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("New Trip")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.warmGray)
                        .foregroundColor(SonderColors.inkDark)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let trip = selectedTrip {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(SonderColors.terracotta)
                    Text("Saving to \(trip.name)")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTrip?.id)
        .sheet(isPresented: $showAllTrips) {
            allTripsSheet
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

    private func tripChip(_ trip: Trip) -> some View {
        let isSelected = selectedTrip?.id == trip.id

        return HStack(spacing: 4) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 10))
            Text(trip.name)
                .font(SonderTypography.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(isSelected ? SonderColors.terracotta : SonderColors.warmGray)
        .foregroundColor(isSelected ? .white : SonderColors.inkDark)
        .clipShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTrip = isSelected ? nil : trip
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @ViewBuilder
    private var allTripsSheet: some View {
        AllTripsPickerSheet(
            trips: availableTrips,
            selectedTrip: $selectedTrip,
            isPresented: $showAllTrips
        )
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

                // Remove from Want to Go if bookmarked
                await wantToGoService.removeBookmarkIfLoggedPlace(placeID: place.id, userID: userId)

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

// MARK: - All Trips Picker Sheet

struct AllTripsPickerSheet: View {
    let trips: [Trip]
    @Binding var selectedTrip: Trip?
    @Binding var isPresented: Bool
    @State private var searchText = ""

    private var filteredTrips: [Trip] {
        if searchText.isEmpty { return trips }
        return trips.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedTrip = nil
                    isPresented = false
                } label: {
                    HStack {
                        Text("None")
                            .foregroundColor(SonderColors.inkDark)
                        Spacer()
                        if selectedTrip == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(SonderColors.terracotta)
                        }
                    }
                }

                ForEach(filteredTrips, id: \.id) { trip in
                    Button {
                        selectedTrip = trip
                        isPresented = false
                    } label: {
                        HStack {
                            Text(trip.name)
                                .foregroundColor(SonderColors.inkDark)
                            Spacer()
                            if selectedTrip?.id == trip.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(SonderColors.terracotta)
                            }
                        }
                    }
                }
            }
            .navigationTitle("All Trips")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search trips")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
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
