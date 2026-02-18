//
//  ShareTripView.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI
import CoreLocation
import UIKit

// MARK: - Export Data Models

struct TripExportData {
    let tripName: String
    let tripDescription: String?
    let dateRangeText: String?
    let placeCount: Int
    let dayCount: Int
    let ratingCounts: (mustSee: Int, solid: Int, skip: Int)
    let topTags: [String]
    var heroImage: UIImage?
    var logPhotos: [LogPhotoData]
    let stops: [ExportStop]
    var customCaption: String?
    var allAvailablePhotos: [LogPhotoData] = []
    var allHeroImages: [UIImage] = []
    var categoryBreakdown: [(emoji: String, label: String, count: Int)] = []
    var bestQuote: (text: String, placeName: String)?
}

struct LogPhotoData {
    let image: UIImage
    let placeName: String
    let rating: Rating
    var placeID: String = ""
    var note: String?
    var tags: [String] = []
}

struct ExportStop {
    let placeName: String
    let coordinate: CLLocationCoordinate2D
    let rating: Rating
    var placeID: String = ""
    var note: String?
    var tags: [String] = []
}

extension TripExportData {
    /// Photos aligned to stops by placeID (for route map and journey).
    /// Falls back to positional matching if placeIDs aren't set.
    var stopAlignedPhotos: [LogPhotoData?] {
        let photosByPlace = Dictionary(allAvailablePhotos.map { ($0.placeID, $0) }, uniquingKeysWith: { first, _ in first })
        return stops.map { stop in
            if !stop.placeID.isEmpty, let photo = photosByPlace[stop.placeID] {
                return photo
            }
            return nil
        }
    }
}

// MARK: - Export Style

enum ExportStyle: String, CaseIterable {
    case collage, receipt
    case cover, route, journey

    var title: String {
        switch self {
        case .collage: return "Collage"
        case .receipt: return "Receipt"
        case .cover: return "Cover"
        case .route: return "Route"
        case .journey: return "Journey"
        }
    }

