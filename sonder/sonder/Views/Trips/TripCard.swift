//
//  TripCard.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI

/// Card displaying trip summary in the trips list
struct TripCard: View {
    let trip: Trip
    let logCount: Int
    let isOwner: Bool
    var compact: Bool = false

    private var hasCoverPhoto: Bool {
        trip.coverPhotoURL != nil
    }

    private var coverHeight: CGFloat {
        compact ? 120 : 140
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover photo (only when available)
            if hasCoverPhoto {
                coverPhotoSection
                    .frame(height: coverHeight)
                    .clipped()
            }

            // Info section
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                // Name + owner badge
                HStack {
                    Text(trip.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    Spacer()

                    if isOwner {
                        Text("Owner")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, SonderSpacing.xs)
                            .padding(.vertical, 3)
                            .background(SonderColors.terracotta.opacity(0.15))
                            .foregroundStyle(SonderColors.terracotta)
                            .clipShape(Capsule())
                    }
                }

                // Description
                if let description = trip.tripDescription, !description.isEmpty {
                    Text(description)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(2)
                }

                // Date range
                if let dateText = dateRangeText {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text(dateText)
                            .font(SonderTypography.caption)
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }

                // Stats row
                HStack(spacing: SonderSpacing.md) {
                    // Log count
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text("\(logCount) \(logCount == 1 ? "place" : "places")")
                            .font(SonderTypography.caption)
                    }
                    .foregroundStyle(SonderColors.inkLight)

                    // Collaborators indicator
                    if !trip.collaboratorIDs.isEmpty {
                        HStack(spacing: SonderSpacing.xxs) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text("\(trip.collaboratorIDs.count + 1) travelers")
                                .font(SonderTypography.caption)
                        }
                        .foregroundStyle(SonderColors.inkLight)
                    }

                    Spacer()
                }
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
    }

    // MARK: - Cover Photo Section

    @ViewBuilder
    private var coverPhotoSection: some View {
        if let urlString = trip.coverPhotoURL,
           let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: compact ? 200 : 400, height: coverHeight)) {
                placeholderGradient
            }
            .id(urlString)
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        TripCoverPlaceholderView(
            seedKey: trip.id,
            title: compact ? nil : trip.name,
            caption: compact ? nil : "Travel journal"
        )
    }

    // MARK: - Helpers

    private var dateRangeText: String? {
        ProfileShared.tripMediumDateRange(trip)
    }
}

#Preview {
    VStack(spacing: 16) {
        TripCard(
            trip: Trip(
                name: "Japan 2024",
                startDate: Date(),
                endDate: Date().addingTimeInterval(86400 * 14),
                createdBy: "user1"
            ),
            logCount: 12,
            isOwner: true
        )

        TripCard(
            trip: Trip(
                name: "Weekend Getaway",
                createdBy: "user2"
            ),
            logCount: 3,
            isOwner: false
        )
    }
    .padding()
    .background(SonderColors.cream)
}
