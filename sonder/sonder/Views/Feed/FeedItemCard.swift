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

    private var hasPhoto: Bool {
        feedItem.log.photoURL != nil || feedItem.place.photoReference != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: User info
            userHeader

            // Photo (only if available)
            if hasPhoto {
                photoSection
            }

            // Content: Place name, rating, note
            contentSection

            // Footer: Date and Want to Go button
            footerSection
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
    }

    // MARK: - User Header

    private var userHeader: some View {
        Button(action: onUserTap) {
            HStack(spacing: SonderSpacing.sm) {
                // Avatar
                if let urlString = feedItem.user.avatarURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 36, height: 36)) {
                        avatarPlaceholder
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                // Username
                Text(feedItem.user.username)
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)

                Spacer()
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
            .frame(width: 36, height: 36)
            .overlay {
                Text(feedItem.user.username.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        Button(action: onPlaceTap) {
            ZStack(alignment: .bottomTrailing) {
                // Photo
                if let urlString = feedItem.log.photoURL,
                   let url = URL(string: urlString) {
                    // User's photo
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 220)) {
                        placePhoto
                    }
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

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            // Place name and rating
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    Text(feedItem.place.name)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(2)

                    Text(feedItem.place.address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Rating badge
                Text(feedItem.rating.emoji)
                    .font(.title2)
            }

            // Note
            if let note = feedItem.log.note, !note.isEmpty {
                Text(note)
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .lineLimit(3)
            }

            // Tags
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
                }
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.top, SonderSpacing.md)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            // Relative time
            Text(feedItem.createdAt.relativeDisplay)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)

            Spacer()

            // Want to Go button
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

#Preview {
    ScrollView {
        FeedItemCard(
            feedItem: FeedItem(
                id: "1",
                log: FeedItem.FeedLog(
                    id: "1",
                    rating: "must_see",
                    photoURL: nil,
                    note: "Amazing coffee! The pour-over was exceptional and the staff was super friendly.",
                    tags: ["coffee", "cafe"],
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
                    address: "123 Main St, San Francisco, CA",
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