    var icon: String {
        switch self {
        case .collage: return "rectangle.split.2x2"
        case .receipt: return "doc.text"
        case .cover: return "book.pages"
        case .route: return "map"
        case .journey: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

// MARK: - ShareTripView

struct ShareTripView: View {
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    let tripLogs: [Log]
    let places: [Place]

    @State private var selectedStyle: ExportStyle = .collage
    @State private var customization = TripExportCustomization()
    @State private var exportData: TripExportData?
    @State private var mapSnapshot: UIImage?
    @State private var mapSnapshotCache: [String: UIImage] = [:]
    @State private var previewImage: UIImage?
    @State private var isLoadingPhotos = true
    @State private var showFullPreview = false
    @State private var showShareSheet = false
    @State private var exportImage: UIImage?
    @State private var toastMessage: String?
    @State private var renderTask: Task<Void, Never>?
    @State private var captionDebounceTask: Task<Void, Never>?

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoadingPhotos {
                    loadingView
                } else {
                    // Zone 1: Preview
                    previewZone

                    // Zone 2: Customization Controls
                    customizationZone

                    // Zone 3: Action Bar
                    actionBar
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = exportImage {
                    ShareSheet(items: [image])
                }
            }
            .fullScreenCover(isPresented: $showFullPreview) {
                fullScreenPreview
            }
            .overlay(alignment: .top) {
                toastOverlay
            }
        }
        .task {
            await loadPhotos()
        }
        .onChange(of: selectedStyle) {
            schedulePreviewRender()
        }
        .onChange(of: customization.theme) {
            schedulePreviewRender()
        }
        .onChange(of: customization.aspectRatio) {
            schedulePreviewRender()
        }
        .onChange(of: customization.selectedHeroPhotoIndex) {
            updateHeroPhoto()
            schedulePreviewRender()
        }
        .onChange(of: customization.selectedLogPhotoIndices) {
            updateSelectedPhotos()
            schedulePreviewRender()
        }
        .onChange(of: customization.customCaption) {
            debounceCaptionRender()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(SonderColors.terracotta)
                Text("Preparing photos...")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: - Zone 1: Preview

    private var previewZone: some View {
        ScrollView {
            Group {
                if let preview = previewImage {
                    Button {
                        showFullPreview = true
                    } label: {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Shimmer placeholder
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SonderColors.warmGray)
                        .frame(width: 340, height: 340 * (customization.canvasSize.height / customization.canvasSize.width))
                        .overlay {
                            ProgressView()
                                .tint(SonderColors.terracotta)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.md)
            .animation(.easeInOut(duration: 0.2), value: previewImage == nil)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Zone 2: Customization Controls

    private var customizationZone: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SonderSpacing.lg) {
                // Style
                sectionLabel("STYLE")
                stylePickerRow

                // Theme
                sectionLabel("THEME")
                themePickerRow

                // Format
                sectionLabel("FORMAT")
                formatPickerRow

                // Hero Photo (Cover style only)
                if selectedStyle == .cover, let data = exportData, !data.allHeroImages.isEmpty {
                    sectionLabel("HERO PHOTO")
                    heroPhotoPickerRow
                }

                // Photos (for styles that show log photos)
                if selectedStyle != .route, let data = exportData, !data.allAvailablePhotos.isEmpty {
                    sectionLabel("PHOTOS")
                    photoPickerRow
                }

                // Caption
                sectionLabel("CAPTION")
                captionField
            }
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.vertical, SonderSpacing.sm)
        }
        .frame(maxHeight: 260)
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SonderColors.inkMuted)
            .tracking(1.2)
    }

    // MARK: - Style Picker

    private var stylePickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SonderSpacing.sm) {
                ForEach(ExportStyle.allCases, id: \.rawValue) { style in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        selectedStyle = style
                    } label: {
                        VStack(spacing: SonderSpacing.xxs) {
                            Image(systemName: style.icon)
                                .font(.system(size: 20))
                            Text(style.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(width: 72, height: 64)
                        .background(selectedStyle == style ? SonderColors.terracotta.opacity(0.12) : SonderColors.warmGray)
                        .foregroundStyle(selectedStyle == style ? SonderColors.terracotta : SonderColors.inkMuted)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        .overlay {
                            if selectedStyle == style {
                                RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                    .stroke(SonderColors.terracotta, lineWidth: 2)
                            }
                        }
                        .scaleEffect(selectedStyle == style ? 1.04 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: selectedStyle == style)
                    }
                }
            }
        }
    }

    // MARK: - Theme Picker

