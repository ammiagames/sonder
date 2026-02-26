//
//  PhotoSuggestionsRow.swift
//  sonder
//
//  Shared photo suggestion strip used by RatePlaceView and LogViewScreen.
//

import SwiftUI
import UIKit
import Photos

/// Horizontal strip of nearby photo suggestions from the user's library.
/// Handles authorization prompts, loading shimmer, empty state, and results.
struct PhotoSuggestionsRow: View {
    @Environment(PhotoSuggestionService.self) private var service

    let thumbnailSize: CGFloat
    let canAddMore: Bool
    let showEmptyState: Bool
    let onImageAdded: (UIImage) -> Void

    init(thumbnailSize: CGFloat, canAddMore: Bool, showEmptyState: Bool = true, onImageAdded: @escaping (UIImage) -> Void) {
        self.thumbnailSize = thumbnailSize
        self.canAddMore = canAddMore
        self.showEmptyState = showEmptyState
        self.onImageAdded = onImageAdded
    }

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var loadingID: String?

    var body: some View {
        let suggestions = service.suggestions
        let auth = service.authorizationLevel

        if auth == .denied {
            authPrompt(
                icon: "photo.on.rectangle.angled",
                message: "Allow photo access for nearby suggestions"
            )
        } else if auth == .limited && suggestions.isEmpty && !service.isLoading {
            authPrompt(
                icon: "photo.badge.exclamationmark",
                message: "Allow full access for better suggestions"
            )
        } else if service.isLoading && suggestions.isEmpty {
            loadingView
        } else if !suggestions.isEmpty && canAddMore {
            suggestionsView(suggestions)
        } else if showEmptyState && suggestions.isEmpty && !service.isLoading && (auth == .full || auth == .limited) {
            emptyView
        }
    }

    // MARK: - Auth Prompt

    private func authPrompt(icon: String, message: String) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(SonderColors.inkMuted)

            Text(message)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)

            Spacer()

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Settings")
                    .font(SonderTypography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(SonderColors.terracotta)
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Loading Shimmer

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(SonderColors.terracotta)
                Text("Finding nearby photos...")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                            .fill(SonderColors.warmGray)
                            .frame(width: thumbnailSize, height: thumbnailSize)
                            .overlay(ShimmerEffect())
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(SonderColors.inkMuted)
            Text("No nearby photos found")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
        }
    }

    // MARK: - Suggestions

    private func suggestionsView(_ suggestions: [PHAsset]) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(SonderColors.terracotta)
                Text("Nearby photos")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(suggestions, id: \.localIdentifier) { asset in
                        Button {
                            addSuggestion(asset)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                Group {
                                    if let thumb = thumbnails[asset.localIdentifier] {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Rectangle()
                                            .fill(SonderColors.warmGray)
                                    }
                                }
                                .frame(width: thumbnailSize, height: thumbnailSize)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                                if loadingID == asset.localIdentifier {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(width: thumbnailSize, height: thumbnailSize)
                                        .background(.black.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white, SonderColors.terracotta)
                                        .shadow(radius: 2)
                                        .padding(4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingID != nil)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .task {
                            guard thumbnails[asset.localIdentifier] == nil else { return }
                            if let thumb = await service.loadThumbnail(for: asset) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    thumbnails[asset.localIdentifier] = thumb
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Add Suggestion

    private func addSuggestion(_ asset: PHAsset) {
        guard canAddMore, loadingID == nil else { return }
        loadingID = asset.localIdentifier

        Task {
            if let image = await service.loadFullImage(for: asset) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    service.suggestions.removeAll { $0.localIdentifier == asset.localIdentifier }
                    thumbnails.removeValue(forKey: asset.localIdentifier)
                }
                onImageAdded(image)
                SonderHaptics.impact(.light)
            }
            loadingID = nil
        }
    }
}

// MARK: - Shimmer Effect

private struct ShimmerEffect: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.25), location: 0.4),
                    .init(color: Color.white.opacity(0.35), location: 0.5),
                    .init(color: Color.white.opacity(0.25), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 1.5)
            .offset(x: phase * width * 1.5)
        }
        .clipped()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
        .onDisappear {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { phase = -1 }
        }
    }
}
