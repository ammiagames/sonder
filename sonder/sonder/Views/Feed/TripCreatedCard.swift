//
//  TripCreatedCard.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI

/// Slim card shown when a followed user creates a new trip with no logs yet.
struct TripCreatedCard: View {
    let item: FeedTripCreatedItem
    let onUserTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // User header
            Button(action: onUserTap) {
                HStack(spacing: SonderSpacing.sm) {
                    if let urlString = item.user.avatarURL,
                       let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 28, height: 28)) {
                            avatarPlaceholder
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.user.username)
                            .font(SonderTypography.subheadline)
                            .foregroundStyle(SonderColors.inkDark)
                        Text("started a new trip")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Trip name + timestamp
            HStack {
                Label(item.tripName, systemImage: "suitcase")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                Spacer()

                Text(item.createdAt.relativeDisplay)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
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
                Text(item.user.username.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }
}
