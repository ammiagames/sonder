//
//  PlaceSearchRow.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Row component for displaying a place search result
struct PlaceSearchRow: View {
    let name: String
    let address: String
    let photoReference: String?
    let icon: String?
    let placeId: String?
    let onBookmark: (() -> Void)?

    init(name: String, address: String, photoReference: String? = nil, icon: String? = nil, placeId: String? = nil, onBookmark: (() -> Void)? = nil) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.icon = icon
        self.placeId = placeId
        self.onBookmark = onBookmark
    }

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo or icon
            if photoReference != nil {
                PlacePhotoView(photoReference: photoReference, size: 44, cornerRadius: SonderSpacing.radiusSm)
            } else {
                Image(systemName: icon ?? "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(SonderColors.terracotta)
                    .frame(width: 44, height: 44)
                    .background(SonderColors.terracotta.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            }

            // Place info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SonderTypography.body)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                if !address.isEmpty {
                    Text(address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Bookmark button (if provided)
            if let placeId = placeId, onBookmark != nil {
                BookmarkButton(placeId: placeId, placeName: name, placeAddress: address, photoReference: photoReference)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SonderColors.inkLight)
        }
        .padding(.vertical, SonderSpacing.xs)
        .padding(.horizontal, SonderSpacing.md)
        .contentShape(Rectangle())
    }
}

/// Inline bookmark button for search rows
struct BookmarkButton: View {
    let placeId: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService

    @State private var isBookmarked = false
    @State private var isLoading = false

    init(placeId: String, placeName: String? = nil, placeAddress: String? = nil, photoReference: String? = nil) {
        self.placeId = placeId
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.photoReference = photoReference
    }

    var body: some View {
        Button {
            toggleBookmark()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18))
                        .foregroundColor(isBookmarked ? SonderColors.terracotta : SonderColors.inkLight)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onAppear {
            checkStatus()
        }
    }

    private func checkStatus() {
        guard let userID = authService.currentUser?.id else { return }
        isBookmarked = wantToGoService.isInWantToGo(placeID: placeId, userID: userID)
    }

    private func toggleBookmark() {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true
        let wasBookmarked = isBookmarked

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: placeId,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: nil
                )
                isBookmarked.toggle()

                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                // When adding a bookmark, ensure the place is cached locally with
                // coordinates so the map can display the pin immediately.
                if !wasBookmarked {
                    await ensurePlaceCached()
                }
            } catch {
                print("Error toggling bookmark: \(error)")
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

    @State private var isDeletePressed = false

    init(name: String, address: String, photoReference: String? = nil, placeId: String? = nil, onDelete: @escaping () -> Void) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.placeId = placeId
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo with clock badge
            ZStack(alignment: .bottomTrailing) {
                PlacePhotoView(photoReference: photoReference, size: 44, cornerRadius: SonderSpacing.radiusSm)

                // Clock badge overlay
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(SonderColors.inkMuted)
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }

            // Place info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SonderTypography.body)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                if !address.isEmpty {
                    Text(address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Bookmark button
            if let placeId = placeId {
                BookmarkButton(placeId: placeId, placeName: name, placeAddress: address, photoReference: photoReference)
            }

            // Delete button with press animation
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(SonderColors.inkLight)
                .scaleEffect(isDeletePressed ? 0.8 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isDeletePressed)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isDeletePressed {
                                isDeletePressed = true
                            }
                        }
                        .onEnded { _ in
                            isDeletePressed = false
                            // Haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            onDelete()
                        }
                )
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
        Divider().padding(.leading, 68)
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
        print("Delete tapped")
    }
    .background(Color(.systemBackground))
}
