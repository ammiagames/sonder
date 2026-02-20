//
//  ShareProfileCardView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import UIKit

/// Generates a shareable profile card image
struct ShareProfileCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService

    let placesCount: Int
    let citiesCount: Int
    let countriesCount: Int
    let topTags: [String]
    let mustSeeCount: Int

    @State private var cardImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: SonderSpacing.lg) {
                // Preview of the card
                profileCard
                    .padding(SonderSpacing.lg)

                Spacer()

                // Share button
                Button {
                    generateAndShare()
                } label: {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Your Journey")
                    }
                    .font(SonderTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SonderSpacing.md)
                    .background(SonderColors.terracotta)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }
                .padding(.horizontal, SonderSpacing.lg)
                .padding(.bottom, SonderSpacing.lg)
            }
            .background(SonderColors.cream)
            .navigationTitle("Share Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = cardImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: SonderSpacing.lg) {
            // Header
            HStack {
                Text("sonder")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
                Spacer()
            }

            // Avatar and name
            HStack(spacing: SonderSpacing.md) {
                // Avatar
                if let urlString = authService.currentUser?.avatarURL,
                   let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                        avatarPlaceholder
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                        .frame(width: 60, height: 60)
                }

                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    Text(authService.currentUser?.username ?? "Explorer")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)

                    if let bio = authService.currentUser?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            // Stats
            HStack(spacing: SonderSpacing.md) {
                statItem(value: "\(placesCount)", label: "Places")
                statItem(value: "\(citiesCount)", label: "Cities")
                statItem(value: "\(countriesCount)", label: "Countries")
            }

            // Favorites highlight
            if mustSeeCount > 0 {
                HStack(spacing: SonderSpacing.xs) {
                    Text("🔥")
                    Text("\(mustSeeCount) must-see places discovered")
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.inkMuted)
                    Spacer()
                }
            }

            // Tags
            if !topTags.isEmpty {
                HStack {
                    ForEach(topTags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(SonderTypography.caption)
                            .padding(.horizontal, SonderSpacing.xs)
                            .padding(.vertical, SonderSpacing.xxs)
                            .background(SonderColors.terracotta.opacity(0.12))
                            .foregroundStyle(SonderColors.terracotta)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(SonderSpacing.lg)
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusXl))
        .overlay {
            RoundedRectangle(cornerRadius: SonderSpacing.radiusXl)
                .stroke(SonderColors.warmGray, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: SonderSpacing.xxs) {
            Text(value)
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)
            Text(label)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .overlay {
                Text(authService.currentUser?.username.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    // MARK: - Actions

    private func generateAndShare() {
        // Render the card to an image
        let renderer = ImageRenderer(content: profileCard.frame(width: 350))
        renderer.scale = 3.0 // High resolution

        if let image = renderer.uiImage {
            cardImage = image
            showShareSheet = true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ShareProfileCardView(
        placesCount: 47,
        citiesCount: 12,
        countriesCount: 3,
        topTags: ["coffee", "ramen", "viewpoints", "bars"],
        mustSeeCount: 15
    )
}
