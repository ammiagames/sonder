//
//  WantToGoButton.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Bookmark toggle button for saving places to Want to Go list
struct WantToGoButton: View {
    let placeID: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?
    let sourceLogID: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    @State private var isLoading = false

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
            toggle()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20))
                        .foregroundColor(isWantToGo ? SonderColors.terracotta : SonderColors.inkDark)
                }
            }
        }
        .disabled(isLoading)
    }

    private func toggle() {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: placeID,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: sourceLogID
                )

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                print("Error toggling want to go: \(error)")
            }
            isLoading = false
        }
    }
}

// MARK: - Large Want to Go Button

/// A larger version for inline use with label
struct WantToGoButtonLarge: View {
    let placeID: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?
    let sourceLogID: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    @State private var isLoading = false

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
            toggle()
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(isWantToGo ? SonderColors.inkMuted : .white)
                } else {
                    Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                    Text(isWantToGo ? "Saved" : "Want to Go")
                        .font(SonderTypography.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.sm)
            .background(isWantToGo ? SonderColors.warmGray : SonderColors.terracotta)
            .foregroundColor(isWantToGo ? SonderColors.inkMuted : .white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .disabled(isLoading)
    }

    private func toggle() {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: placeID,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: sourceLogID
                )

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                print("Error toggling want to go: \(error)")
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
