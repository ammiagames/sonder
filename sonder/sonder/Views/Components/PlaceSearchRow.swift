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
    let onBookmark: (() -> Void)?

    init(name: String, address: String, photoReference: String? = nil, icon: String? = nil, placeId: String? = nil, distanceText: String? = nil, onBookmark: (() -> Void)? = nil) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.icon = icon
        self.placeId = placeId
        self.distanceText = distanceText
        self.onBookmark = onBookmark
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

            // Bookmark button (if provided)
            if let placeId = placeId, onBookmark != nil {
                BookmarkButton(placeId: placeId, placeName: name, placeAddress: address, photoReference: photoReference)
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

/// Inline bookmark button for search rows.
/// Tap: if not saved → add to default list. If already saved → open list picker.
/// Long press: always opens list picker.
struct BookmarkButton: View {
    let placeId: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService

    @State private var isLoading = false
    @State private var showListPicker = false

    init(placeId: String, placeName: String? = nil, placeAddress: String? = nil, photoReference: String? = nil) {
        self.placeId = placeId
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.photoReference = photoReference
    }

    private var isBookmarked: Bool {
        guard let userID = authService.currentUser?.id else { return false }
        return wantToGoService.isInWantToGo(placeID: placeId, userID: userID)
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundStyle(isBookmarked ? SonderColors.terracotta : SonderColors.inkLight)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in showListPicker = true }
        )
        .sheet(isPresented: $showListPicker) {
            AddToListSheet(
                placeID: placeId,
                placeName: placeName,
                placeAddress: placeAddress,
                photoReference: photoReference,
                sourceLogID: nil
            )
        }
    }

    private func handleTap() {
        if isBookmarked {
            // Already saved — open list picker to manage lists or unsave
            showListPicker = true
        } else {
            addToSaved()
        }
    }

    private func addToSaved() {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true

        Task {
            do {
                try await wantToGoService.addToWantToGo(
                    placeID: placeId,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: nil
                )

                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                await ensurePlaceCached()
            } catch {
                logger.error("Error adding bookmark: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    /// Fetch and cache place details so the map has coordinates for this pin.
    private func ensurePlaceCached() async {
        if cacheService.getPlace(by: placeId) != nil { return }
        if let details = await placesService.getPlaceDetails(placeId: placeId) {
            _ = cacheService.cachePlace(from: details)
        }
    }
}

/// Row for recent search with delete action
struct RecentSearchRow: View {
    let name: String
    let address: String
    let photoReference: String?
    let placeId: String?
    let onDelete: () -> Void


    init(name: String, address: String, photoReference: String? = nil, placeId: String? = nil, onDelete: @escaping () -> Void) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.placeId = placeId
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

            // Bookmark button
            if let placeId = placeId {
                BookmarkButton(placeId: placeId, placeName: name, placeAddress: address, photoReference: photoReference)
            }

            // Delete button
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
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
