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
    let heroImage: UIImage?
    let logPhotos: [LogPhotoData]
    let stops: [ExportStop]
}

struct LogPhotoData {
    let image: UIImage
    let placeName: String
    let rating: Rating
}

struct ExportStop {
    let placeName: String
    let coordinate: CLLocationCoordinate2D
    let rating: Rating
}

// MARK: - Export Style

enum ExportStyle: String, CaseIterable {
    case journal, postcard, routeMap

    var title: String {
        switch self {
        case .journal: return "Cover"
        case .postcard: return "Highlight"
        case .routeMap: return "Route Map"
        }
    }

    var icon: String {
        switch self {
        case .journal: return "book.pages"
        case .postcard: return "photo.on.rectangle.angled"
        case .routeMap: return "map"
        }
    }
}

// MARK: - ShareTripView

struct ShareTripView: View {
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    let tripLogs: [Log]
    let places: [Place]

    @State private var selectedStyle: ExportStyle = .journal
    @State private var exportData: TripExportData?
    @State private var isLoadingPhotos = true
    @State private var mapSnapshot: UIImage?
    @State private var exportImage: UIImage?
    @State private var showShareSheet = false

    private static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoadingPhotos {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                        Text("Preparing photos...")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    }
                    Spacer()
                } else {
                    // Preview
                    ScrollView {
                        previewSection
                            .padding(.top, SonderSpacing.md)
                    }

                    // Style picker + share button
                    bottomControls
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(SonderColors.inkMuted)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = exportImage {
                    ShareSheet(items: [image])
                }
            }
        }
        .task {
            await loadPhotos()
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Group {
            if let data = exportData {
                // Show a scaled-down preview of the current style
                selectedCanvas(data: data)
                    .frame(width: 1080, height: 1920)
                    .scaleEffect(x: previewScale, y: previewScale, anchor: .top)
                    .frame(
                        width: 1080 * previewScale,
                        height: 1920 * previewScale
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.horizontal, SonderSpacing.md)
            }
        }
    }

    private var previewScale: CGFloat {
        // Fit within roughly 340pt width
        340.0 / 1080.0
    }

    @ViewBuilder
    private func selectedCanvas(data: TripExportData) -> some View {
        switch selectedStyle {
        case .journal:
            TripExportJournal(data: data)
        case .postcard:
            TripExportPostcard(data: data)
        case .routeMap:
            TripExportRouteMap(data: data, mapSnapshot: mapSnapshot)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: SonderSpacing.md) {
            // Style picker
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                Text("Choose a style")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .padding(.horizontal, SonderSpacing.lg)

                HStack(spacing: SonderSpacing.md) {
                    ForEach(ExportStyle.allCases, id: \.rawValue) { style in
                        styleButton(style)
                    }
                }
                .padding(.horizontal, SonderSpacing.lg)
            }

            // Share button
            Button {
                generateExportImage()
            } label: {
                HStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Image")
                }
                .font(SonderTypography.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.md)
                .background(SonderColors.terracotta)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.bottom, SonderSpacing.lg)
        }
        .padding(.top, SonderSpacing.md)
        .background(SonderColors.cream)
    }

    private func styleButton(_ style: ExportStyle) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedStyle = style
            }
        } label: {
            VStack(spacing: SonderSpacing.xs) {
                Image(systemName: style.icon)
                    .font(.system(size: 22))
                Text(style.title)
                    .font(SonderTypography.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.sm)
            .background(selectedStyle == style ? SonderColors.terracotta.opacity(0.12) : SonderColors.warmGray)
            .foregroundColor(selectedStyle == style ? SonderColors.terracotta : SonderColors.inkMuted)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .overlay {
                if selectedStyle == style {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                        .stroke(SonderColors.terracotta, lineWidth: 2)
                }
            }
        }
    }

    // MARK: - Photo Loading

    private func loadPhotos() async {
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })

        // Sort logs: mustSee first, then solid, then skip; within each tier by date
        let sortedLogs = tripLogs.sorted { a, b in
            let ratingOrder: [Rating: Int] = [.mustSee: 0, .solid: 1, .skip: 2]
            let aOrder = ratingOrder[a.rating] ?? 1
            let bOrder = ratingOrder[b.rating] ?? 1
            if aOrder != bOrder { return aOrder < bOrder }
            return a.createdAt < b.createdAt
        }

        // Determine hero image URL
        let heroURL: URL? = {
            if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
                return url
            }
            // Fall back to first log photo
            for log in sortedLogs {
                if let urlString = log.photoURL, let url = URL(string: urlString) {
                    return url
                }
                if let place = placesByID[log.placeID],
                   let photoRef = place.photoReference,
                   let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
                    return url
                }
            }
            return nil
        }()

        // Download hero and log photos in parallel
        async let heroTask: UIImage? = {
            guard let url = heroURL else { return nil }
            return await ImageDownsampler.downloadImage(from: url, targetSize: CGSize(width: 1080, height: 600))
        }()

        // Collect log photo URLs (up to 6)
        let logPhotoInfos: [(url: URL, placeName: String, rating: Rating)] = sortedLogs.prefix(6).compactMap { log in
            let place = placesByID[log.placeID]
            let placeName = place?.name ?? "Unknown"

            if let urlString = log.photoURL, let url = URL(string: urlString) {
                return (url, placeName, log.rating)
            }
            if let place, let photoRef = place.photoReference,
               let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
                return (url, placeName, log.rating)
            }
            return nil
        }

        async let logPhotosTask: [LogPhotoData] = {
            var results: [LogPhotoData] = []
            await withTaskGroup(of: (Int, LogPhotoData?).self) { group in
                for (idx, info) in logPhotoInfos.enumerated() {
                    group.addTask {
                        guard let image = await ImageDownsampler.downloadImage(
                            from: info.url,
                            targetSize: CGSize(width: 500, height: 400)
                        ) else { return (idx, nil) }
                        return (idx, LogPhotoData(image: image, placeName: info.placeName, rating: info.rating))
                    }
                }
                var indexed: [(Int, LogPhotoData)] = []
                for await (idx, data) in group {
                    if let data { indexed.append((idx, data)) }
                }
                results = indexed.sorted { $0.0 < $1.0 }.map(\.1)
            }
            return results
        }()

        // Build stops for route map
        let chronologicalLogs = tripLogs.sorted { $0.createdAt < $1.createdAt }
        let stops: [ExportStop] = chronologicalLogs.compactMap { log in
            guard let place = placesByID[log.placeID] else { return nil }
            return ExportStop(placeName: place.name, coordinate: place.coordinate, rating: log.rating)
        }

        // Await hero and log photos first
        let hero = await heroTask
        let logPhotos = await logPhotosTask

        // Generate map snapshot (needs logPhotos for photo circles)
        let map = await TripMapSnapshotGenerator.generateSnapshot(
            stops: stops,
            logPhotos: logPhotos
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

        // Compute top tags
        var tagFrequency: [String: Int] = [:]
        for log in tripLogs {
            for tag in log.tags {
                tagFrequency[tag, default: 0] += 1
            }
        }
        let topTags = tagFrequency.sorted { $0.value > $1.value }.prefix(4).map(\.key)

        // Date range text
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

        await MainActor.run {
            self.exportData = TripExportData(
                tripName: trip.name,
                tripDescription: trip.tripDescription,
                dateRangeText: dateRangeText,
                placeCount: tripLogs.count,
                dayCount: dayCount,
                ratingCounts: ratingCounts,
                topTags: topTags,
                heroImage: hero,
                logPhotos: logPhotos,
                stops: stops
            )
            self.mapSnapshot = map
            self.isLoadingPhotos = false
        }
    }

    // MARK: - Export Image Generation

    private func generateExportImage() {
        guard let data = exportData else { return }

        let canvas = selectedCanvas(data: data)
            .frame(width: 1080, height: 1920)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0 // Canvas is already at pixel dimensions

        if let image = renderer.uiImage {
            exportImage = image
            showShareSheet = true
        }
    }
}
