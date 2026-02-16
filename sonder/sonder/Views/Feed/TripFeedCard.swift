//
//  TripFeedCard.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI

/// Card showing a friend's trip in the feed with hero image + thumbnail grid
struct TripFeedCard: View {
    let tripItem: FeedTripItem
    let onUserTap: () -> Void
    let onTripTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            userHeader
            heroImage
            if tripItem.logs.count > 1 {
                thumbnailGrid
            }
            contentSection
            footerSection
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
        .onTapGesture(perform: onTripTap)
    }

    // MARK: - User Header

    private var userHeader: some View {
        Button(action: onUserTap) {
            HStack(spacing: SonderSpacing.sm) {
                if let urlString = tripItem.user.avatarURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 36, height: 36)) {
                        avatarPlaceholder
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(tripItem.user.username)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                    Text(tripItem.activitySubtitle)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }

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
                Text(tripItem.user.username.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Hero Image

    private var heroImage: some View {
        Group {
            if let urlString = tripItem.coverPhotoURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 220)) {
                    logPhotoFallback
                }
            } else {
                logPhotoFallback
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var logPhotoFallback: some View {
        if let firstLog = tripItem.logs.first {
            if let urlString = firstLog.photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 220)) {
                    placePhotoFallback(photoReference: firstLog.placePhotoReference)
                }
            } else {
                placePhotoFallback(photoReference: firstLog.placePhotoReference)
            }
        } else {
            gradientPlaceholder
        }
    }

    @ViewBuilder
    private func placePhotoFallback(photoReference: String?) -> some View {
        if let ref = photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: 800) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 220)) {
                gradientPlaceholder
            }
        } else {
            gradientPlaceholder
        }
    }

    private var gradientPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "suitcase")
                    .font(.largeTitle)
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    // MARK: - Thumbnail Grid

    private var thumbnailGrid: some View {
        let thumbnails = Array(tripItem.logs.prefix(4))
        return HStack(spacing: 2) {
            ForEach(thumbnails) { log in
                thumbnailView(for: log)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private func thumbnailView(for log: FeedTripItem.LogSummary) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 100, height: 72)) {
                thumbnailPlaceholder(for: log)
            }
        } else {
            thumbnailPlaceholder(for: log)
        }
    }

    @ViewBuilder
    private func thumbnailPlaceholder(for log: FeedTripItem.LogSummary) -> some View {
        if let ref = log.placePhotoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 100, height: 72)) {
                smallGradientPlaceholder
            }
        } else {
            smallGradientPlaceholder
        }
    }

    private var smallGradientPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.2), SonderColors.ochre.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "mappin")
                    .font(.caption)
                    .foregroundColor(SonderColors.terracotta.opacity(0.4))
            }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text(tripItem.name)
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
                .lineLimit(2)

            HStack(spacing: SonderSpacing.sm) {
                if let dateRange = tripItem.dateRangeDisplay {
                    Label(dateRange, systemImage: "calendar")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }

                Label("\(tripItem.logs.count) \(tripItem.logs.count == 1 ? "log" : "logs")", systemImage: "list.bullet")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.top, SonderSpacing.md)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text(tripItem.latestActivityAt.relativeDisplay)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)
            Spacer()
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.md)
    }
}
