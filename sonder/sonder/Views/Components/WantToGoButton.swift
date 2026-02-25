//
//  WantToGoButton.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "WantToGoButton")

/// Bookmark toggle button for saving places to Want to Go list.
/// Tap: if not saved → add to default list. If already saved → open list picker.
/// Long press: always opens list picker.
///
/// - Parameters:
///   - iconSize: SF Symbol font size (default 20). Pass 18 for list-row contexts.
///   - unsavedColor: Tint when not yet saved (default `inkDark`). Pass `inkLight` for list-row contexts.
struct WantToGoButton: View {
    let placeID: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?
    let sourceLogID: String?
    let iconSize: CGFloat
    let unsavedColor: Color

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService

    @State private var isLoading = false
    @State private var showListPicker = false

    init(
        placeID: String,
        placeName: String? = nil,
        placeAddress: String? = nil,
        photoReference: String? = nil,
        sourceLogID: String? = nil,
        iconSize: CGFloat = 20,
        unsavedColor: Color = SonderColors.inkDark
    ) {
        self.placeID = placeID
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.photoReference = photoReference
        self.sourceLogID = sourceLogID
        self.iconSize = iconSize
        self.unsavedColor = unsavedColor
    }

    /// Computed from the observable service so SwiftUI tracks changes
    private var isWantToGo: Bool {
        guard let userID = authService.currentUser?.id else { return false }
        return wantToGoService.isInWantToGo(placeID: placeID, userID: userID)
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                .font(.system(size: iconSize))
                .foregroundStyle(isWantToGo ? SonderColors.terracotta : unsavedColor)
        }
        .disabled(isLoading)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in showListPicker = true }
        )
        .sheet(isPresented: $showListPicker) {
            AddToListSheet(
                placeID: placeID,
                placeName: placeName,
                placeAddress: placeAddress,
                photoReference: photoReference,
                sourceLogID: sourceLogID
            )
        }
    }

    private func handleTap() {
        if isWantToGo {
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
                    placeID: placeID,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: sourceLogID
                )

                SonderHaptics.impact(.light)

                await ensurePlaceCached()
            } catch {
                logger.error("Error adding to want to go: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    /// Fetch and cache place details so the map has coordinates for this pin.
    private func ensurePlaceCached() async {
        if cacheService.getPlace(by: placeID) != nil { return }
        if let details = await placesService.getPlaceDetails(placeId: placeID) {
            _ = cacheService.cachePlace(from: details)
        }
    }
}

// MARK: - Large Want to Go Button

/// A larger version for inline use with label.
/// Tap: if not saved → add. If already saved → open list picker.
/// Long press: always opens list picker.
struct WantToGoButtonLarge: View {
    let placeID: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?
    let sourceLogID: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    @State private var isLoading = false
    @State private var showListPicker = false

    init(placeID: String, placeName: String? = nil, placeAddress: String? = nil, photoReference: String? = nil, sourceLogID: String? = nil) {
        self.placeID = placeID
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.photoReference = photoReference
        self.sourceLogID = sourceLogID
    }

    /// Computed from the observable service so SwiftUI tracks changes
    private var isWantToGo: Bool {
        guard let userID = authService.currentUser?.id else { return false }
        return wantToGoService.isInWantToGo(placeID: placeID, userID: userID)
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack {
                Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                Text(isWantToGo ? "Saved" : "Want to Go")
                    .font(SonderTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.sm)
            .background(isWantToGo ? SonderColors.warmGray : SonderColors.terracotta)
            .foregroundStyle(isWantToGo ? SonderColors.inkMuted : .white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .disabled(isLoading)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in showListPicker = true }
        )
        .sheet(isPresented: $showListPicker) {
            AddToListSheet(
                placeID: placeID,
                placeName: placeName,
                placeAddress: placeAddress,
                photoReference: photoReference,
                sourceLogID: sourceLogID
            )
        }
    }

    private func handleTap() {
        if isWantToGo {
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
                    placeID: placeID,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: sourceLogID
                )

                SonderHaptics.impact(.light)
            } catch {
                logger.error("Error adding to want to go: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WantToGoButton(placeID: "place123")

        WantToGoButtonLarge(placeID: "place123")
            .padding(.horizontal)
    }
}
