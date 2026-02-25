//
//  TripExportPDFRenderer.swift
//  sonder
//
//  Multi-page PDF guidebook: cover page, map overview, and stop detail pages.
//  Phone-friendly 1080x1920 (9:16) format. Theme-aware.
//

import SwiftUI
import UIKit

enum TripExportPDFRenderer {

    static let pageSize = CGSize(width: 1080, height: 1920)
    private static let stopsPerPage = 3

    // MARK: - Public API

    /// Renders a multi-page PDF and returns a temporary file URL.
    @MainActor
    static func renderPDF(
        data: TripExportData,
        theme: ExportColorTheme,
        mapSnapshot: UIImage?
    ) -> URL? {
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let sanitizedName = data.tripName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = sanitizedName.isEmpty ? "Trip-Guidebook" : "\(sanitizedName)-Guidebook"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).pdf")

        do {
            let pdfData = renderer.pdfData { context in
                // Page 1: Cover
                context.beginPage()
                renderPage(PDFCoverPage(data: data, theme: theme), in: context, size: pageSize)

                // Page 2: Map (if stops exist and map available)
                if !data.stops.isEmpty {
                    context.beginPage()
                    renderPage(PDFMapPage(data: data, theme: theme, mapSnapshot: mapSnapshot), in: context, size: pageSize)
                }

                // Page 3+: Stop pages (3 per page)
                let chunks = stride(from: 0, to: data.stops.count, by: stopsPerPage).map { startIndex in
                    Array(data.stops[startIndex..<min(startIndex + stopsPerPage, data.stops.count)])
                }
                for (pageIndex, chunk) in chunks.enumerated() {
                    let startNumber = pageIndex * stopsPerPage + 1
                    context.beginPage()
                    renderPage(
                        PDFStopsPage(
                            stops: chunk,
                            startNumber: startNumber,
                            totalStops: data.stops.count,
                            stopAlignedPhotos: data.stopAlignedPhotos,
                            globalOffset: pageIndex * stopsPerPage,
                            theme: theme
                        ),
                        in: context,
                        size: pageSize
                    )
                }
            }

            try pdfData.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Renders a preview image of the cover page (for ShareTripView thumbnail).
    @MainActor
    static func renderCoverPreview(data: TripExportData, theme: ExportColorTheme) -> UIImage? {
        let view = PDFCoverPage(data: data, theme: theme)
            .frame(width: pageSize.width, height: pageSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        return renderer.uiImage
    }

    // MARK: - Helpers

    @MainActor
    private static func renderPage<V: View>(_ view: V, in context: UIGraphicsPDFRendererContext, size: CGSize) {
        let hostView = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hostView)
        renderer.scale = 1.0
        if let image = renderer.uiImage {
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Cover Page

private struct PDFCoverPage: View {
    let data: TripExportData
    let theme: ExportColorTheme

    var body: some View {
        ZStack {
            theme.background

            // Hero photo or gradient
            if let hero = data.heroImage {
                Image(uiImage: hero)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 1080, height: 1920)
                    .clipped()

                // Gradient overlay
                LinearGradient(
                    stops: theme.overlayGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 24) {
                    // Trip name
                    Text(data.tripName)
                        .font(.system(size: 80, weight: .bold, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)

                    // Date range
                    if let dateText = data.dateRangeText {
                        Text(dateText)
                            .font(.system(size: 32))
                            .foregroundStyle(theme.textSecondary)
                    }

                    // Stats row
                    HStack(spacing: 32) {
                        statPill("\(data.placeCount) places")
                        statPill("\(data.dayCount) days")
                    }

                    Spacer().frame(height: 20)

                    // Rating breakdown
                    HStack(spacing: 24) {
                        if data.ratingCounts.mustSee > 0 {
                            Text("\(Rating.mustSee.emoji) \(data.ratingCounts.mustSee)")
                        }
                        if data.ratingCounts.great > 0 {
                            Text("\(Rating.great.emoji) \(data.ratingCounts.great)")
                        }
                        if data.ratingCounts.okay > 0 {
                            Text("\(Rating.okay.emoji) \(data.ratingCounts.okay)")
                        }
                        if data.ratingCounts.skip > 0 {
                            Text("\(Rating.skip.emoji) \(data.ratingCounts.skip)")
                        }
                    }
                    .font(.system(size: 36))
                    .foregroundStyle(theme.textSecondary)

                    // Top tags
                    if !data.topTags.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(data.topTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(theme.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(theme.accent.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Spacer().frame(height: 24)

                    // Branding
                    HStack {
                        Spacer()
                        Text("\(Text("sonder").font(.system(size: 24, weight: .semibold, design: .rounded)))  \u{00B7}  your travel story")
                            .font(.system(size: 24))
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 72)
                .padding(.bottom, 64)
            }
        }
        .frame(width: 1080, height: 1920)
    }

    private func statPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(theme.backgroundSecondary.opacity(0.6))
            .clipShape(Capsule())
    }
}

// MARK: - Map Page

private struct PDFMapPage: View {
    let data: TripExportData
    let theme: ExportColorTheme
    let mapSnapshot: UIImage?

    var body: some View {
        ZStack {
            theme.background

            VStack(spacing: 0) {
                // Page title
                Text("Route Overview")
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 72)
                    .padding(.top, 72)

                Spacer().frame(height: 32)

                // Map
                if let snapshot = mapSnapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 936)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 72)
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(theme.backgroundSecondary)
                        .frame(height: 800)
                        .padding(.horizontal, 72)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "map")
                                    .font(.system(size: 48))
                                    .foregroundStyle(theme.textTertiary)
                                Text("Map unavailable")
                                    .font(.system(size: 24))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                }

                Spacer().frame(height: 40)

                // Stop legend
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(data.stops.enumerated()), id: \.offset) { index, stop in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(theme.background)
                                    .frame(width: 32, height: 32)
                                    .background(theme.accent)
                                    .clipShape(Circle())

                                Text(stop.placeName)
                                    .font(.system(size: 24))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)

                                Text(stop.rating.emoji)
                                    .font(.system(size: 22))
                            }
                        }
                    }
                    .padding(.horizontal, 72)
                }

