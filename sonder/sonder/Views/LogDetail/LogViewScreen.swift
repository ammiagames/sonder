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

/// A photo in the edit strip — either a remote URL or a local image with its original.
struct EditPhoto: Identifiable {
    let id = UUID()
    var source: Source
    var cropState: CropState?
    /// When a remote photo is cropped, preserves the original URL so we don't re-upload.
    var originalURL: String?
    /// Locally rendered crop preview for remote photos (avoids re-upload for crop-only edits).
    var croppedPreview: UIImage?

    enum Source {
        case remote(url: String)
        case local(display: UIImage, original: UIImage)
    }
}

/// Persisted crop states for a log, keyed by URL with positional fallback.
private struct SavedCropStates: Codable {
    let byURL: [String: CropState]
    let ordered: [CropState?]
    var originalURLs: [String: String]?   // displayURL → originalURL
    var orderedOriginals: [String?]?      // positional: index → originalURL
}

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
    @Environment(WantToGoService.self) private var wantToGoService

    let log: Log
    let place: Place
    var onDelete: (() -> Void)?
    /// Reports edit-mode state to the parent so it can block pop-to-root while editing.
    var externalIsEditing: Binding<Bool>? = nil

    @State private var allTrips: [Trip] = []
    @State private var allLogs: [Log] = []
    @State private var cachedAvailableTrips: [Trip] = []
    @State private var cachedRecentTags: [String] = []

    // MARK: - View-mode state

    @State private var photoPageIndex = 0
    @State private var selectedPlaceDetails: PlaceDetails?
    @State private var isLoadingDetails = false
    @State private var placeToLog: Place?
    @State private var contentAppeared = false
    @State private var showShareLog = false
    @State private var showDirectionsDialog = false
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
    @State private var editPhotos: [EditPhoto] = []
    @State private var draggingPhotoID: UUID?
    @State private var dragOffset: CGFloat = 0

    // MARK: - Edit UI state

    @State private var showDeleteAlert = false
    @State private var showDiscardAlert = false
    @State private var hasChanges = false
    @State private var showSavedToast = false
    @State private var savedToastTask: Task<Void, Never>?
    @State private var fetchDetailsTask: Task<Void, Never>?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var highlightedPhotoIndex = 0
    @FocusState private var isNoteFocused: Bool

    // Crop sheet
    @State private var showCropSheet = false
    @State private var cropSourceImage: UIImage?
    @State private var cropSourceIndex: Int?
    @State private var cropSourceState: CropState?
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

    private var hasPhotos: Bool { !log.allUserPhotoURLs.isEmpty }

    private var trip: Trip? {
        guard let tripID = log.tripID else { return nil }
        return allTrips.first { $0.id == tripID }
    }

    private var heroHeight: CGFloat { isEditing ? 300 : 520 }

    private var availableTrips: [Trip] { cachedAvailableTrips }

    private var recentTagSuggestions: [String] { cachedRecentTags }

    private func refreshQueryData() {
        guard let userID = authService.currentUser?.id else { return }
        let logDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        allLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        let tripDescriptor = FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let fetchedTrips = (try? modelContext.fetch(tripDescriptor)) ?? []
        allTrips = fetchedTrips.filter { $0.isAccessible(by: userID) }

        rebuildDerivedCaches(userID: userID)
    }

    private func rebuildDerivedCaches(userID: String) {
        // Available trips sorted by most recently used
        let latestLogByTrip: [String: Date] = allLogs.reduce(into: [:]) { map, log in
            guard let tripID = log.tripID else { return }
            if let existing = map[tripID] {
                if log.createdAt > existing { map[tripID] = log.createdAt }
            } else {
                map[tripID] = log.createdAt
            }
        }
        cachedAvailableTrips = allTrips.sorted { a, b in
            let aDate = latestLogByTrip[a.id] ?? a.createdAt
            let bDate = latestLogByTrip[b.id] ?? b.createdAt
            return aDate > bDate
        }

        // Recent tag suggestions
        cachedRecentTags = recentTagsByUsage(logs: allLogs, userID: userID)
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
        editPhotos.count
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
            .task { refreshQueryData() }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                    contentAppeared = true
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isEditing)
            .toolbar(.automatic, for: .navigationBar)
            .toolbar { toolbarContent }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isNoteFocused = false }
                        .fontWeight(.medium)
                }
            }
            .preference(key: HideTabBarGradientKey.self, value: (isEditing && hasChanges) || showSavedToast)
            .preference(key: HideSonderTabBarKey.self, value: isNoteFocused)
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
                cropSourceState: cropSourceState,
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
                    cropSourceState = nil
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
                            editPhotos.append(EditPhoto(source: .local(display: image, original: image)))
                        }
                    }
                    hasChanges = true
                    selectedPhotoItems = []
                }
            }
            .directionsConfirmationDialog(isPresented: $showDirectionsDialog, coordinate: place.coordinate, name: place.name, address: place.address)
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
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // Swipe to the left (negative width) to dismiss edit mode if no changes
                    if isEditing && !hasChanges {
                        if value.translation.width < -100 && abs(value.translation.height) < 50 {
                            SonderHaptics.impact(.light)
                            exitEditMode()
                        }
                    }
                }
        )
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
        let uploadedURLs = log.userPhotoURLs
        if hasPhotos && uploadedURLs.isEmpty {
            // All photos still uploading — show progress state
            Rectangle()
                .fill(SonderColors.warmGray)
                .overlay {
                    VStack(spacing: SonderSpacing.xs) {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                        Text("Uploading photos...")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }
        } else if !uploadedURLs.isEmpty {
            ZStack(alignment: .topTrailing) {
                FeedItemCardShared.photoCarousel(
                    photoURLs: uploadedURLs,
                    pageIndex: $photoPageIndex,
                    height: 520
                )
                .onTapGesture {
                    fullscreenPhotoIndex = photoPageIndex
                    showFullscreenPhoto = true
                }

                if log.hasPendingUploads {
                    HStack(spacing: 4) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                        Text("Uploading...")
                            .font(SonderTypography.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xxs)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(SonderSpacing.sm)
                }
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
            if editPhotos.isEmpty {
                PhotoPlaceholderView(icon: placeholderIcon, prompt: placeholderPrompt)
            } else {
                let index = min(max(0, highlightedPhotoIndex), editPhotos.count - 1)
                let photo = editPhotos[index]
                if let preview = photo.croppedPreview {
                    Color.clear.overlay {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                } else {
                    switch photo.source {
                    case .remote(let urlString):
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
                    case .local(let display, _):
                        Color.clear.overlay {
                            Image(uiImage: display)
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
                Text("PHOTOS")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if editTotalPhotoCount < maxPhotos && showSuggestions {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSuggestions = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SonderColors.inkMuted)
                            .padding(4)
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
                        ForEach(Array(editPhotos.enumerated()), id: \.element.id) { index, photo in
                            photoThumbnail(at: index, photo: photo)
                                .scaleEffect(draggingPhotoID == photo.id ? 1.12 : 1.0)
                                .zIndex(draggingPhotoID == photo.id ? 1 : 0)
                                .shadow(color: draggingPhotoID == photo.id ? .black.opacity(0.2) : .clear, radius: 6, y: 2)
                                .offset(x: draggingPhotoID == photo.id ? dragOffset : 0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: editPhotos.map(\.id))
                                .animation(.easeOut(duration: 0.2), value: draggingPhotoID)
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.1)
                                        .sequenced(before: DragGesture())
                                        .onChanged { value in
                                            switch value {
                                            case .second(true, let drag):
                                                if draggingPhotoID == nil {
                                                    draggingPhotoID = photo.id
                                                    SonderHaptics.impact(.medium)
                                                }
                                                guard draggingPhotoID == photo.id else { return }
                                                let raw = drag?.translation.width ?? 0
                                                let itemWidth: CGFloat = 64 + SonderSpacing.xs
                                                let maxLeft = -CGFloat(index) * itemWidth
                                                let maxRight = CGFloat(editPhotos.count - 1 - index) * itemWidth
                                                dragOffset = min(max(raw, maxLeft), maxRight)
                                                checkPhotoReorder()
                                            default: break
                                            }
                                        }
                                        .onEnded { _ in
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                draggingPhotoID = nil
                                                dragOffset = 0
                                            }
                                        }
                                )
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
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                }
                .scrollDisabled(draggingPhotoID != nil)
            }

            // Collapsible suggestions row
            if showSuggestions {
                PhotoSuggestionsRow(
                    thumbnailSize: 64,
                    canAddMore: editTotalPhotoCount < maxPhotos,
                    showEmptyState: suggestionsLoaded
                ) { image in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        editPhotos.append(EditPhoto(source: .local(display: image, original: image)))
                        highlightedPhotoIndex = editPhotos.count - 1
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

    private func photoThumbnail(at index: Int, photo: EditPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = photo.croppedPreview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    switch photo.source {
                    case .remote(let urlString):
                        if urlString.hasPrefix("pending-upload:") {
                            Rectangle()
                                .fill(SonderColors.warmGray)
                                .overlay {
                                    ProgressView()
                                        .tint(SonderColors.terracotta)
                                        .scaleEffect(0.7)
                                }
                        } else if let url = URL(string: urlString) {
                            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 128, height: 128)) {
                                Color(SonderColors.warmGray)
                            }
                        }
                    case .local(let display, _):
                        Image(uiImage: display)
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                    .stroke(highlightedPhotoIndex == index ? SonderColors.terracotta : Color.clear, lineWidth: 2)
            )
            .overlay {
                if isDownloadingForCrop && cropSourceIndex == index {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 64, height: 64)
                        .background(.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if highlightedPhotoIndex == index {
                    openCropSheet(for: index)
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        highlightedPhotoIndex = index
                    }
                }
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    removePhoto(at: index)
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

    private func checkPhotoReorder() {
        guard let id = draggingPhotoID,
              let currentIndex = editPhotos.firstIndex(where: { $0.id == id }) else { return }
        let itemWidth: CGFloat = 64 + 8 // thumbnail + spacing
        // Only swap when dragged past half the item width
        let steps = Int(round(dragOffset / itemWidth))
        guard steps != 0 else { return }
        let targetIndex = min(max(currentIndex + steps, 0), editPhotos.count - 1)
        guard currentIndex != targetIndex else { return }
        editPhotos.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex)
        dragOffset -= CGFloat(steps) * itemWidth
        hasChanges = true
        SonderHaptics.impact(.light)
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
        editPlaceSection
        sectionDivider
        editPhotoStrip
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
            Text("RATING")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: SonderSpacing.md) {
                ForEach(Rating.allCases, id: \.self) { ratingOption in
                    editRatingCircle(ratingOption)
                }
            }
        }
    }

    private func editRatingCircle(_ rating: Rating) -> some View {
        let isSelected = editRating == rating
        let color = SonderColors.pinColor(for: rating)

        return Button {
            SonderHaptics.impact(.medium)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                editRating = rating
            }
        } label: {
            VStack(spacing: SonderSpacing.xs) {
                Text(rating.emoji)
                    .font(.system(size: 32))
                    .frame(width: 54, height: 54)
                    .background(isSelected ? color.opacity(0.2) : SonderColors.warmGray)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(isSelected ? color : .clear, lineWidth: 2)
                    )
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: editRating)

                Text(rating.displayName)
                    .font(SonderTypography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
            }
        }
        .buttonStyle(.plain)
    }

    private var editNoteSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("NOTE")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

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
            Text("TAGS")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TagInputView(
                selectedTags: $editTags,
                recentTags: recentTagSuggestions
            )
        }
    }

    private var editTripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("TRIP")
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

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
                        showDirectionsDialog = true
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SonderColors.inkMuted)
                            .toolbarIcon()
                    }

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
        let savedStates = loadCropStates()
        editPhotos = log.allUserPhotoURLs.enumerated().map { index, url in
            var photo = EditPhoto(source: .remote(url: url))
            if let saved = savedStates {
                photo.cropState = saved.byURL[url] ?? (index < saved.ordered.count ? saved.ordered[index] : nil)
                photo.originalURL = saved.originalURLs?[url] ?? {
                    guard let arr = saved.orderedOriginals, index < arr.count else { return nil }
                    return arr[index]
                }()
            }
            return photo
        }
        selectedPhotoItems = []
        highlightedPhotoIndex = 0
        hasChanges = false
        showSavedToast = false
        editModeInitialized = false
        showSuggestions = true
        suggestionsLoaded = false

        withAnimation(.easeInOut(duration: 0.35)) {
            isEditing = true
        }
        externalIsEditing?.wrappedValue = true
        // Delay flag so onChange doesn't fire on initial snapshot
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            editModeInitialized = true
        }
        // Eagerly fetch photo suggestions
        Task { await fetchEditPhotoSuggestions() }
    }

    private func exitEditMode() {
        isNoteFocused = false
        editModeInitialized = false
        showSuggestions = false
        photoSuggestionService.clearSuggestions()
        suggestionsLoaded = false
        editPhotos = []
        externalIsEditing?.wrappedValue = false
        withAnimation(.easeInOut(duration: 0.35)) {
            isEditing = false
        }
    }

    // MARK: - Actions

    private func save() {
        guard let userId = authService.currentUser?.id else { return }

        isNoteFocused = false

        // Separate remote URLs and local images, preserving order
        var finalPhotoURLs: [String] = []
        var imagesToUpload: [UIImage] = []
        var uploadSlots: [Int] = []

        for photo in editPhotos {
            switch photo.source {
            case .remote(let url):
                finalPhotoURLs.append(url)
            case .local(let display, let original):
                // Always upload — cropped display or uncropped original
                uploadSlots.append(finalPhotoURLs.count)
                finalPhotoURLs.append("")
                imagesToUpload.append(photo.cropState != nil ? display : original)
            }
        }

        // Queue new photos for background upload
        if !imagesToUpload.isEmpty {
            let logID = log.id
            let engine = syncEngine
            let newURLs = photoService.queueBatchUpload(
                images: imagesToUpload,
                for: userId,
                logID: logID
            ) { results in
                guard let updatedURLs = engine.replacePendingPhotoURLs(logID: logID, uploadResults: results) else { return }

                // Update crop state keys from pending-upload to real URLs (UserDefaults only — safe without SwiftData)
                if let cropData = UserDefaults.standard.data(forKey: "cropStates:\(logID)"),
                   let saved = try? JSONDecoder().decode(SavedCropStates.self, from: cropData) {
                    var updatedByURL = saved.byURL
                    var updatedOriginalURLs = saved.originalURLs ?? [:]

                    for (i, entry) in saved.ordered.enumerated() {
                        guard i < updatedURLs.count else { continue }
                        let url = updatedURLs[i]
                        guard !url.hasPrefix("pending-upload:") else { continue }
                        if let state = entry { updatedByURL[url] = state }
                        if let orderedOriginals = saved.orderedOriginals,
                           i < orderedOriginals.count,
                           let orig = orderedOriginals[i] {
                            updatedOriginalURLs[url] = orig
                        }
                    }

                    let updated = SavedCropStates(
                        byURL: updatedByURL, ordered: saved.ordered,
                        originalURLs: updatedOriginalURLs, orderedOriginals: saved.orderedOriginals
                    )
                    if let data = try? JSONEncoder().encode(updated) {
                        UserDefaults.standard.set(data, forKey: "cropStates:\(logID)")
                    }
                }
            }

            // Fill pending-upload URLs at the correct positions
            for (i, slot) in uploadSlots.enumerated() {
                if i < newURLs.count {
                    finalPhotoURLs[slot] = newURLs[i]
                }
            }
        }

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

            // Persist crop states for next edit session
            persistCropStates(finalURLs: finalPhotoURLs)

            editPhotos = []
            hasChanges = false

            SonderHaptics.notification(.success)

            // Exit edit mode and show toast simultaneously
            isNoteFocused = false
            editModeInitialized = false
            externalIsEditing?.wrappedValue = false
            withAnimation(.easeInOut(duration: 0.35)) {
                isEditing = false
                showSavedToast = true
            }
            savedToastTask?.cancel()
            savedToastTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation { showSavedToast = false }
            }

            if imagesToUpload.isEmpty {
                Task { await syncEngine.syncNow() }
            }
        } catch {
            logger.error("Failed to save log: \(error.localizedDescription)")
        }
    }

    private func removePhoto(at index: Int) {
        guard index < editPhotos.count else { return }
        editPhotos.remove(at: index)
        if highlightedPhotoIndex >= editPhotos.count && !editPhotos.isEmpty {
            highlightedPhotoIndex = editPhotos.count - 1
        }
        hasChanges = true
        SonderHaptics.impact(.light)
    }

    // MARK: - Crop

    private func openCropSheet(for index: Int) {
        guard index < editPhotos.count else { return }
        let photo = editPhotos[index]

        switch photo.source {
        case .remote(let urlString):
            let downloadURL = photo.originalURL ?? urlString
            guard !urlString.hasPrefix("pending-upload:"),
                  let url = URL(string: downloadURL) else { return }
            isDownloadingForCrop = true
            cropSourceIndex = index
            cropSourceState = photo.cropState
            Task {
                defer { isDownloadingForCrop = false }
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }
                cropSourceImage = image
                showCropSheet = true
            }
        case .local(_, let original):
            cropSourceImage = original
            cropSourceIndex = index
            cropSourceState = photo.cropState
            showCropSheet = true
        }
    }

    private func handleCropResult(_ croppedImage: UIImage, _ state: CropState) {
        guard let index = cropSourceIndex, index < editPhotos.count else { return }

        switch editPhotos[index].source {
        case .remote(let urlString):
            // Non-destructive: keep remote URL, store crop preview locally.
            // This avoids re-uploading when only the crop changed.
            editPhotos[index].originalURL = editPhotos[index].originalURL ?? urlString
            editPhotos[index].croppedPreview = croppedImage
        case .local(_, let original):
            // Update display, keep original
            editPhotos[index].source = .local(display: croppedImage, original: original)
        }
        editPhotos[index].cropState = state

        hasChanges = true
        cropSourceImage = nil
        cropSourceIndex = nil
        cropSourceState = nil
    }

    // MARK: - Photo Suggestions

    private func fetchEditPhotoSuggestions() async {
        await photoSuggestionService.requestAuthorizationIfNeeded()
        guard photoSuggestionService.authorizationLevel == .full ||
              photoSuggestionService.authorizationLevel == .limited else { return }
        await photoSuggestionService.fetchSuggestions(near: place.coordinate)
        suggestionsLoaded = true
    }

    // MARK: - Crop State Persistence

    private func persistCropStates(finalURLs: [String]) {
        var byURL: [String: CropState] = [:]
        var ordered: [CropState?] = []
        var originalURLs: [String: String] = [:]
        var orderedOriginals: [String?] = []

        for (i, photo) in editPhotos.enumerated() {
            ordered.append(photo.cropState)
            orderedOriginals.append(photo.originalURL)
            if i < finalURLs.count {
                let url = finalURLs[i]
                if !url.isEmpty && !url.hasPrefix("pending-upload:") {
                    if let state = photo.cropState { byURL[url] = state }
                    if let orig = photo.originalURL { originalURLs[url] = orig }
                }
            }
        }

        let store = SavedCropStates(
            byURL: byURL, ordered: ordered,
            originalURLs: originalURLs, orderedOriginals: orderedOriginals
        )
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: "cropStates:\(log.id)")
        }
    }

    private func loadCropStates() -> SavedCropStates? {
        guard let data = UserDefaults.standard.data(forKey: "cropStates:\(log.id)") else { return nil }
        return try? JSONDecoder().decode(SavedCropStates.self, from: data)
    }

    private func deleteLog() {
        let logID = log.id
        let engine = syncEngine

        UserDefaults.standard.removeObject(forKey: "cropStates:\(logID)")

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
        fetchDetailsTask?.cancel()
        fetchDetailsTask = Task {
            isLoadingDetails = true
            if let details = await placesService.getPlaceDetails(placeId: place.id) {
                guard !Task.isCancelled else { return }
                selectedPlaceDetails = details
            }
            if !Task.isCancelled { isLoadingDetails = false }
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
    let cropSourceState: CropState?
    let availableTrips: [Trip]
    let editSelectedTripBinding: Binding<Trip?>
    let onDeleteLog: () -> Void
    let onExitEditMode: () -> Void
    let onCreateTrip: () -> Void
    let onCropDone: (UIImage, CropState) -> Void
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
                        initialCropState: cropSourceState,
                        onDone: { cropped, state in
                            showCropSheet = false
                            onCropDone(cropped, state)
                        },
                        onCancel: {
                            onCropCancel()
                        }
                    )
                    .ignoresSafeArea()
                    .background(Color(red: 0.14, green: 0.12, blue: 0.11).ignoresSafeArea())
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
                            .foregroundStyle(SonderColors.inkDark)
                        Spacer()
                        if selectedTrip == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(SonderColors.terracotta)
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
                                .foregroundStyle(SonderColors.inkDark)
                            Spacer()
                            if selectedTrip?.id == trip.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SonderColors.terracotta)
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
