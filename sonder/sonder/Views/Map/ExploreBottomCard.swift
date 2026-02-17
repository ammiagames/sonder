//
//  ExploreBottomCard.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI

/// Bottom card showing details for a selected place on the explore map.
/// Dismisses via swipe-down or tapping the map behind it.
struct ExploreBottomCard: View {
    let place: ExploreMapPlace
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(SonderColors.inkLight.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, SonderSpacing.sm)
                .padding(.bottom, SonderSpacing.xs)

            VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                // Header: place info + bookmark
                HStack(alignment: .top) {
                    // Place photo
                    PlacePhotoView(photoReference: place.photoReference, size: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.inkDark)
                            .lineLimit(1)

                        Text(place.address)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(place.bestRating.emoji)
                            Text("\(place.friendCount) friend\(place.friendCount == 1 ? "" : "s")")
                                .font(SonderTypography.caption)
                                .foregroundColor(SonderColors.inkMuted)

                            if place.isFriendsLoved {
                                Text("\u{1F525} Friends Loved")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(SonderColors.ratingMustSee)
                            }
                        }
                    }

                    Spacer()

                    WantToGoButton(placeID: place.id, placeName: place.name, placeAddress: place.address, photoReference: place.photoReference)
                }

                // Mini-feed of friends' reviews
                if !place.logs.isEmpty {
                    Divider()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: SonderSpacing.xs) {
                            ForEach(place.logs.prefix(5), id: \.id) { item in
                                friendReviewRow(item)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)
        }
        .background(SonderColors.cream.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.md)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
                        onDismiss()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
        )
    }

    // MARK: - Friend Review Row

    private func friendReviewRow(_ item: FeedItem) -> some View {
        HStack(spacing: SonderSpacing.xs) {
            // Avatar
            if let urlString = item.user.avatarURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 28, height: 28)) {
                    avatarPlaceholder(for: item.user)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
            } else {
                avatarPlaceholder(for: item.user)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.user.username)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)

                    Text(item.rating.emoji)
                        .font(.system(size: 13))

                    Spacer()

                    Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundColor(SonderColors.inkLight)
                }

                if let note = item.log.note, !note.isEmpty {
                    Text(note)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(2)
                }
            }
        }
    }

    private func avatarPlaceholder(for user: FeedItem.FeedUser) -> some View {
        Circle()
            .fill(SonderColors.warmGray)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.inkMuted)
            }
    }
}
