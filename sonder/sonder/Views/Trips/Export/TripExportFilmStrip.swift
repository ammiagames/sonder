//
//  TripExportFilmStrip.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Style 4: The Photo Essay — masonry-style photo grid with editorial captions.
struct TripExportFilmStrip: View {
    let data: TripExportData
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }

    private var photoCount: Int {
        switch canvasSize.height {
        case 1920: return 6
        case 1350: return 4
        default: return 3
        }
    }

    private var photos: [LogPhotoData] { Array(data.logPhotos.prefix(photoCount)) }

    var body: some View {
        ZStack {
            theme.background

            VStack(alignment: .leading, spacing: 0) {
                // Title bar
                titleBar
                    .padding(.horizontal, 56 * s)
                    .padding(.top, 50 * s)
                    .padding(.bottom, 24 * s)

                // Masonry photo grid
                masonryGrid
                    .padding(.horizontal, 40 * s)

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

    // MARK: - Title Bar

    private var titleBar: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text("sonder")
                .font(.system(size: 26 * s, weight: .semibold, design: .rounded))
                .foregroundColor(theme.accent)
                .tracking(2)

            Text(data.tripName)
                .font(.system(size: 60 * s, weight: .bold, design: .serif))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(spacing: 8 * s) {
                if let dateText = data.dateRangeText {
                    Text(dateText)
                }
                Text("\u{00B7}")
                Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
            }
            .font(.system(size: 26 * s))
            .foregroundColor(theme.textSecondary)
        }
    }

    // MARK: - Masonry Grid

    private var masonryGrid: some View {
        let columnWidth = (canvasSize.width - 80 * s - 16 * s) / 2 // 40px padding each side, 16px gap
        let tallHeight: CGFloat = 320 * s
        let shortHeight: CGFloat = 240 * s
        let gap: CGFloat = 16 * s
        let staggerOffset: CGFloat = 50 * s

        return HStack(alignment: .top, spacing: gap) {
            // Left column
            VStack(spacing: gap) {
                ForEach(0..<photos.count, id: \.self) { index in
                    if index % 2 == 0 {
                        photoTile(index: index, width: columnWidth, height: tallHeight)
                    }
                }
            }

            // Right column (staggered down)
            VStack(spacing: gap) {
                ForEach(0..<photos.count, id: \.self) { index in
                    if index % 2 == 1 {
                        photoTile(index: index, width: columnWidth, height: shortHeight)
                    }
                }
            }
            .padding(.top, staggerOffset)
        }
    }

    // MARK: - Photo Tile

    private func photoTile(index: Int, width: CGFloat, height: CGFloat) -> some View {
        let photoData = photos[index]
        return VStack(alignment: .leading, spacing: 8 * s) {
            // Photo with overlay
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: photoData.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8 * s))

                // Place name + rating overlay
                HStack(spacing: 6 * s) {
                    Text(photoData.placeName)
                        .font(.system(size: 20 * s, weight: .semibold))
                        .lineLimit(1)
                    Text(photoData.rating.emoji)
                        .font(.system(size: 18 * s))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10 * s)
                .padding(.vertical, 5 * s)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
                .padding(8 * s)
            }

            // Note snippet placeholder
            if false {
                Text("")
                    .font(.system(size: 18 * s, design: .serif))
                    .italic()
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4 * s)
            }

            // Tag pills placeholder
            if false {
                HStack(spacing: 4 * s) {
                    ForEach(Array([""].prefix(2)), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 14 * s, weight: .medium))
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 6 * s)
                            .padding(.vertical, 2 * s)
                            .background(theme.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 4 * s)
            }
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            // Category breakdown placeholder
            EmptyView()

            // Rating summary
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
                Spacer()
                Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
            }
            .font(.system(size: 30 * s))
            .foregroundColor(theme.textSecondary.opacity(0.85))

            // Caption placeholder
            if let caption = data.tripDescription, !caption.isEmpty {
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
    }
}
