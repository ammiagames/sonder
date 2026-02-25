//
//  FeedItemCardShared.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Static helpers shared across all four feed-card variants.
enum FeedItemCardShared {

    // MARK: - Byline Avatar

    @ViewBuilder
    static func bylineAvatar(avatarURL: String?, username: String, size: CGFloat) -> some View {
        if let urlString = avatarURL,
           let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) {
                avatarPlaceholder(username: username, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarPlaceholder(username: username, size: size)
        }
    }

    // MARK: - Avatar Placeholder

    static func avatarPlaceholder(username: String, size: CGFloat) -> some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .frame(width: size, height: size)
            .overlay {
                Text(username.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    // MARK: - Compact Place Thumbnail

    @ViewBuilder
    static func compactPlaceThumbnail(
        photoReference: String?,
        placeName: String,
        rating: Rating,
        size: CGFloat
    ) -> some View {
        if let photoRef = photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: Int(size * 2)) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) {
                compactInitialFallback(placeName: placeName, rating: rating, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        } else {
            compactInitialFallback(placeName: placeName, rating: rating, size: size)
        }
    }

    // MARK: - Compact Initial Fallback

    static func compactInitialFallback(placeName: String, rating: Rating, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
            .fill(
                LinearGradient(
                    colors: [
                        SonderColors.pinColor(for: rating).opacity(0.3),
                        SonderColors.pinColor(for: rating).opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(placeName.prefix(1).uppercased())
                    .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
                    .foregroundStyle(SonderColors.pinColor(for: rating))
            }
    }

    // MARK: - Photo Carousel

    /// Reusable photo carousel (TabView with page style).
    @ViewBuilder
    static func photoCarousel(
        photoURLs: [String],
        pageIndex: Binding<Int>,
        height: CGFloat,
        targetImageWidth: CGFloat = 400
    ) -> some View {
        if photoURLs.isEmpty {
            Rectangle()
                .fill(SonderColors.warmGray)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
        } else {
            let safeSelection = Binding<Int>(
                get: {
                    let maxIndex = max(photoURLs.count - 1, 0)
                    return min(max(pageIndex.wrappedValue, 0), maxIndex)
                },
                set: { newValue in
                    let maxIndex = max(photoURLs.count - 1, 0)
                    pageIndex.wrappedValue = min(max(newValue, 0), maxIndex)
                }
            )

            TabView(selection: safeSelection) {
                ForEach(photoURLs.indices, id: \.self) { index in
                    // Only load images for the current page and adjacent pages (±1)
                    // to avoid eagerly downloading all carousel photos at once
                    let currentPage = safeSelection.wrappedValue
                    let isNearby = abs(index - currentPage) <= 1
                    if isNearby, let url = URL(string: photoURLs[index]) {
                        DownsampledAsyncImage(
                            url: url,
                            targetSize: CGSize(width: targetImageWidth, height: height),
                            contentMode: .fill
                        ) {
                            Rectangle().fill(SonderColors.warmGray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .tag(index)
                    } else {
                        Rectangle()
                            .fill(SonderColors.warmGray)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photoURLs.count > 1 ? .automatic : .never))
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }
}
