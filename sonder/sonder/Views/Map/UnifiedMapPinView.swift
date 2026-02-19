//
//  UnifiedMapPinView.swift
//  sonder
//
//  Pin views for the unified map: personal, friends, and combined.
//

import SwiftUI

// MARK: - Shared Pin Photo Constants

/// Standard size for all map pin place photos so prefetch and render share cache entries.
/// Uses the largest pin size (48pt combined must-see) so images are sharp at every tier.
enum PinPhotoConstants {
    static let pointSize = CGSize(width: 48, height: 48)
    /// 48 * 3 for @3x displays
    static let maxWidth = 144
}

// MARK: - Want to Go Tab

/// Bookmark badge that appears at the top-right corner of a pin when the place
/// is on the Want to Go list. Circular background with a bookmark icon.
struct WantToGoTab: View {
    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(SonderColors.wantToGoPin, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
    }
}

// MARK: - Log Pin View

/// Personal log pin.
/// With photo: circle with image and terracotta ring.
/// Without photo: rating emoji in a cream circle with rating-color ring.
/// Multiple photos: stacked circles with depth effect.
struct LogPinView: View {
    let rating: Rating
    var photoURLs: [String] = []
    var placeTypes: [String] = []
    var visitCount: Int = 1
    var isWantToGo: Bool = false

    private var pinSize: CGFloat {
        switch rating {
        case .mustSee: return 44
        case .solid: return 38
        case .skip: return 32
        }
    }

    private var ringWidth: CGFloat {
        switch rating {
        case .mustSee: return 3.5
        case .solid: return 2.5
        case .skip: return 1.5
        }
    }

    private var shadowRadius: CGFloat {
        switch rating {
        case .mustSee: return 6
        case .solid: return 3
        case .skip: return 1.5
        }
    }

    private var shadowColor: Color {
        switch rating {
        case .mustSee: return SonderColors.ochre.opacity(0.5)
        case .solid: return .black.opacity(0.2)
        case .skip: return .black.opacity(0.12)
        }
    }

    private var saturation: Double {
        switch rating {
        case .mustSee: return 1.0
        case .solid: return 0.85
        case .skip: return 0.5
        }
    }

    private var ratingColor: Color {
        SonderColors.pinColor(for: rating)
    }

    private var resolvedPhotoURLs: [URL] {
        photoURLs.compactMap { URL(string: $0) }
    }

