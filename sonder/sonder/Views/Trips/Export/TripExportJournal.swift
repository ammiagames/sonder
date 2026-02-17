//
//  TripExportJournal.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI

/// Style 1: The Editorial Spread — magazine-style hero photo with rich info section below.
struct TripExportJournal: View {
    let data: TripExportData
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Hero photo — top ~55%
            heroBackground

            // Editorial section — bottom ~45%
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 18 * s) {
                    // Brand mark
                    Text("sonder")
                        .font(.system(size: 32 * s, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accent)
                        .tracking(2)

                    // Trip name
                    Text(data.tripName)
                        .font(.system(size: 90 * s, weight: .bold, design: .serif))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    // Date range + place count
                    statsLine

                    // Pull quote — the bragging rights moment
                    if let quote = data.bestQuote {
                        pullQuoteView(quote)
                    }

                    // Category breakdown pills
                    if !data.categoryBreakdown.isEmpty {
                        categoryPills
                    }

                    // Highlight reel — circular photos
                    if !data.logPhotos.isEmpty {
                        photoThumbnails
                    }

                    // Rating summary
                    ratingsRow

                    // Caption
                    if let caption = data.customCaption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 26 * s, design: .serif))
                            .italic()
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(2)
                    }

                    // Footer
                    HStack {
                        Spacer()
                        Text("sonder")
                            .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.textTertiary) +
                        Text("  \u{00B7}  your travel story")
                            .font(.system(size: 22 * s))
                            .foregroundColor(theme.textTertiary)
                        Spacer()
                    }
                    .padding(.top, 4 * s)
                }
                .padding(.horizontal, 56 * s)
                .padding(.bottom, 40 * s)
            }
            .background(alignment: .bottom) {
                LinearGradient(
                    stops: theme.overlayGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 920 * s)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: - Hero Background

    private var heroBackground: some View {
        Group {
            if let hero = data.heroImage {
                ZStack(alignment: .bottom) {
                    Image(uiImage: hero)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .clipped()

                    // Subtle vignette at bottom edge of hero
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.15), location: 1.0),
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: canvasSize.height * 0.55)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } else {
                LinearGradient(
                    colors: [theme.accent, theme.accent.opacity(0.6), theme.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Stats Line

    private var statsLine: some View {
        HStack(spacing: 12 * s) {
            if let dateText = data.dateRangeText {
                Text(dateText)
                Text("\u{00B7}")
            }
            Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
            Text("\u{00B7}")
            Text("\(data.dayCount)d")
        }
        .font(.system(size: 32 * s))
        .foregroundColor(theme.textSecondary)
    }

    // MARK: - Pull Quote

    private func pullQuoteView(_ quote: (text: String, placeName: String)) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text("\u{201C}\(quote.text)\u{201D}")
                .font(.system(size: 34 * s, design: .serif))
                .italic()
                .foregroundColor(theme.textPrimary)
                .lineLimit(3)

            Text("— \(quote.placeName)")
                .font(.system(size: 24 * s, weight: .medium))
                .foregroundColor(theme.accent)
        }
        .padding(.vertical, 8 * s)
    }

    // MARK: - Category Pills

    private var categoryPills: some View {
        let items = Array(data.categoryBreakdown.prefix(4))
        return HStack(spacing: 10 * s) {
            ForEach(0..<items.count, id: \.self) { index in
                let cat = items[index]
                HStack(spacing: 6 * s) {
                    Text(cat.emoji)
                        .font(.system(size: 22 * s))
                    Text("\(cat.label) \u{00D7} \(cat.count)")
                        .font(.system(size: 22 * s, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                }
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 8 * s)
                .background(theme.accent.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Ratings Row

    private var ratingsRow: some View {
        HStack(spacing: 24 * s) {
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
        .font(.system(size: 36 * s))
        .foregroundColor(theme.textSecondary.opacity(0.85))
    }

    // MARK: - Photo Thumbnails

    private var photoThumbnails: some View {
        let photos = Array(data.logPhotos.prefix(4))
        let thumbSize: CGFloat = 100 * s
        return HStack(spacing: 18 * s) {
            ForEach(0..<photos.count, id: \.self) { index in
                VStack(spacing: 6 * s) {
                    Image(uiImage: photos[index].image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbSize, height: thumbSize)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(theme.textPrimary.opacity(0.6), lineWidth: 3 * s)
                        }

                    Text(photos[index].placeName)
                        .font(.system(size: 20 * s))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                        .frame(width: 120 * s)
                }
            }
        }
    }
}
