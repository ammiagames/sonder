//
//  PlaceSearchRow.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "PlaceSearchRow")

/// Row component for displaying a place search result
struct PlaceSearchRow: View {
    let name: String
    let address: String
    let photoReference: String?
    let icon: String?
    let placeId: String?
    let distanceText: String?
    let onLogDirect: (() -> Void)?

    init(name: String, address: String, photoReference: String? = nil, icon: String? = nil, placeId: String? = nil, distanceText: String? = nil, onLogDirect: (() -> Void)? = nil) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.icon = icon
        self.placeId = placeId
        self.distanceText = distanceText
        self.onLogDirect = onLogDirect
    }

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Place info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SonderTypography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                if !address.isEmpty {
                    Text(address)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let distanceText {
                Text(distanceText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SonderColors.inkLight)
            }

            // Direct-log button (if provided)
            if let onLogDirect {
                Button(action: onLogDirect) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SonderColors.terracotta)
                }
                .buttonStyle(.plain)
            }

            // Bookmark button
            if let placeId = placeId {
                WantToGoButton(placeID: placeId, placeName: name, placeAddress: address, photoReference: photoReference, iconSize: 18, unsavedColor: SonderColors.inkLight)
                    .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SonderColors.inkLight)
        }
        .padding(.vertical, SonderSpacing.xs)
        .padding(.horizontal, SonderSpacing.md)
        .contentShape(Rectangle())
    }
}

/// Row for recent search with delete action
struct RecentSearchRow: View {
    let name: String
    let address: String
    let photoReference: String?
    let placeId: String?
    let onLogDirect: (() -> Void)?
    let onDelete: () -> Void

    init(name: String, address: String, photoReference: String? = nil, placeId: String? = nil, onLogDirect: (() -> Void)? = nil, onDelete: @escaping () -> Void) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.placeId = placeId
        self.onLogDirect = onLogDirect
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Clock icon for recent search
            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundStyle(SonderColors.inkLight)

            // Place info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SonderTypography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                if !address.isEmpty {
                    Text(address)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Direct-log button
            if let onLogDirect {
                Button(action: onLogDirect) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SonderColors.terracotta)
                }
                .buttonStyle(.plain)
            }

            // Bookmark button
            if let placeId = placeId {
                WantToGoButton(placeID: placeId, placeName: name, placeAddress: address, photoReference: photoReference, iconSize: 18, unsavedColor: SonderColors.inkLight)
                    .buttonStyle(.plain)
            }

            // Delete button
            Button {
                SonderHaptics.impact(.light)
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.8))
        }
        .padding(.vertical, SonderSpacing.xs)
        .padding(.horizontal, SonderSpacing.md)
        .contentShape(Rectangle())
    }
}

#Preview("Search Result") {
    VStack(spacing: 0) {
        PlaceSearchRow(
            name: "Blue Bottle Coffee",
            address: "123 Main St, San Francisco, CA"
        )
        Divider().padding(.leading, SonderSpacing.md)
        PlaceSearchRow(
            name: "Tartine Bakery",
            address: "600 Guerrero St, San Francisco, CA",
            icon: "fork.knife"
        )
    }
    .background(Color(.systemBackground))
}

#Preview("Recent Search") {
    RecentSearchRow(
        name: "Philz Coffee",
        address: "748 Van Ness Ave"
    ) {
        logger.debug("Delete tapped")
    }
    .background(Color(.systemBackground))
}
