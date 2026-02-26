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

    // Collapsible cards
    @State private var collapsedClusterIDs: Set<UUID> = []

    @State private var savingTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: SonderSpacing.md) {
                    // Sticky progress counter + trip badge
                    progressHeader

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

                    // Excluded photos section
                    if !importService.excludedPhotos.isEmpty {
                        excludedSection
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

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: SonderSpacing.sm) {
            if let tripName {
                tripBadge(tripName)
            }

            HStack(spacing: SonderSpacing.xs) {
                let ready = importService.readyCount
                let total = importService.clusters.count

                Circle()
                    .fill(ready == total && total > 0 ? SonderColors.terracotta : SonderColors.inkLight)
                    .frame(width: 6, height: 6)

                Text("\(ready) of \(total) ready")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)

                if total > 0 && collapsedClusterIDs.count < readyClusterIDs.count {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            collapsedClusterIDs.formUnion(readyClusterIDs)
                        }
                    } label: {
                        Text("Collapse completed")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.terracotta)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

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

    /// IDs of clusters that have both a place and a rating.
    private var readyClusterIDs: Set<UUID> {
        Set(importService.clusters.filter { cluster in
            (cluster.confirmedPlace != nil || !cluster.suggestedPlaces.isEmpty)
            && cluster.rating != nil
        }.map(\.id))
    }

    // MARK: - Add Log Button

    private var addLogButton: some View {
        Button {
            SonderHaptics.impact(.light)
            let newID = importService.addEmptyCluster()
            withAnimation {
                collapsedClusterIDs.remove(newID)
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
        let isCollapsed = collapsedClusterIDs.contains(cluster.id)
        let isReady = readyClusterIDs.contains(cluster.id)

        return Group {
            if isCollapsed {
                collapsedCard(cluster, isReady: isReady)
            } else {
                expandedCard(cluster, isReady: isReady)
            }
        }
    }

    // MARK: Collapsed Card

    private func collapsedCard(_ cluster: PhotoCluster, isReady: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                _ = collapsedClusterIDs.remove(cluster.id)
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Lead thumbnail
                if let firstPhoto = cluster.photoMetadata.first {
                    PhotoThumbnailView(assetID: firstPhoto.id, photoSuggestionService: photoSuggestionService)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }

                // Place name
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.confirmedPlace?.name ?? cluster.suggestedPlaces.first?.name ?? "No place")
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    if cluster.photoMetadata.count > 0 {
                        Text("\(cluster.photoMetadata.count) photos")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }

                Spacer()

                // Rating emoji
                if let rating = cluster.rating {
                    Text(rating.emoji)
                        .font(.system(size: 20))
                }

                // Ready indicator
                if isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SonderColors.terracotta)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.warmGray.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { droppedIDs, _ in
            handleDrop(droppedIDs: droppedIDs, onCluster: cluster)
        } isTargeted: { targeted in
            dropTargetClusterID = targeted ? cluster.id : nil
        }
    }

    // MARK: Expanded Card

    private func expandedCard(_ cluster: PhotoCluster, isReady: Bool) -> some View {
        let cardBackground: Color = SonderColors.warmGray.opacity(0.5)

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Photo thumbnail strip
            photoStrip(for: cluster)

            // Place name (tappable to search) + inline search
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                .strokeBorder(
                    dropTargetClusterID == cluster.id ? SonderColors.terracotta : Color(white: 0, opacity: 0),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: SonderSpacing.xxs) {
                // Collapse button (only if card is ready)
                if isReady {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            collapsedClusterIDs.insert(cluster.id)
                            return ()
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SonderColors.inkLight)
                            .frame(width: 24, height: 24)
                    }
                }

                // Delete button
                Button {
                    withAnimation {
                        if inlineSearchClusterID == cluster.id {
                            collapseInlineSearch()
                        }
                        collapsedClusterIDs.remove(cluster.id)
                        importService.removeCluster(cluster.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
            .padding(SonderSpacing.xs)
        }
        .dropDestination(for: String.self) { droppedIDs, _ in
            handleDrop(droppedIDs: droppedIDs, onCluster: cluster)
        } isTargeted: { targeted in
            dropTargetClusterID = targeted ? cluster.id : nil
        }
    }

    private func handleDrop(droppedIDs: [String], onCluster cluster: PhotoCluster) -> Bool {
        let existingIDs = Set(cluster.photoMetadata.map(\.id))
        let newIDs = Set(droppedIDs).subtracting(existingIDs)
        guard !newIDs.isEmpty else { return false }

        let unlocatedIDs = Set(importService.unlocatedPhotos.map(\.id))
        let excludedIDs = Set(importService.excludedPhotos.map(\.id))
        let fromUnlocated = newIDs.intersection(unlocatedIDs)
        let fromExcluded = newIDs.intersection(excludedIDs)
        let fromClusters = newIDs.subtracting(fromUnlocated).subtracting(fromExcluded)

        withAnimation {
            if !fromClusters.isEmpty {
                importService.movePhotos(photoIDs: fromClusters, toClusterID: cluster.id)
            }
            if !fromUnlocated.isEmpty {
                importService.moveUnlocatedPhotos(photoIDs: fromUnlocated, toClusterID: cluster.id)
            }
            for id in fromExcluded {
                importService.restorePhoto(id, toClusterID: cluster.id)
            }
        }
        SonderHaptics.notification(.success)
        return true
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
                        ForEach(Array(cluster.photoMetadata.enumerated()), id: \.element.id) { index, photo in
                            PhotoThumbnailView(assetID: photo.id, photoSuggestionService: photoSuggestionService)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                                .overlay(alignment: .bottom) {
                                    if index == 0 && cluster.photoMetadata.count > 1 {
                                        Text("Cover")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color(SonderColors.terracotta).opacity(0.8))
                                            .clipShape(Capsule())
                                            .padding(3)
                                    }
                                }
                                .draggable(photo.id)
                                .contextMenu {
                                    if index != 0 {
                                        Button {
                                            withAnimation {
                                                importService.reorderPhoto(in: cluster.id, fromIndex: index, toIndex: 0)
                                            }
                                            SonderHaptics.impact(.light)
                                        } label: {
                                            Label("Make Cover Photo", systemImage: "star")
                                        }
                                    }

                                    Button(role: .destructive) {
                                        withAnimation {
                                            importService.excludePhoto(photo.id, fromClusterID: cluster.id)
                                        }
                                        SonderHaptics.impact(.light)
                                    } label: {
                                        Label("Remove from Log", systemImage: "minus.circle")
                                    }
                                }
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
                // Tappable place name — tap to open inline search
                if let place = cluster.confirmedPlace {
                    tappablePlaceLabel(
                        name: place.name,
                        address: place.address,
                        cluster: cluster
                    )
                } else if let first = cluster.suggestedPlaces.first {
                    tappablePlaceLabel(
                        name: first.name,
                        address: first.address,
                        cluster: cluster
                    )
                } else {
                    // No place at all — show search field inline immediately
                    Button {
                        openInlineSearch(for: cluster)
                    } label: {
                        HStack(spacing: SonderSpacing.xs) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(SonderColors.inkMuted)
                            Text("Search for a place")
                                .font(SonderTypography.headline)
                                .foregroundStyle(SonderColors.inkLight)
                            Spacer()
                        }
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.warmGray)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                    }
                    .buttonStyle(.plain)
                }

                // Inline place chips (up to 5 suggestions + search icon)
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
                        }
                    }
                }
            }
        }
    }

    /// A tappable place name + address label that opens inline search when tapped.
    private func tappablePlaceLabel(name: String, address: String, cluster: PhotoCluster) -> some View {
        Button {
            openInlineSearch(for: cluster, prefill: name)
        } label: {
            HStack(spacing: SonderSpacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                    Text(address)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(SonderColors.inkMuted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline Search

    private func openInlineSearch(for cluster: PhotoCluster, prefill: String = "") {
        withAnimation {
            inlineSearchClusterID = cluster.id
            inlineSearchText = prefill
            inlineSearchPredictions = []
            inlineSearchFocused = true
        }
    }

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
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation {
                                        importService.excludeUnlocatedPhoto(photo.id)
                                    }
                                } label: {
                                    Label("Exclude Photo", systemImage: "minus.circle")
                                }
                            }
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

    // MARK: - Excluded Section

    private var excludedSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack {
                Image(systemName: "eye.slash")
                    .foregroundStyle(SonderColors.inkMuted)
                Text("\(importService.excludedPhotos.count) excluded")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(importService.excludedPhotos) { photo in
                        PhotoThumbnailView(assetID: photo.id, photoSuggestionService: photoSuggestionService)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                            .opacity(0.5)
                            .draggable(photo.id)
                    }
                }
            }

            Text("Drag back onto a log to restore.")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
        }
        .padding(SonderSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SonderColors.warmGray.opacity(0.2))
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
