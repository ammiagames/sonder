//
//  TripExportCollage.swift
//  sonder
//
//  Asymmetric photo mosaic — one large hero, 2-3 supporting shots, minimal text.
//  The photos ARE the export. Think Pinterest board meets magazine spread.
//

import SwiftUI

struct TripExportCollage: View {
    let data: TripExportData
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }
    private var gap: CGFloat { 5 * s }

    private var photos: [UIImage] {
        var imgs: [UIImage] = []
        for p in data.logPhotos.prefix(5) { imgs.append(p.image) }
        if imgs.isEmpty, let hero = data.heroImage { imgs.append(hero) }
        return imgs
    }

    private var gridHeight: CGFloat { canvasSize.height * 0.62 }

    var body: some View {
        ZStack {
            theme.background

            VStack(spacing: 0) {
                // Photo mosaic — edge-to-edge, no padding
                photoGrid
                    .frame(width: canvasSize.width, height: gridHeight)
                    .clipped()

                // Info section
                infoSection
            }

            // Film grain
            FilmGrainOverlay(opacity: 0.02, seed: data.tripName.hashValue)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: - Photo Grid

    @ViewBuilder
    private var photoGrid: some View {
        let count = photos.count
        if count >= 4 {
            fourPlusLayout
        } else if count == 3 {
            threeLayout
        } else if count == 2 {
            twoLayout
        } else if count == 1 {
            singleLayout
        } else {
            gradientPlaceholder
        }
    }

    // Large left (60%) + 3 stacked right (40%)
    private var fourPlusLayout: some View {
        HStack(spacing: gap) {
            photoCell(photos[0])
                .frame(width: canvasSize.width * 0.58 - gap / 2)
            VStack(spacing: gap) {
                photoCell(photos[1])
                photoCell(photos[2])
                photoCell(photos[3])
            }
            .frame(width: canvasSize.width * 0.42 - gap / 2)
        }
    }

    // Large left (58%) + 2 stacked right (42%)
    private var threeLayout: some View {
        HStack(spacing: gap) {
            photoCell(photos[0])
                .frame(width: canvasSize.width * 0.58 - gap / 2)
            VStack(spacing: gap) {
                photoCell(photos[1])
                photoCell(photos[2])
            }
            .frame(width: canvasSize.width * 0.42 - gap / 2)
        }
    }

    // Two side by side, slightly asymmetric
    private var twoLayout: some View {
        HStack(spacing: gap) {
            photoCell(photos[0])
                .frame(width: canvasSize.width * 0.55 - gap / 2)
            photoCell(photos[1])
                .frame(width: canvasSize.width * 0.45 - gap / 2)
        }
    }

    // Single photo, full bleed in grid area
    private var singleLayout: some View {
        photoCell(photos[0])
    }

    private func photoCell(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var gradientPlaceholder: some View {
        LinearGradient(
            colors: [theme.accent.opacity(0.6), theme.accent.opacity(0.2), theme.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thin accent line as divider
            Rectangle()
                .fill(theme.accent)
                .frame(width: 52 * s, height: 4 * s)
                .padding(.top, 44 * s)
                .padding(.bottom, 28 * s)

            // Trip name
            Text(data.tripName)
                .font(.system(size: 74 * s, weight: .bold, design: .serif))
                .foregroundColor(theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)

            Spacer().frame(height: 16 * s)

            // Date + stats
            HStack(spacing: 10 * s) {
                if let dateText = data.dateRangeText {
                    Text(dateText)
                    Text("\u{00B7}")
                }
                Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
                Text("\u{00B7}")
                Text("\(data.dayCount) \(data.dayCount == 1 ? "day" : "days")")
            }
            .font(.system(size: 28 * s))
            .foregroundColor(theme.textSecondary)

            Spacer().frame(height: 24 * s)

            // Ratings
            HStack(spacing: 24 * s) {
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
            .font(.system(size: 32 * s))
            .foregroundColor(theme.textSecondary.opacity(0.85))

            // Pull quote
            if let quote = data.bestQuote {
                Spacer().frame(height: 24 * s)
                Text("\u{201C}\(quote.text)\u{201D}")
                    .font(.system(size: 28 * s, design: .serif))
                    .italic()
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }

            // Caption
            if let caption = data.customCaption, !caption.isEmpty {
                Spacer().frame(height: 16 * s)
                Text(caption)
                    .font(.system(size: 26 * s, design: .serif))
                    .italic()
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Footer
            HStack {
                Text("sonder")
                    .font(.system(size: 24 * s, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.accent)
                Spacer()
            }
            .padding(.bottom, 44 * s)
        }
        .padding(.horizontal, 56 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
