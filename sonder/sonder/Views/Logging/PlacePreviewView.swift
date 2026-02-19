//
//  PlacePreviewView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import UIKit
import CoreLocation
import MapKit
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "PlacePreviewView")

/// Preview screen showing place details before logging
struct PlacePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(LocationService.self) private var locationService
    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(PlacesCacheService.self) private var cacheService

    let details: PlaceDetails
    let onLog: () -> Void

    @State private var isBookmarked = false
    @State private var isTogglingBookmark = false
    @State private var heroImage: UIImage?
    @State private var photoLoadFailed = false
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero photo
                    heroPhoto

                    // Content
                    VStack(alignment: .leading, spacing: SonderSpacing.md) {
                        // Name and address
                        nameSection

                        // Stats row: rating, price, distance
                        statsRow

                        // Mini map
                        miniMapSection

                        // Editorial summary
                        if let summary = details.editorialSummary {
                            summarySection(summary)
                        }

                        // Place type tags
                        if !details.types.isEmpty {
                            typeTags
                        }
                    }
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.md)
                    .padding(.bottom, 80)
                }
            }
            .scrollContentBackground(.hidden)

            // Sticky bottom button
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [SonderColors.cream.opacity(0), SonderColors.cream],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)

                logButton
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.bottom, SonderSpacing.md)
                    .background(SonderColors.cream)
            }
        }
        .background(SonderColors.cream)
        .navigationTitle("Place Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleBookmark()
                } label: {
                    if isTogglingBookmark {
                        ProgressView()
                    } else {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isBookmarked ? SonderColors.terracotta : SonderColors.inkDark)
                    }
                }
                .disabled(isTogglingBookmark)
            }
        }
        .onAppear {
            checkBookmarkStatus()
        }
        .task {
            await loadHeroPhoto()
        }
    }

    private func checkBookmarkStatus() {
        guard let userID = authService.currentUser?.id else { return }
        isBookmarked = wantToGoService.isInWantToGo(placeID: details.placeId, userID: userID)
    }

    private func toggleBookmark() {
        guard let userID = authService.currentUser?.id else { return }

        isTogglingBookmark = true

        Task {
            do {
                try await wantToGoService.toggleWantToGo(
                    placeID: details.placeId,
                    userID: userID,
                    placeName: details.name,
                    placeAddress: details.formattedAddress,
                    photoReference: details.photoReference,
                    sourceLogID: nil
                )
                isBookmarked.toggle()

                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                logger.error("Error toggling bookmark: \(error.localizedDescription)")
            }
            isTogglingBookmark = false
        }
    }

    // MARK: - Hero Photo

    @ViewBuilder
    private var heroPhoto: some View {
        if !photoLoadFailed {
            Color.clear
                .frame(height: 250)
                .overlay {
                    ZStack {
                        // Shimmer placeholder (visible until image loads)
                        if heroImage == nil {
                            Rectangle()
                                .fill(SonderColors.warmGray)
                                .overlay { shimmerOverlay }
                                .transition(.opacity)
                        }

                        // Loaded image — placed in overlay so .fill doesn't widen the layout
                        if let heroImage {
                            Image(uiImage: heroImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        }
                    }
                }
                .clipped()
                .animation(.easeInOut(duration: 0.3), value: heroImage != nil)
        }
    }

    private var shimmerOverlay: some View {
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
            .offset(x: shimmerPhase * width * 1.5)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerPhase = 1
                }
            }
        }
        .clipped()
    }

    private func loadHeroPhoto() async {
        // Check file cache first (instant offline display)
        if let cached = cacheService.getCachedPhoto(for: details.placeId) {
            heroImage = cached
            return
        }

        // Try REST URL first if we have a photo reference.
        if let photoRef = details.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            let image = await ImageDownsampler.downloadImage(
                from: url,
                targetSize: CGSize(width: 400, height: 250),
                cacheMode: .transient
            )
            if let image {
                heroImage = image
                cacheService.cachePhoto(image, for: details.placeId)
                return
            }
        }

        // Fallback: load photo directly via SDK
        let image = await placesService.loadPlacePhoto(
            placeId: details.placeId,
            maxSize: CGSize(width: 800, height: 600)
        )

        if let image {
            heroImage = image
            cacheService.cachePhoto(image, for: details.placeId)
        } else {
            // No photo available — smoothly collapse the placeholder
            withAnimation(.easeInOut(duration: 0.3)) {
                photoLoadFailed = true
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(details.name)
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            Text(details.formattedAddress)
                .font(SonderTypography.subheadline)
                .foregroundStyle(SonderColors.inkMuted)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: SonderSpacing.md) {
            // Rating
            if let rating = details.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(SonderColors.ochre)
                    Text(String(format: "%.1f", rating))
                        .fontWeight(.medium)
                        .foregroundStyle(SonderColors.inkDark)
                    if let count = details.userRatingCount {
                        Text("(\(count))")
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }
            }

            // Price level
            if let priceLevel = details.priceLevel {
                Text(priceLevel.displayString)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.sage)
            }

            // Distance
            if let distance = distanceFromUser {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(SonderColors.terracotta)
                    Text(formatDistance(distance))
                        .foregroundStyle(SonderColors.inkDark)
                }
            }

            Spacer()
        }
        .font(SonderTypography.subheadline)
    }

    // MARK: - Mini Map

    private var placeCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: details.latitude, longitude: details.longitude)
    }

    private var miniMapSection: some View {
        Button {
            let placemark = MKPlacemark(coordinate: placeCoordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = details.name
            mapItem.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
            ])
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: placeCoordinate,
                    latitudinalMeters: 800,
                    longitudinalMeters: 800
                ))) {
                    Marker(details.name, coordinate: placeCoordinate)
                        .tint(SonderColors.terracotta)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .allowsHitTesting(false)

                // "Open in Maps" pill
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Directions")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, SonderSpacing.sm)
                .padding(.vertical, 6)
                .background(SonderColors.terracotta)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .padding(SonderSpacing.sm)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Section

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("About")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Text(summary)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
    }

    // MARK: - Type Tags

    private var typeTags: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Category")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            TagFlowLayout(spacing: SonderSpacing.xs) {
                ForEach(displayTypes, id: \.self) { type in
                    Text(type)
                        .font(SonderTypography.caption)
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.warmGray)
                        .foregroundStyle(SonderColors.inkDark)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Log Button

    private var logButton: some View {
        Button(action: onLog) {
            Text("Log This Place")
                .font(SonderTypography.headline)
                .frame(maxWidth: .infinity)
                .padding(SonderSpacing.md)
                .background(SonderColors.terracotta)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
    }

    // MARK: - Helpers

    private var distanceFromUser: CLLocationDistance? {
        guard let userLocation = locationService.currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: details.latitude, longitude: details.longitude)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        return userCLLocation.distance(from: placeLocation)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            let miles = meters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }

    /// Convert API types to readable display names
    private var displayTypes: [String] {
        details.types
            .filter { !$0.starts(with: "point_of_interest") && !$0.starts(with: "establishment") }
            .prefix(5)
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
    }
}

// MARK: - Flow Layout for Tags

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, spacing: spacing, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, spacing: spacing, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

#Preview {
    NavigationStack {
        PlacePreviewView(
            details: PlaceDetails(
                placeId: "test",
                name: "Blue Bottle Coffee",
                formattedAddress: "123 Main St, San Francisco, CA 94102",
                latitude: 37.7749,
                longitude: -122.4194,
                types: ["cafe", "coffee_shop", "food", "store"],
                photoReference: nil,
                rating: 4.5,
                userRatingCount: 1234,
                priceLevel: .moderate,
                editorialSummary: "Trendy coffee shop known for slow-drip coffee and minimalist aesthetic. Popular spot for remote workers and coffee enthusiasts."
            )
        ) {
            logger.debug("Log tapped")
        }
    }
}
