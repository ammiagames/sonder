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
    let isWantToGo: Bool
    let onUserTap: () -> Void
    let onPlaceTap: () -> Void
    let onWantToGoTap: () -> Void

    @State private var photoPageIndex = 0
    @State private var bookmarkScale: CGFloat = 1.0

    private var hasPhoto: Bool { !feedItem.log.photoURLs.isEmpty }
    private var hasNote: Bool {
        if let note = feedItem.log.note, !note.isEmpty { return true }
        return false
    }

    var body: some View {
        Button(action: onPlaceTap) {
            ZStack(alignment: .bottom) {
                if hasPhoto {
                    FeedItemCardShared.photoCarousel(
                        photoURLs: feedItem.log.photoURLs,
                        pageIndex: $photoPageIndex,
                        height: hasNote ? 440 : 380
                    )

                    // Heavy cinematic gradient — darker, moodier
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.2),
                            .init(color: .black.opacity(0.4), location: 0.5),
                            .init(color: .black.opacity(0.85), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    // Dark cinematic background for no-photo — sized by content
                    Color.clear
                }

                // Content overlay — everything on the photo
                VStack(alignment: .leading, spacing: 0) {
                    if hasPhoto { Spacer() }

                    // Pull-quote (the emotional hook)
                    if let note = feedItem.log.note, !note.isEmpty {
                        HStack(alignment: .top, spacing: 0) {
                            Text("\u{201C}")
                                .font(.system(size: 48, weight: .thin, design: .serif))
                                .foregroundStyle(SonderColors.terracotta.opacity(0.7))
                                .offset(y: -8)
                                .padding(.trailing, 2)

                            Text(note)
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.bottom, SonderSpacing.md)
                    }

                    // Place name — bold, commanding
                    Text(feedItem.place.name)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    // City + rating inline
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10, weight: .medium))
                            Text(feedItem.place.cityName)
                                .font(.system(size: 12, weight: .medium))
                        }

                        Text("\u{00B7}")

                        HStack(spacing: 4) {
                            Text(feedItem.rating.emoji)
                                .font(.system(size: 13))
                            Text(feedItem.rating.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 4)

                    // Byline — on the photo itself
                    HStack(spacing: SonderSpacing.xs) {
                        Button(action: onUserTap) {
                            HStack(spacing: SonderSpacing.xs) {
                                FeedItemCardShared.bylineAvatar(
                                    avatarURL: feedItem.user.avatarURL,
                                    username: feedItem.user.username,
                                    size: 22
                                )
                                Text("@\(feedItem.user.username)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(feedItem.createdAt.relativeDisplay)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))

                        FeedItemCardShared.bookmarkButton(
                            isWantToGo: isWantToGo,
                            scale: $bookmarkScale,
                            onTap: onWantToGoTap
                        )
                        .colorMultiply(.white)
                    }
                    .padding(.top, SonderSpacing.md)
                }
                .padding(SonderSpacing.lg)
            }
            .frame(height: hasPhoto ? (hasNote ? 440 : 380) : nil)
            .background(
                hasPhoto ? nil : ZStack {
                    // Warm dark base gradient
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.14, blue: 0.12),
                            Color(red: 0.14, green: 0.10, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Rating color overlay
                    SonderColors.pinColor(for: feedItem.rating).opacity(0.15)

                    // Category watermark icon
                    Image(systemName: feedItem.place.categoryIcon)
                        .font(.system(size: 80, weight: .thin))
                        .foregroundStyle(.white.opacity(0.06))
                        .rotationEffect(.degrees(-15))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                }
            )
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
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

#Preview("Photo Card") {
    ScrollView {
        FeedItemCard(
            feedItem: previewPhotoItem,
            isWantToGo: false,
            onUserTap: {},
            onPlaceTap: {},
            onWantToGoTap: {}
        )
        .padding()
    }
    .background(SonderColors.cream)
}

#Preview("Compact Card") {
    ScrollView {
        FeedItemCard(
            feedItem: previewCompactItem,
            isWantToGo: true,
            onUserTap: {},
            onPlaceTap: {},
            onWantToGoTap: {}
        )
        .padding()
    }
    .background(SonderColors.cream)
}