    var body: some View {
        ZStack {
            let urls = resolvedPhotoURLs
            if urls.count >= 2 {
                stackedPhotoCircles(urls: urls)
            } else if let url = urls.first {
                photoPinVisual(url: url)
            } else {
                ratingEmojiVisual
            }

            // Visit count badge — hidden when stacked (stacking conveys multiplicity)
            if visitCount > 1 && resolvedPhotoURLs.count < 2 {
                Text("×\(visitCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
                    .offset(x: -(pinSize * 0.44), y: pinSize * 0.39)
            }

            // Bookmark badge
            WantToGoTab()
                .offset(x: pinSize * 0.39, y: -(pinSize * 0.39))
                .opacity(isWantToGo ? 1 : 0)
                .scaleEffect(isWantToGo ? 1 : 0.3)
                .animation(.easeOut(duration: 0.25), value: isWantToGo)
        }
    }

    // MARK: - Stacked Photo Circles

    private func stackedPhotoCircles(urls: [URL]) -> some View {
        let stack = Array(urls.prefix(3))
        return ZStack {
            // Back circles (painter's order: furthest back first)
            ForEach(Array(stack.enumerated()).dropLast(), id: \.offset) { index, url in
                let depth = stack.count - 1 - index // distance from front
                let scale: CGFloat = depth == 2 ? 0.84 : 0.92
                let opacity: Double = depth == 2 ? 0.55 : 0.65
                let offsetAmount = CGFloat(depth) * -4

                DownsampledAsyncImage(url: url, targetSize: PinPhotoConstants.pointSize) {
                    Circle().fill(ratingColor)
                }
                .saturation(saturation)
                .frame(width: pinSize, height: pinSize)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(SonderColors.terracotta, lineWidth: 1)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .offset(x: offsetAmount, y: offsetAmount)
            }

            // Front circle — most recent photo, full appearance
            photoPinVisual(url: stack.last!)
        }
    }

    // MARK: - Photo Pin (circle with image)

    private func photoPinVisual(url: URL) -> some View {
        DownsampledAsyncImage(url: url, targetSize: PinPhotoConstants.pointSize) {
            Circle().fill(ratingColor)
        }
        .saturation(saturation)
        .frame(width: pinSize, height: pinSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(SonderColors.terracotta, lineWidth: ringWidth)
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }

    // MARK: - No Photo: Rating Emoji

    private var categoryGradient: AnyShapeStyle {
        if let category = ExploreMapFilter.CategoryFilter.category(for: placeTypes) {
            return AnyShapeStyle(
                RadialGradient(
                    colors: [category.color.opacity(0.18), SonderColors.cream],
                    center: .center,
                    startRadius: 0,
                    endRadius: pinSize / 2
                )
            )
        }
        return AnyShapeStyle(SonderColors.cream)
    }

    private var ratingEmojiVisual: some View {
        Circle()
            .fill(categoryGradient)
            .frame(width: pinSize, height: pinSize)
            .overlay {
                Text(rating.emoji)
                    .font(.system(size: pinSize * 0.45))
            }
            .overlay {
                Circle()
                    .stroke(ratingColor, lineWidth: ringWidth)
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }
}

// MARK: - Unified Map Pin View

/// Renders the appropriate pin style based on UnifiedMapPin type
struct UnifiedMapPinView: View {
    let pin: UnifiedMapPin
    var isWantToGo: Bool = false

    var body: some View {
        switch pin {
        case .personal(let logs, let place):
            LogPinView(
                rating: logs.first?.rating ?? .solid,
                photoURLs: logs.compactMap(\.photoURL),
                placeTypes: place.types,
                visitCount: logs.count,
                isWantToGo: isWantToGo
            )
        case .friends(let place):
            ExploreMapPinView(place: place, isWantToGo: isWantToGo)
        case .combined(let logs, let place, let friendPlace):
            CombinedMapPinView(
                rating: logs.first?.rating ?? .solid,
                photoURLs: logs.compactMap(\.photoURL),
                placeTypes: place.types,
                friendCount: friendPlace.friendCount,
                isFriendsLoved: friendPlace.isFriendsLoved,
                visitCount: logs.count,
                isWantToGo: isWantToGo
            )
        }
    }
}

// MARK: - Combined Map Pin View

/// Pin for places logged by both the user and friends.
/// With photo: circle with terracotta ring + friend badge.
/// Without photo: rating emoji in cream circle + friend badge.
/// Multiple photos: stacked circles with depth effect + friend badge.
struct CombinedMapPinView: View {
    let rating: Rating
    var photoURLs: [String] = []
    var placeTypes: [String] = []
    let friendCount: Int
    let isFriendsLoved: Bool
    var visitCount: Int = 1
    var isWantToGo: Bool = false

    // Combined pins are slightly larger than personal pins at each tier
    private var pinSize: CGFloat {
        switch rating {
        case .mustSee: return 48
        case .solid: return 42
        case .skip: return 36
        }
    }

    private var ringWidth: CGFloat {
        switch rating {
        case .mustSee: return 3.5
        case .solid: return 2.5
        case .skip: return 1.5
        }
    }

    private var shadowRadius: CGFloat {
        switch rating {
        case .mustSee: return 6
        case .solid: return 3
        case .skip: return 1.5
        }
    }

    private var shadowColor: Color {
        switch rating {
        case .mustSee: return SonderColors.ochre.opacity(0.5)
        case .solid: return .black.opacity(0.2)
        case .skip: return .black.opacity(0.12)
        }
    }

    private var saturation: Double {
        switch rating {
        case .mustSee: return 1.0
        case .solid: return 0.85
        case .skip: return 0.5
        }
    }

    private var ratingColor: Color {
        SonderColors.pinColor(for: rating)
    }

    private var resolvedPhotoURLs: [URL] {
        photoURLs.compactMap { URL(string: $0) }
    }

    var body: some View {
        ZStack {
            let urls = resolvedPhotoURLs
            if urls.count >= 2 {
                stackedPhotoCircles(urls: urls)
            } else if let url = urls.first {
                photoPinVisual(url: url)
            } else {
                ratingEmojiVisual
            }

            // Friend badge (right side)
            HStack(spacing: 2) {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .bold))
                if friendCount > 1 {
                    Text("\(friendCount)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(SonderColors.exploreCluster)
            .clipShape(Capsule())
            .offset(x: pinSize * 0.55, y: -(pinSize * 0.15))

            // Visit count badge — hidden when stacked
            if visitCount > 1 && resolvedPhotoURLs.count < 2 {
                Text("×\(visitCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
                    .offset(x: -(pinSize * 0.44), y: pinSize * 0.35)
            }

            // Fire badge if friends loved
            if isFriendsLoved {
                Text("\u{1F525}")
                    .font(.system(size: 10))
                    .padding(2)
                    .background(SonderColors.cream)
                    .clipShape(Circle())
                    .offset(x: pinSize * 0.55, y: pinSize * 0.2)
            }

            // Bookmark badge
            WantToGoTab()
                .offset(x: pinSize * 0.39, y: -(pinSize * 0.39))
                .opacity(isWantToGo ? 1 : 0)
                .scaleEffect(isWantToGo ? 1 : 0.3)
                .animation(.easeOut(duration: 0.25), value: isWantToGo)
        }
    }

    // MARK: - Stacked Photo Circles

    private func stackedPhotoCircles(urls: [URL]) -> some View {
        let stack = Array(urls.prefix(3))
        return ZStack {
            ForEach(Array(stack.enumerated()).dropLast(), id: \.offset) { index, url in
                let depth = stack.count - 1 - index
                let scale: CGFloat = depth == 2 ? 0.84 : 0.92
                let opacity: Double = depth == 2 ? 0.55 : 0.65
                let offsetAmount = CGFloat(depth) * -4

                DownsampledAsyncImage(url: url, targetSize: PinPhotoConstants.pointSize) {
                    Circle().fill(ratingColor)
                }
                .saturation(saturation)
                .frame(width: pinSize, height: pinSize)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(SonderColors.terracotta, lineWidth: 1)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .offset(x: offsetAmount, y: offsetAmount)
            }

            photoPinVisual(url: stack.last!)
        }
    }

    // MARK: - Photo Pin (circle with image)

    private func photoPinVisual(url: URL) -> some View {
        DownsampledAsyncImage(url: url, targetSize: PinPhotoConstants.pointSize) {
            Circle().fill(ratingColor)
        }
        .saturation(saturation)
        .frame(width: pinSize, height: pinSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(SonderColors.terracotta, lineWidth: ringWidth)
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }

    // MARK: - No Photo: Rating Emoji

    private var categoryGradient: AnyShapeStyle {
        if let category = ExploreMapFilter.CategoryFilter.category(for: placeTypes) {
            return AnyShapeStyle(
                RadialGradient(
                    colors: [category.color.opacity(0.18), SonderColors.cream],
                    center: .center,
                    startRadius: 0,
                    endRadius: pinSize / 2
                )
            )
        }
        return AnyShapeStyle(SonderColors.cream)
    }

    private var ratingEmojiVisual: some View {
        Circle()
            .fill(categoryGradient)
            .frame(width: pinSize, height: pinSize)
            .overlay {
                Text(rating.emoji)
                    .font(.system(size: pinSize * 0.45))
            }
            .overlay {
                Circle()
                    .stroke(ratingColor, lineWidth: ringWidth)
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }
}
