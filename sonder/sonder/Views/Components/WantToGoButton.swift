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
    let sourceLogID: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    @State private var isWantToGo = false
    @State private var isLoading = false

    init(placeID: String, sourceLogID: String? = nil) {
        self.placeID = placeID
        self.sourceLogID = sourceLogID
    }

    var body: some View {
        Button {
            toggle()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 20))
                        .foregroundColor(isWantToGo ? .accentColor : .primary)
                }
            }
        }
        .disabled(isLoading)
        .onAppear {
            checkStatus()
        }
    }

    private func checkStatus() {
        guard let userID = authService.currentUser?.id else { return }
        isWantToGo = wantToGoService.isInWantToGo(placeID: placeID, userID: userID)
    }

    private func toggle() {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: placeID,
                    userID: userID,
                    sourceLogID: sourceLogID
                )
                isWantToGo.toggle()

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
    let sourceLogID: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    @State private var isWantToGo = false
    @State private var isLoading = false

    init(placeID: String, sourceLogID: String? = nil) {
        self.placeID = placeID
        self.sourceLogID = sourceLogID
    }

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(isWantToGo ? .secondary : .white)
                } else {
                    Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                    Text(isWantToGo ? "Saved" : "Want to Go")
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isWantToGo ? Color(.systemGray5) : Color.accentColor)
            .foregroundColor(isWantToGo ? .secondary : .white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
        .onAppear {
            checkStatus()
        }
    }

    private func checkStatus() {
        guard let userID = authService.currentUser?.id else { return }
        isWantToGo = wantToGoService.isInWantToGo(placeID: placeID, userID: userID)
    }

    private func toggle() {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: placeID,
                    userID: userID,
                    sourceLogID: sourceLogID
                )
                isWantToGo.toggle()

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