                Spacer()
            }
        }
        .frame(width: 1080, height: 1920)
    }
}

// MARK: - Stops Page

private struct PDFStopsPage: View {
    let stops: [ExportStop]
    let startNumber: Int
    let totalStops: Int
    let stopAlignedPhotos: [LogPhotoData?]
    let globalOffset: Int
    let theme: ExportColorTheme

    var body: some View {
        ZStack {
            theme.background

            VStack(alignment: .leading, spacing: 0) {
                // Page header
                Text("Places \(startNumber)–\(startNumber + stops.count - 1) of \(totalStops)")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 72)
                    .padding(.top, 64)

                Spacer().frame(height: 32)

                // Stop cards
                ForEach(Array(stops.enumerated()), id: \.offset) { localIndex, stop in
                    let number = startNumber + localIndex
                    let photoIndex = globalOffset + localIndex
                    let photo = photoIndex < stopAlignedPhotos.count ? stopAlignedPhotos[photoIndex] : nil

                    stopCard(number: number, stop: stop, photo: photo)

                    if localIndex < stops.count - 1 {
                        Rectangle()
                            .fill(theme.textTertiary.opacity(0.2))
                            .frame(height: 1)
                            .padding(.horizontal, 72)
                            .padding(.vertical, 16)
                    }
                }

                Spacer()

                // Page footer
                HStack {
                    Spacer()
                    Text("\(Text("sonder").font(.system(size: 20, weight: .semibold, design: .rounded)))  \u{00B7}  your travel story")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
                .padding(.bottom, 48)
            }
        }
        .frame(width: 1080, height: 1920)
    }

    private func stopCard(number: Int, stop: ExportStop, photo: LogPhotoData?) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Photo (if available)
            if let photoData = photo {
                Image(uiImage: photoData.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            VStack(alignment: .leading, spacing: 10) {
                // Number + rating + name
                HStack(spacing: 10) {
                    Text("\(number).")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                    Text(stop.rating.emoji)
                        .font(.system(size: 30))
                    Text(stop.placeName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                }

                // Address
                if !stop.address.isEmpty {
                    Text(stop.address)
                        .font(.system(size: 24))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(2)
                }

                // Note
                if let note = stop.note, !note.isEmpty {
                    Text("\u{201C}\(note)\u{201D}")
                        .font(.system(size: 24, design: .serif))
                        .italic()
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(3)
                }

                // Tags
                if !stop.tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(stop.tags.prefix(4)), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Google Maps link
                if !stop.placeID.isEmpty {
                    Text("\u{1F5FA} maps/\(stop.placeID)")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 16)
    }
}
