//
//  AddDetailsView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import Photos

private struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Screen 3: Add optional details (photo, note, tags, trip)
struct AddDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(PhotoSuggestionService.self) private var photoSuggestionService

    let place: Place
    let rating: Rating
    var initialTrip: Trip? = nil
    var initialVisitedAt: Date = Date()
    let onLogComplete: (CLLocationCoordinate2D) -> Void

    @State private var note = ""
    @State private var tags: [String] = []
    @State private var selectedTrip: Trip?
    @State private var visitedAt = Date()
    @State private var selectedImages: [IdentifiedImage] = []
    @State private var showImagePicker = false
    @State private var showConfirmation = false
    @State private var showNewTripSheet = false
    @State private var newTripName = ""
    @State private var newTripCoverImage: UIImage?
    @State private var showAllTrips = false
    @State private var tripWasCreatedThisSession = false
    @State private var coverNudgeTrip: Trip?
    @State private var showCoverImagePicker = false
    @State private var suggestionThumbnails: [String: UIImage] = [:] // asset localIdentifier -> thumbnail
    @State private var loadingSuggestion: String? = nil

    private let maxPhotos = 5

    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
    @Query private var allPlaces: [Place]

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
            if let existing = map[tripID] {
                if log.createdAt > existing { map[tripID] = log.createdAt }
            } else {
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

                // When
                dateSection
            }
            .padding(SonderSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
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
            LogConfirmationView(
                onDismiss: {
                    showConfirmation = false
                    onLogComplete(place.coordinate)
                },
                tripName: coverNudgeTrip?.name,
                onAddCover: {
                    showConfirmation = false
                    showCoverImagePicker = true
                }
            )
        }
        .sheet(isPresented: $showCoverImagePicker) {
            EditableImagePicker { image in
                showCoverImagePicker = false
                if let trip = coverNudgeTrip, let userId = authService.currentUser?.id {
                    Task {
                        if let url = await photoService.uploadPhoto(image, for: userId) {
                            trip.coverPhotoURL = url
                            trip.updatedAt = Date()
                            trip.syncStatus = .pending
                            try? modelContext.save()
                        }
                    }
                }
                coverNudgeTrip = nil
                onLogComplete(place.coordinate)
            } onCancel: {
                showCoverImagePicker = false
                coverNudgeTrip = nil
                onLogComplete(place.coordinate)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if selectedTrip == nil, let initialTrip {
                selectedTrip = initialTrip
            }
            visitedAt = initialVisitedAt
        }
        .task {
            await photoSuggestionService.requestAuthorizationIfNeeded()
            await fetchPhotoSuggestions()
        }
        .onChange(of: selectedTrip?.id) { _, _ in
            Task { await fetchPhotoSuggestions() }
        }
        .onDisappear {
            photoSuggestionService.clearSuggestions()
        }
        .sheet(isPresented: $showImagePicker) {
            EditableImagePicker { image in
                if selectedImages.count < maxPhotos {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        selectedImages.append(IdentifiedImage(image: image))
                    }
                }
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
            HStack {
                Text("Photos")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(selectedImages.count)/\(maxPhotos)")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
            }

            photoSuggestionsRow

            if selectedImages.isEmpty {
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
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SonderSpacing.xs) {
                        ForEach(selectedImages) { item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                                Button {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                        selectedImages.removeAll { $0.id == item.id }
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                }
                                .padding(2)
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.3).combined(with: .opacity)
                            ))
                        }

                        if selectedImages.count < maxPhotos {
                            Button { showImagePicker = true } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .medium))
                                }
                                .frame(width: 80, height: 80)
                                .background(SonderColors.warmGray)
                                .foregroundColor(SonderColors.inkMuted)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo Suggestions

    @ViewBuilder
    private var photoSuggestionsRow: some View {
        let suggestions = photoSuggestionService.suggestions
        if !suggestions.isEmpty && selectedImages.count < maxPhotos {
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(SonderColors.terracotta)
                    Text("Nearby photos")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SonderSpacing.xs) {
                        ForEach(suggestions, id: \.localIdentifier) { asset in
                            Button {
                                addSuggestion(asset)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Group {
                                        if let thumb = suggestionThumbnails[asset.localIdentifier] {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Rectangle()
                                                .fill(SonderColors.warmGray)
                                        }
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

                                    if loadingSuggestion == asset.localIdentifier {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(width: 100, height: 100)
                                            .background(.black.opacity(0.3))
                                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white, SonderColors.terracotta)
                                            .shadow(radius: 2)
                                            .padding(4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingSuggestion != nil)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                            .task {
                                guard suggestionThumbnails[asset.localIdentifier] == nil else { return }
                                if let thumb = await photoSuggestionService.loadThumbnail(for: asset) {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        suggestionThumbnails[asset.localIdentifier] = thumb
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchPhotoSuggestions() async {
        var tripContext: PhotoSuggestionService.TripContext?
        if let trip = selectedTrip {
            let tripID = trip.id
            let tripLogs = allLogs.filter { $0.tripID == tripID }
            let logPlaceIDs = tripLogs.map(\.placeID)
            // Look up coordinates for places in this trip
            let logCoords: [CLLocationCoordinate2D] = allPlaces
                .filter { logPlaceIDs.contains($0.id) }
                .map(\.coordinate)
            tripContext = .init(
                startDate: trip.startDate,
                endDate: trip.endDate,
                logCoordinates: logCoords
            )
        }
        await photoSuggestionService.fetchSuggestions(
            near: place.coordinate,
            visitedAt: visitedAt,
            tripContext: tripContext
        )
    }

    private func addSuggestion(_ asset: PHAsset) {
        guard selectedImages.count < maxPhotos, loadingSuggestion == nil else { return }
        loadingSuggestion = asset.localIdentifier

        Task {
            if let image = await photoSuggestionService.loadFullImage(for: asset) {
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                    if selectedImages.count < maxPhotos {
                        selectedImages.append(IdentifiedImage(image: image))
                    }
                    // Remove this asset from suggestions
                    photoSuggestionService.suggestions.removeAll { $0.localIdentifier == asset.localIdentifier }
                    suggestionThumbnails.removeValue(forKey: asset.localIdentifier)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            loadingSuggestion = nil
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

    // MARK: - Date Section

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("When")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            DatePicker("", selection: $visitedAt)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(SonderColors.terracotta)
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
                        newTripCoverImage = nil
                        showNewTripSheet = true
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
        .sheet(isPresented: $showNewTripSheet) {
            newTripSheet
        }
    }

    private func tripChip(_ trip: Trip) -> some View {
        let isSelected = selectedTrip?.id == trip.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTrip = isSelected ? nil : trip
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 4) {
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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var allTripsSheet: some View {
        AllTripsPickerSheet(
            trips: availableTrips,
            selectedTrip: $selectedTrip,
            isPresented: $showAllTrips
        )
    }

    @ViewBuilder
    private var newTripSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SonderSpacing.md) {
                TextField("Trip name", text: $newTripName)
                    .font(SonderTypography.body)
                    .padding(SonderSpacing.sm)
                    .background(SonderColors.warmGray)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

                if !selectedImages.isEmpty {
                    VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                        Text("Tap a photo to use as the trip cover")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SonderSpacing.xs) {
                                ForEach(selectedImages) { item in
                                    let isSelected = newTripCoverImage === item.image
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            newTripCoverImage = isSelected ? nil : item.image
                                        }
                                    } label: {
                                        Image(uiImage: item.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                                                    .strokeBorder(SonderColors.terracotta, lineWidth: isSelected ? 3 : 0)
                                            )
                                            .overlay(alignment: .bottomTrailing) {
                                                if isSelected {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 16))
                                                        .foregroundColor(SonderColors.terracotta)
                                                        .background(Circle().fill(.white).padding(2))
                                                        .offset(x: 4, y: 4)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.cream)
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showNewTripSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createNewTrip()
                        showNewTripSheet = false
                    }
                    .fontWeight(.semibold)
                    .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .presentationDetents([.medium])
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

        // Use Google Places photo as immediate fallback if no user photo picked
        if newTripCoverImage == nil, let ref = place.photoReference,
           let url = GooglePlacesService.photoURL(for: ref) {
            trip.coverPhotoURL = url.absoluteString
        }

        modelContext.insert(trip)
        try? modelContext.save()

        selectedTrip = trip
        tripWasCreatedThisSession = true

        if let coverImage = newTripCoverImage {
            Task {
                if let url = await photoService.uploadPhoto(coverImage, for: userId) {
                    trip.coverPhotoURL = url
                    trip.updatedAt = Date()
                    trip.syncStatus = .pending
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        VStack(spacing: SonderSpacing.xxs) {
            Button(action: save) {
                HStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "checkmark")
                    Text("Save")
                        .font(SonderTypography.headline)
                }
                .padding(.horizontal, SonderSpacing.lg)
                .padding(.vertical, SonderSpacing.sm)
                .background(SonderColors.terracotta)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let userId = authService.currentUser?.id else { return }

        let logID = UUID().uuidString.lowercased()

        // Queue photos for background upload, get placeholder URLs immediately
        var photoURLs: [String] = []
        if !selectedImages.isEmpty {
            let context = modelContext
            let engine = syncEngine
            photoURLs = photoService.queueBatchUpload(
                images: selectedImages.map(\.image),
                for: userId,
                logID: logID
            ) { results in
                // Called when all uploads finish — replace placeholders with real URLs
                let idToFind = logID
                let descriptor = FetchDescriptor<Log>(
                    predicate: #Predicate { log in log.id == idToFind }
                )
                guard let log = try? context.fetch(descriptor).first else { return }

                log.photoURLs = log.photoURLs.compactMap { url in
                    if url.hasPrefix("pending-upload:") {
                        let placeholderID = String(url.dropFirst("pending-upload:".count))
                        return results[placeholderID] // nil (removed) if upload failed
                    }
                    return url
                }
                log.updatedAt = Date()
                try? context.save()

                Task { await engine.syncNow() }
            }
        }

        // Create log immediately with placeholder URLs
        let log = Log(
            id: logID,
            userID: userId,
            placeID: place.id,
            rating: rating,
            photoURLs: photoURLs,
            note: note.isEmpty ? nil : note,
            tags: tags,
            tripID: selectedTrip?.id,
            visitedAt: visitedAt,
            syncStatus: .pending
        )

        modelContext.insert(log)

        do {
            try modelContext.save()

            // Auto-assign first photo as trip cover if trip has none
            if let trip = selectedTrip, trip.coverPhotoURL == nil || isGooglePhotoURL(trip.coverPhotoURL) {
                if let firstImage = selectedImages.first?.image {
                    // Upload user photo as cover in background
                    let tripToUpdate = trip
                    Task {
                        if let url = await photoService.uploadPhoto(firstImage, for: userId) {
                            tripToUpdate.coverPhotoURL = url
                            tripToUpdate.updatedAt = Date()
                            tripToUpdate.syncStatus = .pending
                            try? modelContext.save()
                        }
                    }
                } else if trip.coverPhotoURL == nil, let ref = place.photoReference,
                          let url = GooglePlacesService.photoURL(for: ref) {
                    // No photos selected — use Google Places photo as fallback
                    trip.coverPhotoURL = url.absoluteString
                    trip.updatedAt = Date()
                    trip.syncStatus = .pending
                    try? modelContext.save()
                }
            }

            // Show nudge if trip was created this session and has no user-uploaded cover
            if tripWasCreatedThisSession, let trip = selectedTrip, selectedImages.isEmpty {
                coverNudgeTrip = trip
            }

            // Haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // If no photos, sync right away
            if selectedImages.isEmpty {
                Task { await syncEngine.syncNow() }
            }

            // Remove from Want to Go if bookmarked
            Task { await wantToGoService.removeBookmarkIfLoggedPlace(placeID: place.id, userID: userId) }

            showConfirmation = true
        } catch {
            print("Failed to save log: \(error)")
        }
    }

    /// Check if a URL is a Google Places photo URL (not a user-uploaded photo)
    private func isGooglePhotoURL(_ url: String?) -> Bool {
        guard let url else { return false }
        return url.contains("googleapis.com")
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
        ) { _ in
            print("Log complete")
        }
    }
}
