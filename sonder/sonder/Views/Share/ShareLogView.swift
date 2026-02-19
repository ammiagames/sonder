//
//  ShareLogView.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI
import SwiftData

// MARK: - Log Share Style

enum LogShareStyle: String, CaseIterable {
    case filmFrame, stamp, gradient, split, postcard, minimal

    var title: String {
        switch self {
        case .filmFrame: return "Film"
        case .stamp: return "Stamp"
        case .gradient: return "Gradient"
        case .split: return "Split"
        case .postcard: return "Postcard"
        case .minimal: return "Minimal"
        }
    }

    var icon: String {
        switch self {
        case .filmFrame: return "film"
        case .stamp: return "seal"
        case .gradient: return "square.fill"
        case .split: return "rectangle.split.2x1"
        case .postcard: return "envelope"
        case .minimal: return "square"
        }
    }
}

// MARK: - ShareLogView

struct ShareLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService

    let log: Log
    let place: Place

    @State private var selectedStyle: LogShareStyle = .gradient
    @State private var cardData: LogShareCardData?
    @State private var isLoading = true
    @State private var previewImage: UIImage?
    @State private var exportImage: UIImage?
    @State private var showShareSheet = false

    @Query(sort: \Log.createdAt) private var allLogs: [Log]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                        Text("Preparing card...")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    // Preview
                    ScrollView {
                        previewSection
                            .padding(.top, SonderSpacing.md)
                    }

                    // Style picker + share button
                    bottomControls
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Share Log")
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
                if let image = exportImage {
                    ShareSheet(items: [image])
                }
            }
        }
        .task {
            await loadPhoto()
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Group {
            if let preview = previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.horizontal, SonderSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func selectedCanvas(data: LogShareCardData) -> some View {
        switch selectedStyle {
        case .filmFrame:
            LogShareFilmFrame(data: data)
        case .stamp:
            LogShareStamp(data: data)
        case .gradient:
            LogShareGradient(data: data)
        case .split:
            LogShareSplit(data: data)
        case .postcard:
            LogSharePostcard(data: data)
        case .minimal:
            LogShareMinimal(data: data)
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: SonderSpacing.md) {
            // Style picker
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                Text("Choose a style")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .padding(.horizontal, SonderSpacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SonderSpacing.sm) {
                        ForEach(LogShareStyle.allCases, id: \.rawValue) { style in
                            styleButton(style)
                        }
                    }
                    .padding(.horizontal, SonderSpacing.lg)
                }
            }

            // Share button
            Button {
                generateExportImage()
            } label: {
                HStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Image")
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
        .padding(.top, SonderSpacing.md)
        .background(SonderColors.cream)
    }

    private func styleButton(_ style: LogShareStyle) -> some View {
        Button {
            selectedStyle = style
            renderPreview()
        } label: {
            VStack(spacing: SonderSpacing.xs) {
                Image(systemName: style.icon)
                    .font(.system(size: 20))
                Text(style.title)
                    .font(SonderTypography.caption)
            }
            .frame(width: 72)
            .padding(.vertical, SonderSpacing.sm)
            .background(selectedStyle == style ? SonderColors.terracotta.opacity(0.12) : SonderColors.warmGray)
            .foregroundStyle(selectedStyle == style ? SonderColors.terracotta : SonderColors.inkMuted)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .overlay {
                if selectedStyle == style {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                        .stroke(SonderColors.terracotta, lineWidth: 2)
                }
            }
        }
    }

    // MARK: - Photo Loading

    private func loadPhoto() async {
        // Determine photo URL: user photo first, then Google Places fallback
        let photoURL: URL? = {
            if let urlString = log.photoURL, let url = URL(string: urlString) {
                return url
            }
            if let photoRef = place.photoReference,
               let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
                return url
            }
            return nil
        }()

        // Download photo
        let photo: UIImage? = await {
            guard let url = photoURL else { return nil }
            return await ImageDownsampler.downloadImage(
                from: url,
                targetSize: CGSize(width: 1080, height: 1350)
            )
        }()

        // Compute milestone stats
        let userLogs = allLogs.filter { $0.userID == log.userID }
        let logsBeforeThis = userLogs.filter { $0.createdAt <= log.createdAt }
        let placeNumber = logsBeforeThis.count

        // Extract city from address (first component after splitting by comma)
        let cityName = extractCity(from: place.address)

        let username = authService.currentUser?.username ?? "traveler"

        await MainActor.run {
            self.cardData = LogShareCardData(
                placeName: place.name,
                cityName: cityName,
                rating: log.rating,
                photo: photo,
                note: log.note,
                tags: log.tags,
                date: log.createdAt,
                username: username,
                placeNumber: placeNumber > 0 ? placeNumber : nil
            )
            self.isLoading = false
            self.renderPreview()
        }
    }

    private func extractCity(from address: String) -> String {
        ProfileStatsService.extractCity(from: address) ?? address
    }

    // MARK: - Preview & Export Image Generation

    private func renderPreview() {
        guard let data = cardData else { return }

        let canvas = selectedCanvas(data: data)
            .frame(width: 1080, height: 1350)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0

        previewImage = renderer.uiImage
    }

    private func generateExportImage() {
        guard let data = cardData else { return }

        let canvas = selectedCanvas(data: data)
            .frame(width: 1080, height: 1350)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0

        if let image = renderer.uiImage {
            exportImage = image
            showShareSheet = true
        }
    }
}
