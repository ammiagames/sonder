//
//  FeedItemCard.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Cinematic feed card — full-bleed photo with moody gradient and text overlay.
struct FeedItemCard: View {
    let feedItem: FeedItem
    let onUserTap: () -> Void
    let onPlaceTap: () -> Void

    @State private var photoPageIndex = 0

    private var hasPhoto: Bool { !feedItem.log.photoURLs.isEmpty }
    private var photoHeight: CGFloat { 360 }
    private var hasNote: Bool {
        if let note = feedItem.log.note, !note.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, SonderSpacing.lg)
                .padding(.top, SonderSpacing.md)
                .padding(.bottom, SonderSpacing.md)

            if hasPhoto {
                mediaSection
            }

            noteAndMetaContent
        }
        .background(SonderColors.warmGray)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlaceTap()
        }
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                .strokeBorder(SonderColors.inkLight.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }

    // MARK: - Note + Meta Layout

    private var noteAndMetaContent: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.md) {
            if let note = feedItem.log.note, !note.isEmpty {
                HStack(spacing: SonderSpacing.sm) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(SonderColors.terracotta.opacity(0.6))
                        .frame(width: 3)

                    Text(note)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(SonderColors.inkDark)
                        .lineSpacing(4)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            metaSection
        }
        .padding(.horizontal, SonderSpacing.lg)
        .padding(.top, hasNote ? SonderSpacing.md : SonderSpacing.lg)
        .padding(.bottom, SonderSpacing.lg)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: SonderSpacing.sm) {
            Button(action: onUserTap) {
                HStack(spacing: SonderSpacing.sm) {
                    FeedItemCardShared.bylineAvatar(
                        avatarURL: feedItem.user.avatarURL,
                        username: feedItem.user.username,
                        size: 30
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(feedItem.user.username)")
                            .font(SonderTypography.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(SonderColors.inkDark)
                            .lineLimit(1)

                        Text(feedItem.createdAt.relativeDisplay)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaSection: some View {
        FeedItemCardShared.photoCarousel(
            photoURLs: feedItem.log.photoURLs,
            pageIndex: $photoPageIndex,
            height: photoHeight
        )
    }

    // MARK: - Meta

    private var metaSection: some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                Text(feedItem.place.name)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SonderColors.inkMuted)
                    Text(feedItem.place.cityName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SonderColors.inkMuted)

                    Text("\u{00B7}")
                        .foregroundStyle(SonderColors.inkLight)

                    Text(feedItem.rating.emoji)
                        .font(.system(size: 13))
                    Text(feedItem.rating.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: feedItem.rating))
                }
            }

            Spacer(minLength: SonderSpacing.sm)

            WantToGoButton(
                placeID: feedItem.place.id,
                placeName: feedItem.place.name,
                placeAddress: feedItem.place.address,
                photoReference: feedItem.place.photoReference,
                sourceLogID: feedItem.log.id
            )
        }
    }

}

// MARK: - Skeleton / Shimmer Placeholder

/// Structural clone of FeedItemCard with all content replaced by shimmer bars.
/// Shown during initial feed load before any entries arrive.
struct FeedItemCardSkeleton: View {
    private let skeletonColor = SonderColors.warmGrayDark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — mirrors headerSection
            HStack(spacing: SonderSpacing.sm) {
                Circle()
                    .fill(skeletonColor)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(skeletonColor)
                        .frame(width: 110, height: 11)
                    Capsule()
                        .fill(skeletonColor)
                        .frame(width: 65, height: 9)
                }

                Spacer()
            }
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.top, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)

            // Photo area — mirrors mediaSection
            Rectangle()
                .fill(skeletonColor)
                .frame(maxWidth: .infinity)
                .frame(height: 360)

            // Note + meta — mirrors the inner VStack
            VStack(alignment: .leading, spacing: SonderSpacing.md) {
                // Note lines
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(skeletonColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 13)
                    Capsule()
                        .fill(skeletonColor)
                        .frame(width: 200, height: 13)
                }

                // Meta row — place name + location + bookmark
                HStack(alignment: .top, spacing: SonderSpacing.sm) {
                    VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                        Capsule()
                            .fill(skeletonColor)
                            .frame(width: 170, height: 20)
                        Capsule()
                            .fill(skeletonColor)
                            .frame(width: 110, height: 11)
                    }
                    Spacer(minLength: SonderSpacing.sm)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(skeletonColor)
                        .frame(width: 16, height: 22)
                }
            }
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.top, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.lg)
        }
        .background(SonderColors.warmGray)
        .shimmer()
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                .strokeBorder(SonderColors.inkLight.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}

// MARK: - Previews

private let previewPhotoItem = FeedItem(
    id: "1",
    log: FeedItem.FeedLog(
        id: "1",
        rating: "must_see",
        photoURLs: [
            "https://example.com/photo1.jpg",
            "https://example.com/photo2.jpg"
        ],
        note: "Amazing coffee! The pour-over was exceptional and the staff was super friendly. Definitely coming back next time I'm in the city.",
        tags: ["coffee", "cafe", "pour-over"],
        createdAt: Date(),
        tripID: nil
    ),
    user: FeedItem.FeedUser(
        id: "user1",
        username: "johndoe",
        avatarURL: nil,
        isPublic: true
    ),
    place: FeedItem.FeedPlace(
        id: "place1",
        name: "Blue Bottle Coffee",
        address: "123 Main St, San Francisco, CA 94102, USA",
        latitude: 37.7749,
        longitude: -122.4194,
        photoReference: nil
    )
)

private let previewCompactItem = FeedItem(
    id: "2",
    log: FeedItem.FeedLog(
        id: "2",
        rating: "skip",
        photoURLs: [],
        note: "Not great, wouldn't recommend.",
        tags: [],
        createdAt: Date().addingTimeInterval(-86400 * 3),
        tripID: nil
    ),
    user: FeedItem.FeedUser(
        id: "user2",
        username: "janedoe",
        avatarURL: nil,
        isPublic: true
    ),
    place: FeedItem.FeedPlace(
        id: "place2",
        name: "Generic Restaurant",
        address: "456 Oak Ave, Los Angeles, CA 90001, USA",
        latitude: 34.0522,
        longitude: -118.2437,
        photoReference: nil,
        types: ["restaurant"]
    )
)

#Preview("Feed Item Card") {
    ScrollView {
        VStack(spacing: SonderSpacing.md) {
            // Card with photo + note
            FeedItemCard(
                feedItem: previewPhotoItem,
                onUserTap: {},
                onPlaceTap: {}
            )

            // Card without photo (note only)
            FeedItemCard(
                feedItem: previewCompactItem,
                onUserTap: {},
                onPlaceTap: {}
            )
        }
        .padding()
    }
    .background(SonderColors.cream)
}
