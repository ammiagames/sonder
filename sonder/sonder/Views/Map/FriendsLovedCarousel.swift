//
//  FriendsLovedCarousel.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI

/// Horizontal carousel showing places that multiple friends rated must-see
struct FriendsLovedCarousel: View {
    let places: [ExploreMapPlace]
    let onSelectPlace: (ExploreMapPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            // Header
            HStack(spacing: 6) {
                Text("\u{1F525}")
                    .font(.system(size: 16))
                Text("Your Friends Loved")
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)
            }
            .padding(.horizontal, SonderSpacing.md)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.sm) {
                    ForEach(places) { place in
                        Button {
                            onSelectPlace(place)
                        } label: {
                            lovedPlaceCard(place)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SonderSpacing.md)
            }
        }
        .padding(.vertical, SonderSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Compact Place Card

    private func lovedPlaceCard(_ place: ExploreMapPlace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Photo
            PlacePhotoView(photoReference: place.photoReference, size: 80, cornerRadius: SonderSpacing.radiusSm)

            // Name
            Text(place.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SonderColors.inkDark)
                .lineLimit(1)

            // Friends count + rating
            HStack(spacing: 4) {
                Text(place.bestRating.emoji)
                    .font(.system(size: 12))
                Text("\(place.friendCount) friends")
                    .font(.system(size: 11))
                    .foregroundColor(SonderColors.inkMuted)
            }
        }
        .frame(width: 100)
        .padding(SonderSpacing.xs)
        .background(SonderColors.cream.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
