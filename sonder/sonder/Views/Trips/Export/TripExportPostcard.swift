//
//  TripExportPostcard.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI

/// Style 3: The Timeline Chronicle — vertical timeline with alternating photo cards and notes.
struct TripExportJourney: View {
    let data: TripExportData
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }

    private var maxStops: Int {
        switch canvasSize.height {
        case 1920: return 7
        case 1350: return 5
        default: return 3
        }
    }

    private var stops: [ExportStop] { Array(data.stops.prefix(maxStops)) }

    /// Photos aligned to stops by placeID.
    private var stopPhotos: [LogPhotoData?] {
        let photosByPlace = Dictionary(
            data.allAvailablePhotos.map { ($0.placeID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return stops.map { stop in
            if !stop.placeID.isEmpty {
                return photosByPlace[stop.placeID]
            }
            return nil
        }
    }

    private var timelineX: CGFloat { 80 * s }
    private var cardWidth: CGFloat { canvasSize.width - timelineX - 80 * s }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Rich layered background
            background

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 56 * s)
                    .padding(.top, 50 * s)

                // Timeline
                ZStack(alignment: .topLeading) {
                    // Vertical accent line
                    Rectangle()
                        .fill(theme.accent.opacity(0.3))
                        .frame(width: 3 * s)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, timelineX)
                        .padding(.top, 10 * s)

                    // Stop cards
                    VStack(alignment: .leading, spacing: 16 * s) {
                        ForEach(0..<stops.count, id: \.self) { index in
                            timelineCard(index: index)
                        }

                        // "+N more stops" indicator
                        if data.stops.count > maxStops {
                            HStack(spacing: 10 * s) {
                                // Timeline dot
                                Circle()
                                    .fill(theme.accent.opacity(0.4))
                                    .frame(width: 12 * s, height: 12 * s)
                                    .padding(.leading, timelineX - 6 * s)

                                Text("+\(data.stops.count - maxStops) more stops")
                                    .font(.system(size: 24 * s))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                    .padding(.top, 20 * s)
                }

                Spacer()

                // Bottom section
                bottomSection
                    .padding(.horizontal, 56 * s)
                    .padding(.bottom, 40 * s)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text("sonder")
                .font(.system(size: 28 * s, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.accent)
                .tracking(2)

            Text(data.tripName)
                .font(.system(size: 56 * s, weight: .bold, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)

            HStack(spacing: 8 * s) {
                if let dateText = data.dateRangeText {
                    Text(dateText)
                }
                if data.placeCount > 0 {
                    Text("\u{00B7}")
                    Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
                }
            }
            .font(.system(size: 26 * s))
            .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Timeline Card

    @ViewBuilder
    private func timelineCard(index: Int) -> some View {
        let stop = stops[index]
        let photo = index < stopPhotos.count ? stopPhotos[index] : nil

        HStack(alignment: .top, spacing: 0) {
            // Timeline dot
            Circle()
                .fill(theme.accent)
                .frame(width: 12 * s, height: 12 * s)
                .padding(.leading, timelineX - 6 * s)
                .padding(.top, 8 * s)

            // Card content
            VStack(alignment: .leading, spacing: 0) {
                if let photo {
                    // Photo card
                    ZStack(alignment: .bottomLeading) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth - 20 * s, height: 160 * s)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8 * s))

                        // Place name overlay
                        HStack(spacing: 6 * s) {
                            Text(stop.placeName)
                                .font(.system(size: 22 * s, weight: .semibold))
                                .lineLimit(1)
                            Text(stop.rating.emoji)
                                .font(.system(size: 20 * s))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 6 * s)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(8 * s)
                    }
                } else {
                    // Text-only card
                    HStack(spacing: 6 * s) {
                        Text(stop.placeName)
                            .font(.system(size: 24 * s, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(stop.rating.emoji)
                            .font(.system(size: 22 * s))
                    }
                    .padding(.horizontal, 14 * s)
                    .padding(.vertical, 10 * s)
                    .background(theme.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * s))
                }

                // Note below card
                if let note = stop.note, !note.isEmpty {
                    Text("\u{201C}\(note)\u{201D}")
                        .font(.system(size: 20 * s, design: .serif))
                        .italic()
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 6 * s)
                        .padding(.horizontal, 4 * s)
                }

                // Tags
                if !stop.tags.isEmpty {
                    HStack(spacing: 6 * s) {
                        ForEach(Array(stop.tags.prefix(3)), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 16 * s, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 8 * s)
                                .padding(.vertical, 3 * s)
                                .background(theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4 * s)
                    .padding(.horizontal, 4 * s)
                }
            }
            .padding(.leading, 16 * s)
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            theme.background

            RadialGradient(
                colors: [
                    theme.accent.opacity(0.08),
                    theme.accent.opacity(0.03),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: canvasSize.height * 0.7
            )

            RadialGradient(
                colors: [
                    theme.backgroundSecondary.opacity(0.5),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: canvasSize.height * 0.5
            )
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            // Category breakdown pills
            if !data.categoryBreakdown.isEmpty {
                let items = Array(data.categoryBreakdown.prefix(4))
                HStack(spacing: 8 * s) {
                    ForEach(0..<items.count, id: \.self) { index in
                        let cat = items[index]
                        HStack(spacing: 4 * s) {
                            Text(cat.emoji)
                                .font(.system(size: 20 * s))
                            Text("\(cat.label) \u{00D7} \(cat.count)")
                                .font(.system(size: 20 * s, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                        }
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 6 * s)
                        .background(theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            // Rating summary
            HStack(spacing: 20 * s) {
                if data.ratingCounts.mustSee > 0 {
                    Text("\(Rating.mustSee.emoji) \(data.ratingCounts.mustSee)")
                }
                if data.ratingCounts.solid > 0 {
                    Text("\(Rating.solid.emoji) \(data.ratingCounts.solid)")
                }
                if data.ratingCounts.skip > 0 {
                    Text("\(Rating.skip.emoji) \(data.ratingCounts.skip)")
                }
            }
            .font(.system(size: 30 * s))
            .foregroundStyle(theme.textSecondary.opacity(0.85))

            // Caption
            if let caption = data.customCaption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 24 * s, design: .serif))
                    .italic()
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            // Footer
            HStack {
                Spacer()
                Text("sonder")
                    .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textTertiary) +
                Text("  \u{00B7}  your travel story")
                    .font(.system(size: 22 * s))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }
            .padding(.top, 4 * s)
        }
    }
}

// MARK: - Journey Path Shape (kept for potential future use)

struct JourneyPathShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        path.move(to: points[0])

        for i in 1..<points.count {
            let from = points[i - 1]
            let to = points[i]
            let midY = (from.y + to.y) / 2

            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x, y: midY),
                control2: CGPoint(x: to.x, y: midY)
            )
        }

        return path
    }
}