    private var themePickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SonderSpacing.sm) {
                ForEach(ExportColorTheme.allThemes) { theme in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        customization.theme = theme
                    } label: {
                        VStack(spacing: 6) {
                            // 3-dot swatch
                            VStack(spacing: 3) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .fill(theme.previewColors[i])
                                        .frame(width: 14, height: 14)
                                }
                            }
                            .padding(8)
                            .background(SonderColors.warmGray)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                            .overlay {
                                if customization.theme.id == theme.id {
                                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                                        .stroke(SonderColors.terracotta, lineWidth: 2)
                                }
                            }

                            Text(theme.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(customization.theme.id == theme.id ? SonderColors.terracotta : SonderColors.inkMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Format Picker

    private var formatPickerRow: some View {
        HStack(spacing: 0) {
            ForEach(ExportAspectRatio.allCases) { ratio in
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    customization.aspectRatio = ratio
                } label: {
                    Text(ratio.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(customization.aspectRatio == ratio ? .white : SonderColors.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(customization.aspectRatio == ratio ? SonderColors.terracotta : SonderColors.warmGray)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
    }

    // MARK: - Hero Photo Picker

    private var heroPhotoPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SonderSpacing.xs) {
                if let data = exportData {
                    ForEach(Array(data.allHeroImages.enumerated()), id: \.offset) { index, image in
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            customization.selectedHeroPhotoIndex = index
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay {
                                    if customization.selectedHeroPhotoIndex == index {
                                        Circle()
                                            .stroke(SonderColors.terracotta, lineWidth: 3)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo Picker

    private var photoPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SonderSpacing.xs) {
                if let data = exportData {
                    ForEach(Array(data.allAvailablePhotos.enumerated()), id: \.offset) { index, photoData in
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            if customization.selectedLogPhotoIndices.contains(index) {
                                customization.selectedLogPhotoIndices.remove(index)
                            } else {
                                customization.selectedLogPhotoIndices.insert(index)
                            }
                        } label: {
                            ZStack {
                                Image(uiImage: photoData.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())

                                if customization.selectedLogPhotoIndices.contains(index) {
                                    Circle()
                                        .fill(.black.opacity(0.3))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                if customization.selectedLogPhotoIndices.contains(index) {
                                    Circle()
                                        .stroke(SonderColors.terracotta, lineWidth: 3)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Caption Field

    private var captionField: some View {
        HStack {
            TextField("Add a caption...", text: $customization.customCaption)
                .font(SonderTypography.body)
                .onChange(of: customization.customCaption) {
                    if customization.customCaption.count > 100 {
                        customization.customCaption = String(customization.customCaption.prefix(100))
                    }
                }

            if !customization.customCaption.isEmpty {
                Text("\(customization.customCaption.count)/100")
                    .font(.system(size: 11))
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Zone 3: Action Bar

    private var actionBar: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Copy button
            Button {
                performExportAction(.copy)
            } label: {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SonderColors.inkDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }

            // Save button
            Button {
                performExportAction(.save)
            } label: {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "arrow.down.to.line")
                    Text("Save")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SonderColors.inkDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }

            // Share button (wider)
            Button {
                performExportAction(.share)
            } label: {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.sm)
                .background(SonderColors.terracotta)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SonderSpacing.lg)
        .padding(.vertical, SonderSpacing.md)
        .background(SonderColors.cream)
    }

    // MARK: - Toast Overlay

    private var toastOverlay: some View {
        Group {
            if let message = toastMessage {
                HStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(message)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, SonderSpacing.lg)
                .padding(.vertical, SonderSpacing.sm)
                .background(SonderColors.terracotta)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, SonderSpacing.xl)
            }
        }
        .animation(.spring(response: 0.3), value: toastMessage != nil)
    }

    // MARK: - Full Screen Preview

    private var fullScreenPreview: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let preview = previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullPreview = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }

    // MARK: - Canvas Builder

    @ViewBuilder
    private func selectedCanvas(data: TripExportData) -> some View {
        let theme = customization.theme
        let size = customization.canvasSize

        switch selectedStyle {
        case .collage:
            TripExportCollage(data: data, theme: theme, canvasSize: size)
        case .receipt:
            TripExportReceipt(data: data, theme: theme, canvasSize: size)
        case .cover:
            TripExportJournal(data: data, theme: theme, canvasSize: size)
        case .route:
            TripExportRouteMap(data: data, mapSnapshot: currentMapSnapshot, theme: theme, canvasSize: size)
        case .journey:
            TripExportJourney(data: data, theme: theme, canvasSize: size)
        }
    }

    private var currentMapSnapshot: UIImage? {
        let key = "\(Int(customization.canvasSize.width))x\(Int(customization.canvasSize.height))"
        return mapSnapshotCache[key] ?? mapSnapshot
    }

    // MARK: - Export Actions

    private enum ExportAction {
        case share, copy, save
    }

    private func performExportAction(_ action: ExportAction) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        guard var data = exportData else { return }
        data.customCaption = customization.customCaption.isEmpty ? nil : customization.customCaption

        let canvas = selectedCanvas(data: data)
            .frame(width: customization.canvasSize.width, height: customization.canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0

        guard let image = renderer.uiImage else { return }

        switch action {
        case .share:
            exportImage = image
            showShareSheet = true
        case .copy:
            UIPasteboard.general.image = image
            showToast("Copied!")
        case .save:
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            showToast("Saved!")
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                toastMessage = nil
            }
        }
    }

    // MARK: - Photo Loading

    private func loadPhotos() async {
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })

        let sortedLogs = tripLogs.sorted { a, b in
            let ratingOrder: [Rating: Int] = [.mustSee: 0, .solid: 1, .skip: 2]
            let aOrder = ratingOrder[a.rating] ?? 1
            let bOrder = ratingOrder[b.rating] ?? 1
            if aOrder != bOrder { return aOrder < bOrder }
            if let aSort = a.tripSortOrder, let bSort = b.tripSortOrder {
                return aSort < bSort
            }
            return a.visitedAt < b.visitedAt
        }

        // Collect ALL log photo URLs (not just 6)
        let allLogPhotoInfos: [(url: URL, placeName: String, rating: Rating, placeID: String, note: String?, tags: [String])] = sortedLogs.compactMap { log in
            let place = placesByID[log.placeID]
            let placeName = place?.name ?? "Unknown"
            let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? log.note : nil
            let tags = log.tags

            if let urlString = log.photoURL, let url = URL(string: urlString) {
                return (url, placeName, log.rating, log.placeID, note, tags)
            }
            if let place, let photoRef = place.photoReference,
               let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
                return (url, placeName, log.rating, log.placeID, note, tags)
            }
            return nil
        }

        // Collect hero image URLs (trip cover + all log photos as potential heroes)
        var heroURLs: [URL] = []
        if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
            heroURLs.append(url)
        }
        for info in allLogPhotoInfos {
            heroURLs.append(info.url)
        }

        // Download hero images
        let heroImages: [UIImage] = await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (idx, url) in heroURLs.prefix(10).enumerated() {
                group.addTask {
                    let image = await ImageDownsampler.downloadImage(from: url, targetSize: CGSize(width: 1080, height: 600))
                    return (idx, image)
                }
            }
            var indexed: [(Int, UIImage)] = []
            for await (idx, image) in group {
                if let image { indexed.append((idx, image)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        // Download all log photos
        let allLogPhotos: [LogPhotoData] = await withTaskGroup(of: (Int, LogPhotoData?).self) { group in
            for (idx, info) in allLogPhotoInfos.enumerated() {
                group.addTask {
                    guard let image = await ImageDownsampler.downloadImage(
                        from: info.url,
                        targetSize: CGSize(width: 500, height: 400)
                    ) else { return (idx, nil) }
                    return (idx, LogPhotoData(image: image, placeName: info.placeName, rating: info.rating, placeID: info.placeID, note: info.note, tags: info.tags))
                }
            }
            var indexed: [(Int, LogPhotoData)] = []
            for await (idx, data) in group {
                if let data { indexed.append((idx, data)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }

        // Build stops
        let chronologicalLogs = tripLogs.sorted {
            if let a = $0.tripSortOrder, let b = $1.tripSortOrder {
                return a < b
            }
            return $0.visitedAt < $1.visitedAt
        }
        let stops: [ExportStop] = chronologicalLogs.compactMap { log in
            guard let place = placesByID[log.placeID] else { return nil }
            let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? log.note : nil
            return ExportStop(placeName: place.name, coordinate: place.coordinate, rating: log.rating, placeID: log.placeID, note: note, tags: log.tags)
        }

        // Build stop-aligned photos for the map (match photos to stops by placeID)
        let photosByPlace = Dictionary(allLogPhotos.map { ($0.placeID, $0) }, uniquingKeysWith: { first, _ in first })
        let mapPhotos: [LogPhotoData] = stops.map { stop in
            photosByPlace[stop.placeID] ?? LogPhotoData(image: UIImage(), placeName: stop.placeName, rating: stop.rating, placeID: stop.placeID)
        }

        // Generate map snapshot
        let map = await TripMapSnapshotGenerator.generateSnapshot(
            stops: stops,
            logPhotos: mapPhotos
        )

        // Compute stats
        let dayCount: Int = {
            if let start = trip.startDate, let end = trip.endDate {
                let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
                return max(1, days + 1)
            }
            return max(1, Set(tripLogs.map { Calendar.current.startOfDay(for: $0.createdAt) }).count)
        }()

        let ratingCounts = (
            mustSee: tripLogs.filter { $0.rating == .mustSee }.count,
            solid: tripLogs.filter { $0.rating == .solid }.count,
            skip: tripLogs.filter { $0.rating == .skip }.count
        )

        var tagFrequency: [String: Int] = [:]
        for log in tripLogs {
            for tag in log.tags {
                tagFrequency[tag, default: 0] += 1
            }
        }
        let topTags = tagFrequency.sorted { $0.value > $1.value }.prefix(4).map(\.key)

        // Build category breakdown from Place.types
        let categoryEmojis: [ExploreMapFilter.CategoryFilter: String] = [
            .food: "🍴", .coffee: "☕", .nightlife: "🌙",
            .outdoors: "🌿", .shopping: "🛍", .attractions: "🏛"
        ]
        var categoryCounts: [ExploreMapFilter.CategoryFilter: Int] = [:]
        for log in tripLogs {
            guard let place = placesByID[log.placeID] else { continue }
            let placeTypeSet = Set(place.types)
            for category in ExploreMapFilter.CategoryFilter.allCases {
                if !category.placeTypes.isDisjoint(with: placeTypeSet) {
                    categoryCounts[category, default: 0] += 1
                    break // each log counts toward one category only
                }
            }
        }
        let categoryBreakdown = categoryCounts
            .sorted { $0.value > $1.value }
            .map { (emoji: categoryEmojis[$0.key] ?? "📍", label: $0.key.label, count: $0.value) }

        // Pick best mustSee quote
        let bestQuote: (text: String, placeName: String)? = {
            let mustSeeLogs = tripLogs.filter { $0.rating == .mustSee }
            for log in mustSeeLogs {
                if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    let placeName = placesByID[log.placeID]?.name ?? "Unknown"
                    return (text: note, placeName: placeName)
                }
            }
            // Fall back to any log with a note
            for log in tripLogs {
                if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    let placeName = placesByID[log.placeID]?.name ?? "Unknown"
                    return (text: note, placeName: placeName)
                }
            }
            return nil
        }()

        let dateRangeText: String? = {
            if let start = trip.startDate, let end = trip.endDate {
                return "\(Self.mediumDateFormatter.string(from: start)) \u{2013} \(Self.mediumDateFormatter.string(from: end))"
            } else if let start = trip.startDate {
                return "From \(Self.mediumDateFormatter.string(from: start))"
            } else if let end = trip.endDate {
                return "Until \(Self.mediumDateFormatter.string(from: end))"
            }
            return nil
        }()

        // Default selection: first 6 photos
        let defaultIndices = Set(Array(0..<min(6, allLogPhotos.count)))

        await MainActor.run {
            self.exportData = TripExportData(
                tripName: trip.name,
                tripDescription: trip.tripDescription,
                dateRangeText: dateRangeText,
                placeCount: tripLogs.count,
                dayCount: dayCount,
                ratingCounts: ratingCounts,
                topTags: topTags,
                heroImage: heroImages.first,
                logPhotos: Array(allLogPhotos.prefix(6)),
                stops: stops,
                customCaption: nil,
                allAvailablePhotos: allLogPhotos,
                allHeroImages: heroImages,
                categoryBreakdown: categoryBreakdown,
                bestQuote: bestQuote
            )
            self.mapSnapshot = map
            if let map {
                let key = "1080x1920"
                self.mapSnapshotCache[key] = map
            }
            self.customization.selectedLogPhotoIndices = defaultIndices
            self.isLoadingPhotos = false
            self.renderPreview()
        }
    }

    // MARK: - Preview Rendering

    private func schedulePreviewRender() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                renderPreview()
            }
        }
    }

    private func debounceCaptionRender() {
        captionDebounceTask?.cancel()
        captionDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                renderPreview()
            }
        }
    }

    private func renderPreview() {
        guard var data = exportData else { return }
        data.customCaption = customization.customCaption.isEmpty ? nil : customization.customCaption

        let canvas = selectedCanvas(data: data)
            .frame(width: customization.canvasSize.width, height: customization.canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0

        previewImage = renderer.uiImage
    }

    private func updateHeroPhoto() {
        guard var data = exportData else { return }
        let idx = customization.selectedHeroPhotoIndex
        if idx < data.allHeroImages.count {
            data.heroImage = data.allHeroImages[idx]
            exportData = data
        }
    }

    private func updateSelectedPhotos() {
        guard var data = exportData else { return }
        let indices = customization.selectedLogPhotoIndices.sorted()
        data.logPhotos = indices.compactMap { idx in
            idx < data.allAvailablePhotos.count ? data.allAvailablePhotos[idx] : nil
        }
        exportData = data
    }
}
