//
//  RatePlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "RatePlaceView")

/// Complete log creation screen: rate, add photos, note, tags, trip, date.
struct RatePlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(PhotoSuggestionService.self) private var photoSuggestionService

    let place: Place
    let onLogComplete: (CLLocationCoordinate2D) -> Void

    // Core fields
    @State private var selectedRating: Rating?
    @State private var selectedTrip: Trip?
    @State private var visitedAt = Date()
    @State private var note = ""
    @State private var tags: [String] = []

    // Photos
    @State private var photos: [EditPhoto] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var suggestionsLoaded = false

    // UI state
    @State private var showConfirmation = false
    @State private var showNewTripSheet = false
    @State private var newTripName = ""
    @State private var newTripCoverImage: UIImage?
    @State private var isSaving = false
    @State private var coverNudgeTrip: Trip?
    @State private var showCoverImagePicker = false
    @State private var tripSaveError: String?
    @State private var showPlaceDetails = false
    @FocusState private var isNoteFocused: Bool

    // Data
    @State private var userTrips: [Trip] = []
    @State private var userLogs: [Log] = []
    @State private var allPlaces: [Place] = []
    @State private var cachedAvailableTrips: [Trip] = []
    @State private var cachedRecentTags: [String] = []

    private let maxPhotos = 5
    private let maxNoteLength = 280

    private var availableTrips: [Trip] { cachedAvailableTrips }
    private var recentTagSuggestions: [String] { cachedRecentTags }

    private func refreshData() {
        guard let userID = authService.currentUser?.id else { return }
        let logDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        userLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        let tripDescriptor = FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allTrips = (try? modelContext.fetch(tripDescriptor)) ?? []
        userTrips = allTrips.filter { $0.isAccessible(by: userID) }

        let placeDescriptor = FetchDescriptor<Place>()
        allPlaces = (try? modelContext.fetch(placeDescriptor)) ?? []

        // Cache sorted available trips
        let latestLogByTrip: [String: Date] = userLogs.reduce(into: [:]) { map, log in
            guard let tripID = log.tripID else { return }
            if let existing = map[tripID] {
                if log.createdAt > existing { map[tripID] = log.createdAt }
            } else {
                map[tripID] = log.createdAt
            }
        }
        cachedAvailableTrips = userTrips.sorted { a, b in
            let aDate = latestLogByTrip[a.id] ?? a.createdAt
            let bDate = latestLogByTrip[b.id] ?? b.createdAt
            return aDate > bDate
        }

        // Cache recent tag suggestions
        cachedRecentTags = recentTagsByUsage(logs: userLogs, userID: userID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Place header
                placeHeader
                    .padding(SonderSpacing.md)

                sectionDivider

                // Rating section
                VStack(spacing: SonderSpacing.lg) {
                    Text("How was it?")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)
                        .padding(.top, SonderSpacing.lg)

                    // Rating circles
                    HStack(spacing: SonderSpacing.md) {
                        ForEach(Rating.allCases, id: \.self) { rating in
                            ratingCircle(rating)
                        }
                    }
                    .padding(.horizontal, SonderSpacing.md)
                }

                sectionDivider
                    .padding(.top, SonderSpacing.lg)

                // Photos section
                photoSection
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.top, SonderSpacing.lg)

                sectionDivider
                    .padding(.top, SonderSpacing.lg)

                // Note section
                noteSection
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.top, SonderSpacing.lg)

                sectionDivider
                    .padding(.top, SonderSpacing.lg)

                // Tags section
                tagSection
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.top, SonderSpacing.lg)

                sectionDivider
                    .padding(.top, SonderSpacing.lg)

                // Trip section
                tripSection
                    .padding(.top, SonderSpacing.lg)

                // When
                dateSection
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.top, SonderSpacing.lg)
                    .padding(.bottom, SonderSpacing.lg)
            }
            .padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            // Save button
            Button(action: save) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save")
                            .font(SonderTypography.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(SonderSpacing.md)
                .background(selectedRating != nil ? SonderColors.terracotta : SonderColors.inkLight)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }
            .disabled(selectedRating == nil || isSaving)
            .padding(SonderSpacing.md)
            .background(SonderColors.cream)
        }
        .background(SonderColors.cream)
        .navigationTitle("Log Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showConfirmation ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(SonderColors.inkMuted)
            }
        }
        .task { refreshData() }
        .task {
            // Eagerly load photo suggestions
            await photoSuggestionService.requestAuthorizationIfNeeded()
            if photoSuggestionService.authorizationLevel == .full ||
               photoSuggestionService.authorizationLevel == .limited {
                photoSuggestionService.onLibraryChange = { [weak photoSuggestionService] in
                    guard let service = photoSuggestionService else { return }
                    await service.fetchSuggestions(near: place.coordinate)
                }
                photoSuggestionService.startObservingLibrary()
                await fetchPhotoSuggestions()
            }
        }
        .onChange(of: selectedTrip?.id) { _, _ in
            Task { await fetchPhotoSuggestions() }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    guard photos.count < maxPhotos else { break }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photos.append(EditPhoto(source: .local(display: image, original: image)))
                    }
                }
                selectedPhotoItems = []
            }
        }
        .onDisappear {
            photoSuggestionService.stopObservingLibrary()
            photoSuggestionService.onLibraryChange = nil
            photoSuggestionService.clearSuggestions()
        }
        .overlay {
            if showConfirmation {
                LogConfirmationView(
                    onDismiss: {
                        showConfirmation = false
                        onLogComplete(place.coordinate)
                    },
                    tripName: coverNudgeTrip?.name,
                    onAddCover: {
                        showConfirmation = false
                        showCoverImagePicker = true
                    },
                    placeName: place.name,
                    ratingEmoji: selectedRating?.emoji
                )
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showNewTripSheet) {
            newTripSheet
        }
        .sheet(isPresented: $showCoverImagePicker) {
            EditableImagePicker { image in
                showCoverImagePicker = false
                if let trip = coverNudgeTrip, let userId = authService.currentUser?.id {
                    let tripID = trip.id
                    let engine = syncEngine
                    Task {
                        if let url = await photoService.uploadPhoto(image, for: userId) {
                            engine.updateTripCoverPhoto(tripID: tripID, url: url)
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
        .sheet(isPresented: $showPlaceDetails) {
            NavigationStack {
                if let cachedDetails = buildPlaceDetails() {
                    PlacePreviewView(details: cachedDetails) {
                        showPlaceDetails = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showPlaceDetails = false }
                                .foregroundStyle(SonderColors.inkMuted)
                        }
                    }
                }
            }
        }
        .alert("Couldn't Save Trip", isPresented: Binding(
            get: { tripSaveError != nil },
            set: { if !$0 { tripSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { tripSaveError = nil }
        } message: {
            Text(tripSaveError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Place Header

    private var sectionDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGray)
            .frame(height: 1)
    }

    private var placeHeader: some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.terracotta)

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(2)

                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                showPlaceDetails = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(SonderColors.inkMuted)
            }
        }
    }

    // MARK: - Rating Circle

    private func ratingCircle(_ rating: Rating) -> some View {
        let isSelected = selectedRating == rating
        let color = SonderColors.pinColor(for: rating)

        return Button {
            SonderHaptics.impact(.medium)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedRating = rating
            }
        } label: {
            VStack(spacing: SonderSpacing.xs) {
                Text(rating.emoji)
                    .font(.system(size: 32))
                    .frame(width: 62, height: 62)
                    .background(isSelected ? color.opacity(0.2) : SonderColors.warmGray)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? color : .clear, lineWidth: 2)
                    )
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedRating)

                Text(rating.displayName)
                    .font(SonderTypography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack {
                Text("PHOTOS")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SonderColors.inkMuted)
                    .tracking(0.5)

                Spacer()

                Text("\(photos.count)/\(maxPhotos)")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkLight)
            }

            // Photo suggestions (eagerly loaded)
            PhotoSuggestionsRow(
                thumbnailSize: 80,
                canAddMore: photos.count < maxPhotos,
                showEmptyState: suggestionsLoaded
            ) { image in
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                    photos.append(EditPhoto(source: .local(display: image, original: image)))
                }
            }

            if photos.isEmpty {
                // Empty state: dashed-border add button
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: maxPhotos,
                    matching: .images
                ) {
                    AddPhotosEmptyState(height: 80)
                }
            } else {
                // Thumbnail strip with X buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SonderSpacing.xs) {
                        ForEach(photos) { photo in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    switch photo.source {
                                    case .remote(let urlString):
                                        if let url = URL(string: urlString) {
                                            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 160, height: 160)) {
                                                Color(SonderColors.warmGray)
                                            }
                                        }
                                    case .local(let display, _):
                                        Image(uiImage: display)
                                            .resizable()
                                            .scaledToFill()
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                                Button {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                                        photos.removeAll { $0.id == photo.id }
                                    }
                                    SonderHaptics.impact(.light)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                                .padding(2)
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.3).combined(with: .opacity)
                            ))
                        }

                        if photos.count < maxPhotos {
                            PhotosPicker(
                                selection: $selectedPhotoItems,
                                maxSelectionCount: maxPhotos - photos.count,
                                matching: .images
                            ) {
                                AddMorePhotosButton(size: 80)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("NOTE")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SonderColors.inkMuted)
                    .tracking(0.5)

                Spacer()

                Text("\(note.count)/\(maxNoteLength)")
                    .font(SonderTypography.caption)
                    .foregroundStyle(note.count > maxNoteLength ? .red : SonderColors.inkLight)
                    .opacity(isNoteFocused ? 1 : 0)
            }

            TextField("What caught your eye?", text: $note, axis: .vertical)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(3...6)
                .padding(SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .focused($isNoteFocused)
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
            Text("TAGS")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SonderColors.inkMuted)
                .tracking(0.5)

            TagInputView(
                selectedTags: $tags,
                recentTags: recentTagSuggestions
            )
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(SonderColors.inkMuted)

            DatePicker("", selection: $visitedAt)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(SonderColors.terracotta)
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Add to a trip?")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)
                .padding(.horizontal, SonderSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    // Most recently used trips
                    ForEach(availableTrips.prefix(3), id: \.id) { trip in
                        tripChip(trip)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // New trip button
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
                        .foregroundStyle(SonderColors.inkDark)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SonderSpacing.md)
            }

            // Selected trip indicator
            if let trip = selectedTrip {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SonderColors.terracotta)
                    Text("Saving to \(trip.name)")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .padding(.horizontal, SonderSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userTrips.count)
        .animation(.easeInOut(duration: 0.25), value: selectedTrip?.id)
    }

    private func tripChip(_ trip: Trip) -> some View {
        let isSelected = selectedTrip?.id == trip.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTrip = isSelected ? nil : trip
            }
            SonderHaptics.impact(.light)
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
            .foregroundStyle(isSelected ? .white : SonderColors.inkDark)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Trip Sheet

    @ViewBuilder
    private var newTripSheet: some View {
        NewTripSheetView(
            tripName: $newTripName,
            coverImage: $newTripCoverImage,
            onCancel: { showNewTripSheet = false },
            onCreate: {
                createNewTrip()
                showNewTripSheet = false
            }
        )
    }

    // MARK: - Trip Creation

    private func createNewTrip() {
        guard let userId = authService.currentUser?.id else { return }
        let trimmedName = newTripName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let trip = Trip(
            name: trimmedName,
            createdBy: userId
        )

        modelContext.insert(trip)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(trip)
            tripSaveError = error.localizedDescription
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTrip = trip
        }
        SonderHaptics.impact(.light)

        // Upload user-picked cover photo in background
        if let coverImage = newTripCoverImage {
            let tripID = trip.id
            let engine = syncEngine
            Task {
                if let url = await photoService.uploadPhoto(coverImage, for: userId) {
                    engine.updateTripCoverPhoto(tripID: tripID, url: url)
                }
            }
        }
    }

    // MARK: - Photo Suggestions

    private func fetchPhotoSuggestions() async {
        var tripContext: PhotoSuggestionService.TripContext?
        if let trip = selectedTrip {
            let tripID = trip.id
            let tripLogs = userLogs.filter { $0.tripID == tripID }
            let logPlaceIDs = tripLogs.map(\.placeID)
            let logCoords: [CLLocationCoordinate2D] = allPlaces
                .filter { logPlaceIDs.contains($0.id) }
                .map(\.coordinate)
            tripContext = .init(logCoordinates: logCoords)
        }
        await photoSuggestionService.fetchSuggestions(
            near: place.coordinate,
            tripContext: tripContext
        )
        suggestionsLoaded = true
    }

    // MARK: - Place Details Helper

    private func buildPlaceDetails() -> PlaceDetails? {
        PlaceDetails(
            placeId: place.id,
            name: place.name,
            formattedAddress: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            types: place.types,
            photoReference: place.photoReference,
            rating: nil,
            userRatingCount: nil,
            priceLevel: nil,
            editorialSummary: nil
        )
    }

    // MARK: - Save

    private func save() {
        guard let rating = selectedRating,
              let userId = authService.currentUser?.id else { return }

        isSaving = true

        let logID = UUID().uuidString.lowercased()

        // Queue photos for background upload, get placeholder URLs immediately
        var photoURLs: [String] = []
        let localImages = photos.compactMap { photo -> UIImage? in
            switch photo.source {
            case .local(_, let original): return original
            case .remote: return nil
            }
        }
        if !localImages.isEmpty {
            let engine = syncEngine
            photoURLs = photoService.queueBatchUpload(
                images: localImages,
                for: userId,
                logID: logID
            ) { results in
                engine.replacePendingPhotoURLs(logID: logID, uploadResults: results)
            }
        }

        // Strip whitespace before persisting
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = tags.compactMap { tag -> String? in
            let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        let log = Log(
            id: logID,
            userID: userId,
            placeID: place.id,
            rating: rating,
            photoURLs: photoURLs,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            tags: trimmedTags,
            tripID: selectedTrip?.id,
            visitedAt: visitedAt,
            syncStatus: .pending
        )

        modelContext.insert(log)

        do {
            try modelContext.save()

            SonderHaptics.notification(.success)

            Task {
                // Remove from Want to Go if bookmarked
                await wantToGoService.removeBookmarkIfLoggedPlace(placeID: place.id, userID: userId)
                if localImages.isEmpty {
                    await syncEngine.syncNow()
                }
            }

            // Show cover nudge if trip has no cover and user didn't add photos
            if let trip = selectedTrip, photos.isEmpty {
                let tripHasNoCover = trip.coverPhotoURL == nil
                if tripHasNoCover {
                    coverNudgeTrip = trip
                }
            }

            showConfirmation = true
        } catch {
            logger.error("Failed to save log: \(error.localizedDescription)")
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        RatePlaceView(
            place: Place(
                id: "test_place_id",
                name: "Blue Bottle Coffee",
                address: "123 Main St, San Francisco, CA",
                latitude: 37.7749,
                longitude: -122.4194
            )
        ) { _ in
            logger.debug("Log complete")
        }
    }
}
