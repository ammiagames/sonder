//
//  BulkImportReviewView.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import SwiftUI
import Photos

/// Main review screen for bulk import — shows clustered log groups for user confirmation.
struct BulkImportReviewView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(GooglePlacesService.self) private var googlePlacesService
    @Environment(PlacesCacheService.self) private var placesCacheService
    @Environment(PhotoSuggestionService.self) private var photoSuggestionService
    @Environment(\.dismiss) private var dismiss

    @Bindable var importService: BulkPhotoImportService
    let tripID: String?
    let tripName: String?

    // Inline search state
    @State private var inlineSearchClusterID: UUID? = nil
    @State private var inlineSearchText: String = ""
    @State private var inlineSearchPredictions: [PlacePrediction] = []
    @State private var inlineSearchLoading: Bool = false
    @FocusState private var inlineSearchFocused: Bool

    // Drag-and-drop state
    @State private var dropTargetClusterID: UUID?

    @State private var savingTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: SonderSpacing.md) {
                    // Trip badge
                    if let tripName {
                        tripBadge(tripName)
                    }

                    // Cluster cards with inline search results
                    ForEach(importService.clusters) { cluster in
                        VStack(spacing: 0) {
                            clusterCard(cluster)

                            if inlineSearchClusterID == cluster.id && !inlineSearchPredictions.isEmpty {
                                inlineSearchResults(for: cluster)
                            }
                        }
                        .zIndex(inlineSearchClusterID == cluster.id ? 1 : 0)
                    }

                    // Add Log button
                    addLogButton

                    // Unlocated photos section
                    if !importService.unlocatedPhotos.isEmpty {
                        unlocatedSection
                    }
                }
                .padding(.horizontal, SonderSpacing.md)
                .padding(.top, SonderSpacing.md)
                .padding(.bottom, 100) // Room for floating button
            }
            .background(SonderColors.cream)

            // Floating save button
            saveButton
        }
    }

    // MARK: - Trip Badge

    private func tripBadge(_ name: String) -> some View {
        HStack(spacing: SonderSpacing.xs) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 14))
                .foregroundStyle(SonderColors.terracotta)
            Text(name)
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.xs)
        .background(SonderColors.warmGray)
        .clipShape(Capsule())
    }

    // MARK: - Add Log Button

    private var addLogButton: some View {
        Button {
            SonderHaptics.impact(.light)
            let newID = importService.addEmptyCluster()
            withAnimation {
                inlineSearchClusterID = newID
                inlineSearchText = ""
                inlineSearchPredictions = []
                inlineSearchFocused = true
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add Log")
                    .font(SonderTypography.headline)
            }
            .foregroundStyle(SonderColors.terracotta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                    .strokeBorder(SonderColors.terracotta, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cluster Card

    private func clusterCard(_ cluster: PhotoCluster) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Photo thumbnail strip
            photoStrip(for: cluster)

            // Place name + change button (or inline search)
            placeRow(for: cluster)

            // Compact rating picker
            compactRatingPicker(for: cluster)

            // Date display
            if let date = cluster.date {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(SonderColors.inkMuted)
                    Text(date, style: .date)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                .strokeBorder(
                    dropTargetClusterID == cluster.id ? SonderColors.terracotta : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        )
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation {
                    if inlineSearchClusterID == cluster.id {
                        collapseInlineSearch()
                    }
                    importService.removeCluster(cluster.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(SonderSpacing.xs)
        }
        .dropDestination(for: String.self) { droppedIDs, _ in
            let existingIDs = Set(cluster.photoMetadata.map(\.id))
            let newIDs = Set(droppedIDs).subtracting(existingIDs)
            guard !newIDs.isEmpty else { return false }

            let unlocatedIDs = Set(importService.unlocatedPhotos.map(\.id))
            let fromUnlocated = newIDs.intersection(unlocatedIDs)
            let fromClusters = newIDs.subtracting(fromUnlocated)

            withAnimation {
                if !fromClusters.isEmpty {
                    importService.movePhotos(photoIDs: fromClusters, toClusterID: cluster.id)
                }
                if !fromUnlocated.isEmpty {
                    importService.moveUnlocatedPhotos(photoIDs: fromUnlocated, toClusterID: cluster.id)
                }
            }
            SonderHaptics.notification(.success)
            return true
        } isTargeted: { targeted in
            dropTargetClusterID = targeted ? cluster.id : nil
        }
    }

    // MARK: - Photo Strip

    private func photoStrip(for cluster: PhotoCluster) -> some View {
        Group {
            if cluster.photoMetadata.isEmpty {
                // Empty cluster placeholder
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                            .foregroundStyle(SonderColors.inkLight)
                        Text("Drag photos here")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkLight)
                    }
                    Spacer()
                }
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                        .strokeBorder(SonderColors.inkLight, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SonderSpacing.xs) {
                        ForEach(cluster.photoMetadata) { photo in
                            PhotoThumbnailView(assetID: photo.id, photoSuggestionService: photoSuggestionService)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                                .draggable(photo.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Place Row

    private func placeRow(for cluster: PhotoCluster) -> some View {
        let selectedPlaceID = cluster.confirmedPlace?.id ?? cluster.suggestedPlaces.first?.placeId

        return VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            // Inline search mode
            if inlineSearchClusterID == cluster.id {
                inlineSearchField(for: cluster)
            } else {
                // Place name + address
                if let place = cluster.confirmedPlace {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)
                        Text(place.address)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                } else if let first = cluster.suggestedPlaces.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(first.name)
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)
                        Text(first.address)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                } else {
                    HStack {
                        Text("No place found")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkLight)
                        Spacer()
                        searchButton(for: cluster)
                    }
                }

                // Inline place chips (up to 5 suggestions + search button)
                if !cluster.suggestedPlaces.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SonderSpacing.xs) {
                            ForEach(cluster.suggestedPlaces.prefix(5)) { nearbyPlace in
                                placeChip(
                                    nearbyPlace: nearbyPlace,
                                    isSelected: nearbyPlace.placeId == selectedPlaceID,
                                    clusterID: cluster.id
                                )
                            }

                            searchButton(for: cluster)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Inline Search

    private func inlineSearchField(for cluster: PhotoCluster) -> some View {
        HStack(spacing: SonderSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(SonderColors.inkMuted)

            TextField("Search for a place", text: $inlineSearchText)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
                .focused($inlineSearchFocused)
                .submitLabel(.search)

            if inlineSearchLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }

            Button {
                withAnimation {
                    collapseInlineSearch()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        .onChange(of: inlineSearchText) { _, newValue in
            guard !newValue.isEmpty else {
                inlineSearchPredictions = []
                return
            }
            Task {
                inlineSearchLoading = true
                inlineSearchPredictions = await googlePlacesService.autocomplete(
                    query: newValue,
                    location: cluster.centroid
                )
                inlineSearchLoading = false
            }
        }
        .onAppear {
            inlineSearchFocused = true
        }
    }

    private func inlineSearchResults(for cluster: PhotoCluster) -> some View {
        VStack(spacing: 0) {
            ForEach(inlineSearchPredictions.prefix(5)) { prediction in
                Button {
                    selectInlineResult(prediction, for: cluster.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prediction.mainText)
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)
                        Text(prediction.secondaryText)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.sm)
                }
                .buttonStyle(.plain)

                if prediction.id != inlineSearchPredictions.prefix(5).last?.id {
                    Divider()
                        .padding(.horizontal, SonderSpacing.md)
                }
            }
        }
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .padding(.top, 4)
    }

    private func selectInlineResult(_ prediction: PlacePrediction, for clusterID: UUID) {
        inlineSearchLoading = true
        Task {
            if let details = await googlePlacesService.getPlaceDetails(placeId: prediction.placeId) {
                let place = placesCacheService.cachePlace(from: details)
                importService.updatePlace(for: clusterID, place: place)
            }
            withAnimation {
                collapseInlineSearch()
            }
        }
    }

    private func collapseInlineSearch() {
        inlineSearchClusterID = nil
        inlineSearchText = ""
        inlineSearchPredictions = []
        inlineSearchLoading = false
        inlineSearchFocused = false
    }

    private func placeChip(nearbyPlace: NearbyPlace, isSelected: Bool, clusterID: UUID) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            importService.selectSuggestedPlace(for: clusterID, nearbyPlace: nearbyPlace)
        } label: {
            Text(nearbyPlace.name)
                .font(SonderTypography.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? SonderColors.terracotta : SonderColors.inkDark)
                .background(isSelected ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? SonderColors.terracotta : Color.clear, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func searchButton(for cluster: PhotoCluster) -> some View {
        Button {
            withAnimation {
                inlineSearchClusterID = cluster.id
                inlineSearchText = ""
                inlineSearchPredictions = []
                inlineSearchFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(SonderColors.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SonderColors.warmGray)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Rating Picker

    private func compactRatingPicker(for cluster: PhotoCluster) -> some View {
        HStack(spacing: SonderSpacing.xs) {
            ForEach(Rating.allCases, id: \.rawValue) { rating in
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    importService.updateRating(for: cluster.id, rating: rating)
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.emoji)
                            .font(.system(size: 24))
                        Text(rating.displayName)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(
                                cluster.rating == rating ? SonderColors.inkDark : SonderColors.inkMuted
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(
                        cluster.rating == rating
                            ? SonderColors.warmGrayDark
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Unlocated Section

    private var unlocatedSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack {
                Image(systemName: "location.slash")
                    .foregroundStyle(SonderColors.inkMuted)
                Text("\(importService.unlocatedPhotos.count) photos without location")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(importService.unlocatedPhotos) { photo in
                        PhotoThumbnailView(assetID: photo.id, photoSuggestionService: photoSuggestionService)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                                    .strokeBorder(SonderColors.inkLight, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            )
                            .draggable(photo.id)
                    }
                }
            }

            Text("Drag photos onto a log above to include them.")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
        }
        .padding(SonderSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SonderColors.warmGray.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Save Button

    private var saveButton: some View {
        let count = importService.readyCount

        return VStack {
            if case .saving(let progress) = importService.state {
                ProgressView(value: progress)
                    .tint(SonderColors.terracotta)
                    .padding(.horizontal, SonderSpacing.xl)
            }

            Button {
                guard let userID = authService.currentUser?.id else { return }
                savingTask = Task {
                    await importService.saveAllLogs(userID: userID, tripID: tripID)
                }
            } label: {
                Text(importService.state == .saving(progress: 0) ? "Saving..." : "Create \(count) Logs")
                    .font(SonderTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(
                        importService.canSave
                            ? SonderColors.terracotta
                            : SonderColors.inkLight
                    )
                    .clipShape(Capsule())
            }
            .disabled(!importService.canSave || isSaving)
            .padding(.horizontal, SonderSpacing.xl)
            .padding(.bottom, SonderSpacing.lg)
        }
        .background(
            LinearGradient(
                colors: [SonderColors.cream.opacity(0), SonderColors.cream],
                startPoint: .top,
                endPoint: .center
            )
        )
    }

    private var isSaving: Bool {
        if case .saving = importService.state { return true }
        return false
    }
}

// MARK: - Photo Thumbnail View

/// Loads and displays a PHAsset thumbnail.
struct PhotoThumbnailView: View {
    let assetID: String
    let photoSuggestionService: PhotoSuggestionService

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(SonderColors.warmGray)
                    .opacity(0.6)
            }
        }
        .task {
            guard thumbnail == nil else { return }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            if let asset = result.firstObject {
                thumbnail = await photoSuggestionService.loadThumbnail(for: asset)
            }
        }
    }
}

// MARK: - Place Picker Sheet

/// Lightweight place search for changing a cluster's place.
/// Uses Google Places autocomplete + details to resolve a Place.
struct PlacePickerSheet: View {
    @Environment(GooglePlacesService.self) private var googlePlacesService
    @Environment(PlacesCacheService.self) private var placesCacheService
    @Environment(\.dismiss) private var dismiss

    let clusterID: UUID?
    let onPlaceSelected: (UUID, Place) -> Void

    @State private var searchText = ""
    @State private var predictions: [PlacePrediction] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if predictions.isEmpty && !searchText.isEmpty && !isLoading {
                    Text("No results")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)
                        .listRowBackground(SonderColors.cream)
                }

                ForEach(predictions) { prediction in
                    Button {
                        selectPlace(prediction)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prediction.mainText)
                                .font(SonderTypography.headline)
                                .foregroundStyle(SonderColors.inkDark)
                            Text(prediction.secondaryText)
                                .font(SonderTypography.caption)
                                .foregroundStyle(SonderColors.inkMuted)
                        }
                    }
                    .listRowBackground(SonderColors.cream)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .searchable(text: $searchText, prompt: "Search for a place")
            .navigationTitle("Change Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else {
                predictions = []
                return
            }
            Task {
                predictions = await googlePlacesService.autocomplete(query: newValue)
            }
        }
    }

    private func selectPlace(_ prediction: PlacePrediction) {
        guard let clusterID else { return }
        isLoading = true
        Task {
            if let details = await googlePlacesService.getPlaceDetails(placeId: prediction.placeId) {
                let place = placesCacheService.cachePlace(from: details)
                onPlaceSelected(clusterID, place)
            }
            dismiss()
        }
    }
}
