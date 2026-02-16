//
//  TripExportJournal.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI

/// Style 1: Magazine Cover — full-bleed hero photo with bold serif overlay.
/// Rendered at 1080x1920 for Instagram Stories.
struct TripExportJournal: View {
    let data: TripExportData

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed hero photo (entire canvas)
            heroBackground

            // Heavy bottom gradient + overlaid content
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Gradient overlay region (~45% of canvas)
                VStack(alignment: .leading, spacing: 20) {
                    // Brand mark
                    Text("sonder")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(SonderColors.terracotta)
                        .tracking(2)

                    // Trip name — huge serif
                    Text(data.tripName)
                        .font(.system(size: 100, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)

                    // Stats line
                    statsLine

                    // Rating counts
                    ratingsRow

                    // Photo thumbnails
                    if !data.logPhotos.isEmpty {
                        photoThumbnails
                    }

                    // Footer
                    HStack {
                        Spacer()
                        Text("sonder")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5)) +
                        Text("  \u{00B7}  your travel story")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 48)
            }
            .background(alignment: .bottom) {
                // Heavy gradient from clear to black 0.85
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.3), location: 0.25),
                        .init(color: .black.opacity(0.65), location: 0.55),
                        .init(color: .black.opacity(0.85), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 860)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: 1080, height: 1920)
        .clipped()
    }

    // MARK: - Hero Background

    private var heroBackground: some View {
        Group {
            if let hero = data.heroImage {
                Image(uiImage: hero)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 1080, height: 1920)
                    .clipped()
            } else {
                // No-photo fallback: warm gradient
                LinearGradient(
                    colors: [
                        SonderColors.terracotta,
                        SonderColors.ochre,
                        SonderColors.warmGrayDark,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Stats Line

    private var statsLine: some View {
        HStack(spacing: 12) {
            if let dateText = data.dateRangeText {
                Text(dateText)
                Text("\u{00B7}")
            }
            Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
            Text("\u{00B7}")
            Text("\(data.dayCount)\(data.dayCount == 1 ? "d" : "d")")
        }
        .font(.system(size: 36))
        .foregroundColor(.white.opacity(0.8))
    }

    // MARK: - Ratings Row

    private var ratingsRow: some View {
        HStack(spacing: 24) {
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
        .font(.system(size: 40))
        .foregroundColor(.white.opacity(0.7))
    }

    // MARK: - Photo Thumbnails

    private var photoThumbnails: some View {
        let photos = Array(data.logPhotos.prefix(4))
        return HStack(spacing: 20) {
            ForEach(Array(photos.enumerated()), id: \.offset) { _, photoData in
                VStack(spacing: 8) {
                    Image(uiImage: photoData.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                        }

                    Text(photoData.placeName)
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .frame(width: 130)
                }
            }
        }
        .padding(.top, 8)
    }
}
