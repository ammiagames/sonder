//
//  FeedItemCard.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Card showing a friend's log in the feed with save button
struct FeedItemCard: View {
    let feedItem: FeedItem
    let isWantToGo: Bool
    let onUserTap: () -> Void
    let onPlaceTap: () -> Void
    let onWantToGoTap: () -> Void

    @State private var photoPageIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            userRatingHeader
            photoCarousel
            placeSection
            noteSection
            tagsSection
            footerSection
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
    }

    // MARK: - User + Rating Header

    private var userRatingHeader: some View {
        Button(action: onUserTap) {
            HStack(spacing: SonderSpacing.sm) {
                // Avatar
                if let urlString = feedItem.user.avatarURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 28, height: 28)) {
                        avatarPlaceholder
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                // "username rated this"
                HStack(spacing: 4) {
                    Text(feedItem.user.username)
                        .font(SonderTypography.subheadline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)
                    Text("rated this")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }

                Spacer()

                // Rating pill badge
                ratingBadge
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.vertical, SonderSpacing.sm)
        }
        .buttonStyle(.plain)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 28, height: 28)
            .overlay {
                Text(feedItem.user.username.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    private var ratingBadge: some View {
        HStack(spacing: 4) {
            Text(feedItem.rating.emoji)
                .font(.system(size: 13))
            Text(feedItem.rating.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(SonderColors.pinColor(for: feedItem.rating))
        }
        .padding(.horizontal, SonderSpacing.xs)
        .padding(.vertical, 4)
        .background(SonderColors.pinColor(for: feedItem.rating).opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Photo Carousel

    private var photoCarousel: some View {
        Button(action: onPlaceTap) {
            Group {
                if !feedItem.log.photoURLs.isEmpty {
                    TabView(selection: $photoPageIndex) {
                        ForEach(Array(feedItem.log.photoURLs.enumerated()), id: \.offset) { index, urlString in
                            Group {
                                if let url = URL(string: urlString) {
                                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 220)) {
                                        photoPlaceholder
                                    }
                                } else {
                                    photoPlaceholder
                                }
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: feedItem.log.photoURLs.count > 1 ? .automatic : .never))
                } else {
                    placePhoto
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = feedItem.place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 220)) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    // MARK: - Place Section

    private var placeSection: some View {
        Button(action: onPlaceTap) {
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(feedItem.place.name)
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                        .foregroundColor(SonderColors.inkMuted)
                    Text(feedItem.place.cityName)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SonderSpacing.md)
            .padding(.top, SonderSpacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note Section

    @ViewBuilder
    private var noteSection: some View {
        if let note = feedItem.log.note, !note.isEmpty {
            HStack(spacing: SonderSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SonderColors.terracotta)
                    .frame(width: 3)

                Text(note)
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.top, SonderSpacing.sm)
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private var tagsSection: some View {
        if !feedItem.log.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xxs) {
                    ForEach(feedItem.log.tags, id: \.self) { tag in
                        Text(tag)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.terracotta)
                            .padding(.horizontal, SonderSpacing.xs)
                            .padding(.vertical, 4)
                            .background(SonderColors.terracotta.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, SonderSpacing.md)
            }
            .padding(.top, SonderSpacing.sm)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            Text(feedItem.createdAt.relativeDisplay)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)

            Spacer()

            Button(action: onWantToGoTap) {
                Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(isWantToGo ? SonderColors.terracotta : SonderColors.inkLight)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.md)
    }
}

// MARK: - Previews

#Preview("Full Card") {
    ScrollView {
        FeedItemCard(
            feedItem: FeedItem(
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
                    createdAt: Date()
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
            ),
            isWantToGo: false,
            onUserTap: {},
            onPlaceTap: {},
            onWantToGoTap: {}
        )
        .padding()
    }
}

#Preview("Minimal Card") {
    ScrollView {
        FeedItemCard(
            feedItem: FeedItem(
                id: "2",
                log: FeedItem.FeedLog(
                    id: "2",
                    rating: "skip",
                    photoURLs: [],
                    note: nil,
                    tags: [],
                    createdAt: Date().addingTimeInterval(-86400 * 3)
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
                    photoReference: nil
                )
            ),
            isWantToGo: true,
            onUserTap: {},
            onPlaceTap: {},
            onWantToGoTap: {}
        )
        .padding()
    }
}
