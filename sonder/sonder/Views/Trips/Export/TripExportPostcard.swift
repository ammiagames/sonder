//
//  TripExportPostcard.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI

/// Style 2: Highlight Reel — dynamic photo mosaic with bold overlaid text.
/// 1 large hero photo + 2 side-by-side below, filling ~70% of canvas.
/// Rendered at 1080x1920 for Instagram Stories.
struct TripExportPostcard: View {
    let data: TripExportData

    private let photoMargin: CGFloat = 40
    private let photoGap: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            // Photo mosaic section
            photoMosaic

            Spacer(minLength: 16)

            // Ratings row
            ratingsRow
                .padding(.horizontal, photoMargin)

            Spacer(minLength: 12)

            // Stats
            Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places") \u{00B7} \(data.dayCount) \(data.dayCount == 1 ? "day" : "days")")
                .font(.system(size: 36))
                .foregroundColor(SonderColors.inkMuted)

            Spacer(minLength: 16)

            // Footer
            HStack {
                Spacer()
                Text("sonder")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta) +
                Text("  \u{00B7}  your travel story")
                    .font(.system(size: 24))
                    .foregroundColor(SonderColors.inkLight)
                Spacer()
            }
            .padding(.bottom, 40)
        }
        .frame(width: 1080, height: 1920)
        .background(SonderColors.cream)
    }

    // MARK: - Photo Mosaic

    private var photoMosaic: some View {
        let photos = Array(data.logPhotos.prefix(3))
        let contentWidth = 1080 - photoMargin * 2
        let halfWidth = (contentWidth - photoGap) / 2

        return VStack(spacing: 0) {
            // Top photo with overlaid trip info
            ZStack(alignment: .topLeading) {
                photoOrPlaceholder(index: 0, photos: photos, width: contentWidth, height: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Top gradient for text legibility
                VStack {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.7), location: 0),
                            .init(color: .black.opacity(0.3), location: 0.6),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)

                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Text overlay
                VStack(alignment: .leading, spacing: 8) {
                    Text("sonder")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(SonderColors.terracotta)
                        .tracking(2)

                    Text(data.tripName)
                        .font(.system(size: 88, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    if let dateText = data.dateRangeText {
                        Text(dateText)
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(32)

                // Place name overlay at bottom-right of photo 1
                if let first = photos.first {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            placeLabel(name: first.placeName, rating: first.rating)
                                .padding(16)
                        }
                    }
                }
            }
            .frame(width: contentWidth, height: 640)

            // Gap
            Color.clear.frame(height: photoGap)

            // Bottom two photos side by side
            HStack(spacing: photoGap) {
                ZStack(alignment: .bottom) {
                    photoOrPlaceholder(index: 1, photos: photos, width: halfWidth, height: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if photos.count > 1 {
                        HStack {
                            placeLabel(name: photos[1].placeName, rating: photos[1].rating)
                                .padding(12)
                            Spacer()
                        }
                    }
                }
                .frame(width: halfWidth, height: 520)

                ZStack(alignment: .bottom) {
                    photoOrPlaceholder(index: 2, photos: photos, width: halfWidth, height: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if photos.count > 2 {
                        HStack {
                            placeLabel(name: photos[2].placeName, rating: photos[2].rating)
                                .padding(12)
                            Spacer()
                        }
                    }
                }
                .frame(width: halfWidth, height: 520)
            }
        }
        .padding(.horizontal, photoMargin)
        .padding(.top, 40)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func photoOrPlaceholder(index: Int, photos: [LogPhotoData], width: CGFloat, height: CGFloat) -> some View {
        if index < photos.count {
            Image(uiImage: photos[index].image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        } else {
            LinearGradient(
                colors: [SonderColors.terracotta.opacity(0.15), SonderColors.ochre.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundColor(SonderColors.terracotta.opacity(0.3))
            }
        }
    }

    private func placeLabel(name: String, rating: Rating) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)
            Text(rating.emoji)
                .font(.system(size: 32))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45))
        .clipShape(Capsule())
    }

    // MARK: - Ratings Row

    private var ratingsRow: some View {
        HStack(spacing: 32) {
            if data.ratingCounts.mustSee > 0 {
                HStack(spacing: 8) {
                    Text(Rating.mustSee.emoji)
                        .font(.system(size: 56))
                    Text("\(data.ratingCounts.mustSee)")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                }
            }
            if data.ratingCounts.solid > 0 {
                HStack(spacing: 8) {
                    Text(Rating.solid.emoji)
                        .font(.system(size: 56))
                    Text("\(data.ratingCounts.solid)")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                }
            }
            if data.ratingCounts.skip > 0 {
                HStack(spacing: 8) {
                    Text(Rating.skip.emoji)
                        .font(.system(size: 56))
                    Text("\(data.ratingCounts.skip)")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
