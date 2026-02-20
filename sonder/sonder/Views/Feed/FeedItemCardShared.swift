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

    // MARK: - Bookmark Button

    static func bookmarkButton(
        isWantToGo: Bool,
        scale: Binding<CGFloat>,
        onTap: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                scale.wrappedValue = 1.3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    scale.wrappedValue = 1.0
                }
            }
            onTap()
        } label: {
            Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                .font(.system(size: 18))
                .foregroundStyle(isWantToGo ? SonderColors.terracotta : SonderColors.inkLight)
                .scaleEffect(scale.wrappedValue)
        }
        .buttonStyle(.plain)
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
    static func photoCarousel(
        photoURLs: [String],
        pageIndex: Binding<Int>,
        height: CGFloat,
        targetImageWidth: CGFloat = 400
    ) -> some View {
        TabView(selection: pageIndex) {
            ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, urlString in
                Group {
                    if let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: targetImageWidth, height: height)) {
                            Rectangle().fill(SonderColors.warmGray)
                        }
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photoURLs.count > 1 ? .automatic : .never))
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}
