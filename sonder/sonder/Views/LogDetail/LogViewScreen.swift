//
//  LogViewScreen.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "LogViewScreen")

/// Magazine-spread view for the current user's log with seamless view/edit toggle.
struct LogViewScreen: View {
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(PhotoService.self) private var photoService
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoSuggestionService.self) private var photoSuggestionService

    let log: Log
    let place: Place
    var onDelete: (() -> Void)?

    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]

    // MARK: - View-mode state

    @State private var photoPageIndex = 0
    @State private var selectedPlaceDetails: PlaceDetails?
    @State private var isLoadingDetails = false
    @State private var placeToLog: Place?
    @State private var contentAppeared = false
    @State private var showShareLog = false
    @State private var showFullscreenPhoto = false
    @State private var fullscreenPhotoIndex = 0

    // MARK: - Edit-mode toggle

    @State private var isEditing = false
    @State private var editModeInitialized = false

    // MARK: - Edit-mode copies (snapshotted when entering edit mode)

    @State private var editRating: Rating = .okay
    @State private var editNote: String = ""
    @State private var editTags: [String] = []
    @State private var editSelectedTripID: String?
    @State private var editVisitedAt: Date = Date()
    @State private var editSelectedImages: [UIImage] = []
    @State private var editOriginalImages: [UIImage] = []  // originals for re-cropping
    @State private var editCurrentPhotoURLs: [String] = []

    // MARK: - Edit UI state

    @State private var showDeleteAlert = false
    @State private var showDiscardAlert = false
    @State private var hasChanges = false
    @State private var showSavedToast = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var highlightedPhotoIndex = 0
    @FocusState private var isNoteFocused: Bool

    // Crop sheet
    @State private var showCropSheet = false
    @State private var cropSourceImage: UIImage?
    @State private var cropSourceIndex: Int?
    @State private var isDownloadingForCrop = false

    // Photo suggestions
    @State private var showSuggestions = false
    @State private var suggestionsLoaded = false

    // Trip editing
    @State private var showNewTripAlert = false
    @State private var newTripName = ""
    @State private var showAllTrips = false

    private let maxPhotos = 5
    private let maxNoteLength = 280

    // MARK: - Computed properties

    private var hasPhotos: Bool { !log.userPhotoURLs.isEmpty }

    private var trip: Trip? {
        guard let tripID = log.tripID else { return nil }
        return allTrips.first { $0.id == tripID }
    }

    private var heroHeight: CGFloat { isEditing ? 300 : 520 }

    /// Trips the user can add logs to (owned + collaborating), sorted by most recently used.
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

    /// Chips to display: first 3 available trips, plus the currently selected trip if not already shown.
    private var visibleTrips: [Trip] {
        var result = Array(availableTrips.prefix(3))
        if let tripID = editSelectedTripID,
           !result.contains(where: { $0.id == tripID }),
           let trip = availableTrips.first(where: { $0.id == tripID }) {
            result.insert(trip, at: 0)
        }
        return result
    }

    /// Snapshot of all editable fields for consolidated change detection.
    private var editableFieldsSnapshot: [String] {
        [editRating.rawValue, editNote, editTags.joined(separator: "\0"), editSelectedTripID ?? "", editVisitedAt.description]
    }

    /// Total photo count across existing URLs and newly selected images
    private var editTotalPhotoCount: Int {
        editCurrentPhotoURLs.count + editSelectedImages.count
    }

    private var editSelectedTripBinding: Binding<Trip?> {
        Binding(
            get: { allTrips.first(where: { $0.id == editSelectedTripID }) },
            set: { editSelectedTripID = $0?.id }
        )
    }

    /// The photo URLs to pass to fullscreen viewer (user photos or Google Places fallback)
    private var fullscreenPhotoURLs: [String] {
        if hasPhotos {
            return log.userPhotoURLs
        } else if let photoRef = place.photoReference,
                  let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 1200) {
            return [url.absoluteString]
        }
        return []
    }

    private var placeholderIcon: String {
        let icons = ["sparkles", "camera.aperture", "mappin.and.ellipse", "airplane", "globe.americas", "map", "paintbrush.pointed"]
        return icons[abs(log.id.hashValue) % icons.count]
    }

    private var placeholderPrompt: String {
        let prompts = ["What caught your eye?", "Every place has a face", "Snap something worth remembering", "The best souvenir is a photo", "What does this place look like?", "Capture this moment", "A picture worth a thousand places"]
        return prompts[abs(log.id.hashValue) % prompts.count]
    }

    // MARK: - Body

    var body: some View {
        if log.isDeleted {
            Color.clear
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        mainContentBody
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                    contentAppeared = true
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isEditing)
            .toolbar { toolbarContent }
            .preference(key: HideTabBarGradientKey.self, value: (isEditing && hasChanges) || showSavedToast)
            .overlay { loadingOverlay }
            .modifier(ViewModeSheets(
                selectedPlaceDetails: $selectedPlaceDetails,
                placeToLog: $placeToLog,
                showFullscreenPhoto: $showFullscreenPhoto,
                showShareLog: $showShareLog,
                fullscreenPhotoURLs: fullscreenPhotoURLs,
                fullscreenPhotoIndex: fullscreenPhotoIndex,
                log: log,
                place: place,
                cacheService: cacheService
            ))
            .modifier(EditModeSheets(
                showAllTrips: $showAllTrips,
                showDeleteAlert: $showDeleteAlert,
                showDiscardAlert: $showDiscardAlert,
                showNewTripAlert: $showNewTripAlert,
                showCropSheet: $showCropSheet,
                newTripName: $newTripName,
                cropSourceImage: cropSourceImage,
                availableTrips: availableTrips,
                editSelectedTripBinding: editSelectedTripBinding,
                onDeleteLog: deleteLog,
                onExitEditMode: exitEditMode,
                onCreateTrip: createNewTrip,
                onCropDone: handleCropResult,
                onCropCancel: {
                    showCropSheet = false
                    cropSourceImage = nil
                    cropSourceIndex = nil
                }
            ))
            .onChange(of: editableFieldsSnapshot) { _, _ in
                if isEditing && editModeInitialized {
                    hasChanges = true
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            editSelectedImages.append(image)
                            editOriginalImages.append(image)
                        }
                    }
                    hasChanges = true
                    selectedPhotoItems = []
                }
            }
            .onChange(of: log.isDeleted ? [] as [String] : log.photoURLs) { _, newURLs in
                guard !log.isDeleted else { return }
                let filtered = newURLs.filter { !$0.contains("googleapis.com") }
                if isEditing {
                    editCurrentPhotoURLs = filtered
                }
            }
    }

    private var mainContentBody: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                        .frame(height: heroHeight)
                        .zIndex(0)

                    frostedPanel
                        .padding(.top, isEditing ? -50 : -120)
                        .zIndex(1)
                }
                .animation(.easeInOut(duration: 0.35), value: isEditing)
            }
            .scrollDismissesKeyboard(isEditing ? .interactively : .never)
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)

            if isEditing || showSavedToast {
                saveToastOverlay
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoadingDetails {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .overlay {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                        .scaleEffect(1.2)
                }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        if isEditing {
            editHeroSection
        } else {
            viewHeroSection
        }
    }

    @ViewBuilder
    private var viewHeroSection: some View {
        if hasPhotos {
            FeedItemCardShared.photoCarousel(
                photoURLs: log.userPhotoURLs,
                pageIndex: $photoPageIndex,
                height: 520
            )
            .onTapGesture {
                fullscreenPhotoIndex = photoPageIndex
                showFullscreenPhoto = true
            }
        } else if let photoRef = place.photoReference,
                  let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
            Color.clear.overlay {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 520)) {
                    noPhotoHero
                }
            }
            .clipped()
        } else {
            noPhotoHero
        }
    }

    private var editHeroSection: some View {
        Group {
            if editTotalPhotoCount == 0 {
                PhotoPlaceholderView(icon: placeholderIcon, prompt: placeholderPrompt)
            } else {
                let allPhotos = editCurrentPhotoURLs.count + editSelectedImages.count
                let index = min(highlightedPhotoIndex, allPhotos - 1)
                if index < editCurrentPhotoURLs.count {
                    let urlString = editCurrentPhotoURLs[index]
                    if urlString.hasPrefix("pending-upload:") {
                        Rectangle()
                            .fill(SonderColors.warmGray)
                            .overlay {
                                VStack(spacing: SonderSpacing.xs) {
                                    ProgressView()
                                        .tint(SonderColors.terracotta)
                                    Text("Uploading...")
                                        .font(SonderTypography.caption)
                                        .foregroundStyle(SonderColors.inkMuted)
                                }
                            }
                    } else if let url = URL(string: urlString) {
                        Color.clear.overlay {
                            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 300)) {
                                PhotoPlaceholderView(icon: placeholderIcon, prompt: placeholderPrompt)
                            }
                        }
                        .clipped()
                    }
                } else {
                    let imgIndex = index - editCurrentPhotoURLs.count
                    if imgIndex < editSelectedImages.count {
                        Color.clear.overlay {
                            Image(uiImage: editSelectedImages[imgIndex])
                                .resizable()
                                .scaledToFill()
                        }
                        .clipped()
                    }
                }
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Edit Photo Strip

    private var editPhotoStrip: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack {
                Text("Photos")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                if editTotalPhotoCount < maxPhotos {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSuggestions.toggle()
                        }
                        if showSuggestions && !suggestionsLoaded {
                            Task { await fetchEditPhotoSuggestions() }
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(showSuggestions ? .white : SonderColors.terracotta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(showSuggestions ? SonderColors.terracotta : SonderColors.terracotta.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Spacer()
                Text("\(editTotalPhotoCount)/\(maxPhotos)")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            if editTotalPhotoCount == 0 {
                // Empty state: wide add button
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: maxPhotos,
                    matching: .images
                ) {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Add Photos")
                            .font(SonderTypography.body)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(SonderColors.terracotta)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(SonderColors.warmGray)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                            .strokeBorder(SonderColors.terracotta.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                    )
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SonderSpacing.xs) {
                        // Existing remote photo thumbnails
                        ForEach(Array(editCurrentPhotoURLs.enumerated()), id: \.offset) { index, urlString in
                            photoThumbnail(combinedIndex: index) {
                                if let url = URL(string: urlString) {
                                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 128, height: 128)) {
                                        Color(SonderColors.warmGray)
                                    }
                                }
                            }
                        }

                        // Newly selected image thumbnails
                        ForEach(Array(editSelectedImages.enumerated()), id: \.offset) { index, image in
                            photoThumbnail(combinedIndex: editCurrentPhotoURLs.count + index) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }

                        // Add button (if under limit)
                        if editTotalPhotoCount < maxPhotos {
                            PhotosPicker(
                                selection: $selectedPhotoItems,
                                maxSelectionCount: maxPhotos - editTotalPhotoCount,
                                matching: .images
                            ) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(SonderColors.inkMuted)
                                }
                                .frame(width: 64, height: 64)
                                .background(SonderColors.warmGray)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                                        .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )
                            }
                        }

                    }
                }
            }

            // Collapsible suggestions row
            if showSuggestions {
                PhotoSuggestionsRow(
                    thumbnailSize: 64,
                    canAddMore: editTotalPhotoCount < maxPhotos,
                    showEmptyState: suggestionsLoaded
                ) { image in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        editSelectedImages.append(image)
                        editOriginalImages.append(image)
                        highlightedPhotoIndex = editCurrentPhotoURLs.count + editSelectedImages.count - 1
                    }
                    hasChanges = true
                    // Auto-hide suggestions if at max
                    if editTotalPhotoCount >= maxPhotos {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSuggestions = false
                        }
                    }
                }
            }
        }
    }

    private func photoThumbnail<Content: View>(combinedIndex: Int, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                        .stroke(highlightedPhotoIndex == combinedIndex ? SonderColors.terracotta : Color.clear, lineWidth: 2)
                )
                .overlay {
                    if isDownloadingForCrop && cropSourceIndex == combinedIndex {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 64, height: 64)
                            .background(.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if highlightedPhotoIndex == combinedIndex {
                        openCropSheet(for: combinedIndex)
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            highlightedPhotoIndex = combinedIndex
                        }
                    }
                }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    removePhoto(at: combinedIndex)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
    }

    private var noPhotoHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.25, blue: 0.18),
                    Color(red: 0.28, green: 0.20, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            SonderColors.pinColor(for: log.rating).opacity(0.15)

            Image(systemName: place.categoryIcon)
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.06))
                .rotationEffect(.degrees(-15))
        }
    }

    // MARK: - Frosted Panel

    private var frostedPanel: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.lg) {
            if isEditing {
                editPanelContent
            } else {
                viewPanelContent
            }
        }
        .padding(.horizontal, SonderSpacing.lg)
        .padding(.top, isEditing ? SonderSpacing.lg : SonderSpacing.sm)
        .padding(.bottom, isEditing ? 100 : 80)
        .background(alignment: .topTrailing) {
            Text(isEditing ? editRating.emoji : log.rating.emoji)
                .font(.system(size: 140))
                .opacity(0.05)
                .rotationEffect(.degrees(-15))
                .offset(x: 20, y: -10)
        }
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: SonderSpacing.radiusXl,
                topTrailingRadius: SonderSpacing.radiusXl
            )
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
    }

    // MARK: - View Panel Content

    @ViewBuilder
    private var viewPanelContent: some View {
        placeNameSection
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 20)

        waxSealRating
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 20)

        if let trip {
            tripBadge(trip)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 20)
        }

        if let note = log.note, !note.isEmpty {
            noteQuote(note)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 20)
        }

        if !log.tags.isEmpty {
            FlowLayoutTags(tags: log.tags)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 20)
        }
    }

    // MARK: - Edit Panel Content

    @ViewBuilder
    private var editPanelContent: some View {
        editPhotoStrip
        sectionDivider
        editPlaceSection
        sectionDivider
        editRatingSection
        sectionDivider
        editNoteSection
        sectionDivider
        editTagsSection
        sectionDivider
        editTripSection
        sectionDivider
        editMetaSection
        editDeleteSection
    }

    // MARK: - View-mode Sections

    private var placeNameSection: some View {
        Button(action: { fetchPlaceDetails() }) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    Text(place.name)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SonderColors.inkDark)

                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                        Text(place.address)
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(SonderColors.inkDark.opacity(0.6))
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(SonderColors.inkMuted)
                    .padding(.bottom, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var waxSealRating: some View {
        let color = SonderColors.pinColor(for: log.rating)
        return HStack(spacing: SonderSpacing.md) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                    .shadow(color: color.opacity(0.4), radius: 0, x: 1, y: 1)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.25),
                                .clear,
                                .black.opacity(0.1)
                            ],
                            center: .init(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
                    .frame(width: 64, height: 64)

                Text(log.rating.emoji)
                    .font(.system(size: 28))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(log.rating.displayName)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                Text(log.visitedAt.formatted(date: .long, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(SonderColors.inkDark.opacity(0.6))
            }

            Spacer()
        }
    }

    private func tripBadge(_ trip: Trip) -> some View {
        HStack(spacing: SonderSpacing.xxs) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 11))
            Text(trip.name)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(SonderColors.terracotta)
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xxs + 2)
        .background(SonderColors.terracotta.opacity(0.1))
        .clipShape(Capsule())
    }

    private func noteQuote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            Rectangle()
                .fill(SonderColors.terracotta)
                .frame(width: 3)

            Text(note.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 17, design: .serif))
                .italic()
                .foregroundStyle(SonderColors.inkDark)
                .lineSpacing(5)
        }
    }

    // MARK: - Edit-mode Sections

    private var editPlaceSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text(place.name)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(SonderColors.inkDark)

            HStack(spacing: SonderSpacing.xs) {
                Image(systemName: "mappin")
                    .font(.system(size: 12))
                    .foregroundStyle(SonderColors.inkMuted)
                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }
        }
    }

    private var editRatingSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Rating")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            HStack(spacing: SonderSpacing.sm) {
                ForEach(Rating.allCases, id: \.self) { ratingOption in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editRating = ratingOption
                        }
                    } label: {
                        VStack(spacing: SonderSpacing.xxs) {
                            Text(ratingOption.emoji)
                                .font(.system(size: 32))

                            Text(ratingOption.displayName)
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SonderSpacing.sm)
                        .background(editRating == ratingOption ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                        .foregroundStyle(editRating == ratingOption ? SonderColors.terracotta : SonderColors.inkDark)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                .stroke(editRating == ratingOption ? SonderColors.terracotta : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var editNoteSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("Note")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                Spacer()

                Text("\(editNote.count)/\(maxNoteLength)")
                    .font(SonderTypography.caption)
                    .foregroundStyle(editNote.count > maxNoteLength ? .red : SonderColors.inkLight)
                    .opacity(isNoteFocused ? 1 : 0)
            }

            TextField("Add a note...", text: $editNote, axis: .vertical)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(3...10)
                .padding(SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .focused($isNoteFocused)
                .onChange(of: editNote) { _, newValue in
                    if newValue.count > maxNoteLength {
                        editNote = String(newValue.prefix(maxNoteLength))
                    }
                }
        }
    }

    private var editTagsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Tags")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            TagInputView(selectedTags: $editTags)
        }
    }

    private var editTripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Trip")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(visibleTrips, id: \.id) { trip in
                        editTripChip(trip)
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
                            .foregroundStyle(SonderColors.inkMuted)
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
                        .foregroundStyle(SonderColors.inkDark)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let tripID = editSelectedTripID,
               let trip = allTrips.first(where: { $0.id == tripID }) {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SonderColors.terracotta)
                    Text("Saving to \(trip.name)")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: editSelectedTripID)
    }

    private func editTripChip(_ trip: Trip) -> some View {
        let isSelected = editSelectedTripID == trip.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                editSelectedTripID = isSelected ? nil : trip.id
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
            .foregroundStyle(isSelected ? .white : SonderColors.inkDark)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var editMetaSection: some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(SonderColors.inkMuted)

            DatePicker("", selection: $editVisitedAt)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(SonderColors.terracotta)
        }
    }

    private var editDeleteSection: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            HStack {
                Spacer()
                Label("Delete Log", systemImage: "trash")
                    .font(SonderTypography.body)
                Spacer()
            }
            .padding(SonderSpacing.md)
            .background(Color.red.opacity(0.1))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .padding(.top, SonderSpacing.lg)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGray)
            .frame(height: 1)
    }

    // MARK: - Save / Toast Overlay

    private var saveToastOverlay: some View {
        Group {
            if showSavedToast {
                HStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SonderColors.sage)
                    Text("Saved")
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                }
                .padding(.horizontal, SonderSpacing.md)
                .padding(.vertical, SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
            } else if hasChanges {
                Button {
                    save()
                } label: {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "checkmark")
                        Text("Save")
                            .font(SonderTypography.headline)
                    }
                    .padding(.horizontal, SonderSpacing.lg)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.terracotta)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
                }
            }
        }
        .padding(.bottom, SonderSpacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: hasChanges)
        .animation(.easeInOut(duration: 0.25), value: showSavedToast)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .navigation) {
                Button {
                    if hasChanges {
                        showDiscardAlert = true
                    } else {
                        exitEditMode()
                    }
                } label: {
                    Text("Cancel")
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
            if !hasChanges {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exitEditMode()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SonderColors.terracotta)
                            .toolbarIcon()
                    }
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        showShareLog = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SonderColors.inkMuted)
                            .toolbarIcon()
                    }

                    Button {
                        enterEditMode()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SonderColors.terracotta)
                            .toolbarIcon()
                    }
                }
            }
        }
    }

    // MARK: - Enter / Exit Edit Mode

    private func enterEditMode() {
        editRating = log.rating
        editNote = log.note ?? ""
        editTags = log.tags
        editSelectedTripID = log.tripID
        editVisitedAt = log.visitedAt
        editCurrentPhotoURLs = log.userPhotoURLs
        editSelectedImages = []
        editOriginalImages = []
        selectedPhotoItems = []
        highlightedPhotoIndex = 0
        hasChanges = false
        showSavedToast = false
        editModeInitialized = false
        showSuggestions = false
        suggestionsLoaded = false

        withAnimation(.easeInOut(duration: 0.35)) {
            isEditing = true
        }
        // Delay flag so onChange doesn't fire on initial snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editModeInitialized = true
        }
    }

    private func exitEditMode() {
        isNoteFocused = false
        editModeInitialized = false
        showSuggestions = false
        photoSuggestionService.clearSuggestions()
        suggestionsLoaded = false
        withAnimation(.easeInOut(duration: 0.35)) {
            isEditing = false
        }
    }

    // MARK: - Actions

    private func save() {
        guard let userId = authService.currentUser?.id else { return }

        isNoteFocused = false

        // Queue new photos for background upload
        var newURLs: [String] = []
        if !editSelectedImages.isEmpty {
            let logID = log.id
            let context = modelContext
            let engine = syncEngine
            newURLs = photoService.queueBatchUpload(
                images: editSelectedImages,
                for: userId,
                logID: logID
            ) { results in
                let idToFind = logID
                let descriptor = FetchDescriptor<Log>(
                    predicate: #Predicate { log in log.id == idToFind }
                )
                guard let log = try? context.fetch(descriptor).first else { return }

                log.photoURLs = log.photoURLs.compactMap { url in
                    if url.hasPrefix("pending-upload:") {
                        let placeholderID = String(url.dropFirst("pending-upload:".count))
                        return results[placeholderID]
                    }
                    return url
                }
                log.updatedAt = Date()
                try? context.save()

                Task { await engine.syncNow() }
            }
        }

        let finalPhotoURLs = editCurrentPhotoURLs + newURLs

        let trimmedNote = editNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTags = editTags.compactMap { tag -> String? in
            let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        log.rating = editRating
        log.photoURLs = finalPhotoURLs
        log.note = trimmedNote.isEmpty ? nil : trimmedNote
        log.tags = trimmedTags
        log.tripID = editSelectedTripID
        log.visitedAt = editVisitedAt
        log.updatedAt = Date()
        log.syncStatus = .pending

        do {
            try modelContext.save()

            editCurrentPhotoURLs = finalPhotoURLs
            editSelectedImages = []
        editOriginalImages = []
            hasChanges = false

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // Exit edit mode and show toast simultaneously
            isNoteFocused = false
            editModeInitialized = false
            withAnimation(.easeInOut(duration: 0.35)) {
                isEditing = false
                showSavedToast = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { showSavedToast = false }
            }

            if newURLs.isEmpty {
                Task { await syncEngine.syncNow() }
            }
        } catch {
            logger.error("Failed to save log: \(error.localizedDescription)")
        }
    }

    private func removePhoto(at combinedIndex: Int) {
        if combinedIndex < editCurrentPhotoURLs.count {
            editCurrentPhotoURLs.remove(at: combinedIndex)
        } else {
            let i = combinedIndex - editCurrentPhotoURLs.count
            if i < editSelectedImages.count {
                editSelectedImages.remove(at: i)
                editOriginalImages.remove(at: i)
            }
        }
        let total = editTotalPhotoCount
        if highlightedPhotoIndex >= total && total > 0 {
            highlightedPhotoIndex = total - 1
        }
        hasChanges = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Crop

    private func openCropSheet(for combinedIndex: Int) {
        if combinedIndex < editCurrentPhotoURLs.count {
            let urlString = editCurrentPhotoURLs[combinedIndex]
            // Skip pending uploads
            guard !urlString.hasPrefix("pending-upload:"),
                  let url = URL(string: urlString) else { return }

            isDownloadingForCrop = true
            cropSourceIndex = combinedIndex
            Task {
                defer { isDownloadingForCrop = false }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                cropSourceImage = image
                showCropSheet = true
            }
        } else {
            let imgIndex = combinedIndex - editCurrentPhotoURLs.count
            guard imgIndex < editOriginalImages.count else { return }
            cropSourceImage = editOriginalImages[imgIndex]
            cropSourceIndex = combinedIndex
            showCropSheet = true
        }
    }

    private func handleCropResult(_ croppedImage: UIImage) {
        guard let index = cropSourceIndex else { return }

        if index < editCurrentPhotoURLs.count {
            // Remote photo: remove URL, append cropped image + keep downloaded original
            let originalDownloaded = cropSourceImage!
            editCurrentPhotoURLs.remove(at: index)
            editSelectedImages.append(croppedImage)
            editOriginalImages.append(originalDownloaded)
            highlightedPhotoIndex = editCurrentPhotoURLs.count + editSelectedImages.count - 1
        } else {
            // Local photo: replace cropped display version, original stays
            let imgIndex = index - editCurrentPhotoURLs.count
            if imgIndex < editSelectedImages.count {
                editSelectedImages[imgIndex] = croppedImage
            }
        }

        hasChanges = true
        cropSourceImage = nil
        cropSourceIndex = nil
    }

    // MARK: - Photo Suggestions

    private func fetchEditPhotoSuggestions() async {
        await photoSuggestionService.requestAuthorizationIfNeeded()
        guard photoSuggestionService.authorizationLevel == .full ||
              photoSuggestionService.authorizationLevel == .limited else { return }
        await photoSuggestionService.fetchSuggestions(near: place.coordinate)
        suggestionsLoaded = true
    }

    private func deleteLog() {
        let logID = log.id
        let engine = syncEngine

        // Delete locally first so log.isDeleted becomes true immediately,
        // preventing SwiftUI from accessing stale model properties.
        modelContext.delete(log)
        try? modelContext.save()

        onDelete?()
        dismiss()

        // Push deletion to Supabase asynchronously
        Task {
            await engine.pushLogDeletion(id: logID)
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

        editSelectedTripID = trip.id
    }

    // MARK: - Fetch Place Details

    private func fetchPlaceDetails() {
        Task {
            isLoadingDetails = true
            if let details = await placesService.getPlaceDetails(placeId: place.id) {
                selectedPlaceDetails = details
            }
            isLoadingDetails = false
        }
    }
}

// MARK: - View-mode sheets modifier

private struct ViewModeSheets: ViewModifier {
    @Binding var selectedPlaceDetails: PlaceDetails?
    @Binding var placeToLog: Place?
    @Binding var showFullscreenPhoto: Bool
    @Binding var showShareLog: Bool
    let fullscreenPhotoURLs: [String]
    let fullscreenPhotoIndex: Int
    let log: Log
    let place: Place
    let cacheService: PlacesCacheService

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $selectedPlaceDetails) { details in
                PlacePreviewView(details: details) {
                    let cached = cacheService.cachePlace(from: details)
                    placeToLog = cached
                }
            }
            .fullScreenCover(item: $placeToLog) { place in
                NavigationStack {
                    RatePlaceView(place: place) { _ in
                        selectedPlaceDetails = nil
                        placeToLog = nil
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullscreenPhoto) {
                FullscreenPhotoViewer(
                    photoURLs: fullscreenPhotoURLs,
                    initialIndex: fullscreenPhotoIndex
                )
            }
            .sheet(isPresented: $showShareLog) {
                ShareLogView(log: log, place: place)
            }
    }
}

// MARK: - Edit-mode sheets & alerts modifier

private struct EditModeSheets: ViewModifier {
    @Binding var showAllTrips: Bool
    @Binding var showDeleteAlert: Bool
    @Binding var showDiscardAlert: Bool
    @Binding var showNewTripAlert: Bool
    @Binding var showCropSheet: Bool
    @Binding var newTripName: String
    let cropSourceImage: UIImage?
    let availableTrips: [Trip]
    let editSelectedTripBinding: Binding<Trip?>
    let onDeleteLog: () -> Void
    let onExitEditMode: () -> Void
    let onCreateTrip: () -> Void
    let onCropDone: (UIImage) -> Void
    let onCropCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAllTrips) {
                AllTripsPickerSheet(
                    trips: availableTrips,
                    selectedTrip: editSelectedTripBinding,
                    isPresented: $showAllTrips
                )
            }
            .fullScreenCover(isPresented: $showCropSheet) {
                if let image = cropSourceImage {
                    ImageCropSheet(
                        image: image,
                        onDone: { cropped in
                            showCropSheet = false
                            onCropDone(cropped)
                        },
                        onCancel: {
                            onCropCancel()
                        }
                    )
                }
            }
            .alert("Delete Log", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { onDeleteLog() }
            } message: {
                Text("Are you sure you want to delete this log? This action cannot be undone.")
            }
            .alert("Unsaved Changes", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) { }
                Button("Discard", role: .destructive) { onExitEditMode() }
            } message: {
                Text("You have unsaved changes. Do you want to discard them?")
            }
            .alert("New Trip", isPresented: $showNewTripAlert) {
                TextField("Trip name", text: $newTripName)
                Button("Cancel", role: .cancel) { }
                Button("Create") { onCreateTrip() }
                    .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Enter a name for your trip")
            }
    }
}
