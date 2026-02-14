//
//  ExploreMapPinView.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI

/// Pin view for a place on the explore map. Shows avatars and rating color.
/// When `isWantToGo` is true, a bookmark badge appears at bottom-left.
struct ExploreMapPinView: View {
    let place: ExploreMapPlace
    var isWantToGo: Bool = false

    var body: some View {
        if place.friendCount == 1 {
            singleFriendPin
        } else {
            multiFriendPin
        }
    }

    // MARK: - Single Friend Pin

    private var singleFriendPin: some View {
        ZStack {
            Circle()
                .fill(SonderColors.pinColor(for: place.bestRating))
                .frame(width: 40, height: 40)
                .overlay {
                    avatarImage(for: place.users.first, size: 24)
                }
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Fire badge
            if place.isFriendsLoved {
                friendsLovedBadge
                    .offset(x: 20, y: 0)
            }

            // Note badge at bottom-left
            if place.hasNote {
                noteBadge
                    .offset(x: -16, y: 14)
            }

            // Bookmark badge at top-right corner
            WantToGoTab()
                .offset(x: 16, y: -16)
                .opacity(isWantToGo ? 1 : 0)
                .scaleEffect(isWantToGo ? 1 : 0.3)
                .animation(.easeOut(duration: 0.25), value: isWantToGo)
        }
    }

    // MARK: - Multi-Friend Pin

    private var multiFriendPin: some View {
        ZStack {
            Circle()
                .fill(SonderColors.pinColor(for: place.bestRating))
                .frame(width: 48, height: 48)
                .overlay {
                    overlappingAvatars
                }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

            // Right side: friend count badge
            Text("\(place.friendCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(SonderColors.exploreCluster)
                .clipShape(Capsule())
                .offset(x: 28, y: -6)

            // Fire badge below count if loved
            if place.isFriendsLoved {
                friendsLovedBadge
                    .offset(x: 28, y: 8)
            }

            // Note badge at bottom-left
            if place.hasNote {
                noteBadge
                    .offset(x: -20, y: 18)
            }

            // Bookmark badge at top-right corner
            WantToGoTab()
                .offset(x: 20, y: -20)
                .opacity(isWantToGo ? 1 : 0)
                .scaleEffect(isWantToGo ? 1 : 0.3)
                .animation(.easeOut(duration: 0.25), value: isWantToGo)
        }
    }

    // MARK: - Overlapping Avatars

    private var overlappingAvatars: some View {
        let visibleUsers = Array(place.users.prefix(3))
        let totalWidth: CGFloat = CGFloat(visibleUsers.count) * 14 + 6

        return HStack(spacing: -6) {
            ForEach(Array(visibleUsers.enumerated()), id: \.element.id) { index, user in
                avatarImage(for: user, size: 20)
                    .zIndex(Double(visibleUsers.count - index))
            }
        }
        .frame(width: totalWidth)
    }

    // MARK: - Helpers

    private func avatarImage(for user: FeedItem.FeedUser?, size: CGFloat) -> some View {
        Group {
            if let urlString = user?.avatarURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) {
                    avatarPlaceholder(for: user, size: size)
                }
            } else {
                avatarPlaceholder(for: user, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
        }
    }

    private func avatarPlaceholder(for user: FeedItem.FeedUser?, size: CGFloat) -> some View {
        Circle()
            .fill(SonderColors.warmGray)
            .overlay {
                Text(user?.username.prefix(1).uppercased() ?? "?")
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.inkMuted)
            }
    }

    private var friendsLovedBadge: some View {
        Text("\u{1F525}")
            .font(.system(size: 10))
            .padding(2)
            .background(SonderColors.cream)
            .clipShape(Circle())
    }

    private var noteBadge: some View {
        Image(systemName: "text.quote")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(SonderColors.inkDark)
            .frame(width: 16, height: 16)
            .background(SonderColors.cream, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
    }

}
