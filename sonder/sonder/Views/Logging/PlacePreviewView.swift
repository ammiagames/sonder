//
//  PlacePreviewView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import CoreLocation

/// Preview screen showing place details before logging
struct PlacePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var locationService
    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService

    let details: PlaceDetails
    let onLog: () -> Void

    @State private var isBookmarked = false
    @State private var isTogglingBookmark = false

    var body: some View {
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

                    // Editorial summary
                    if let summary = details.editorialSummary {
                        summarySection(summary)
                    }

                    // Place type tags
                    if !details.types.isEmpty {
                        typeTags
                    }

                    // Log button
                    logButton
                        .padding(.top, SonderSpacing.sm)
                }
                .padding(.horizontal, SonderSpacing.md)
                .padding(.vertical, SonderSpacing.md)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
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
                            .foregroundColor(isBookmarked ? SonderColors.terracotta : SonderColors.inkDark)
                    }
                }
                .disabled(isTogglingBookmark)
            }
        }
        .onAppear {
            checkBookmarkStatus()
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
                print("Error toggling bookmark: \(error)")
            }
            isTogglingBookmark = false
        }
    }

    // MARK: - Hero Photo

    private var heroPhoto: some View {
        Group {
            if let photoRef = details.photoReference,
               let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
                Color.clear.overlay {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 250)) {
                        photoPlaceholder
                    }
                }
                .clipped()
            } else {
                photoPlaceholder
            }
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(details.name)
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text(details.formattedAddress)
                .font(SonderTypography.subheadline)
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: SonderSpacing.md) {
            // Rating
            if let rating = details.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(SonderColors.ochre)
                    Text(String(format: "%.1f", rating))
                        .fontWeight(.medium)
                        .foregroundColor(SonderColors.inkDark)
                    if let count = details.userRatingCount {
                        Text("(\(count))")
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }
            }

            // Price level
            if let priceLevel = details.priceLevel {
                Text(priceLevel.displayString)
                    .fontWeight(.medium)
                    .foregroundColor(SonderColors.sage)
            }

            // Distance
            if let distance = distanceFromUser {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundColor(SonderColors.terracotta)
                    Text(formatDistance(distance))
                        .foregroundColor(SonderColors.inkDark)
                }
            }

            Spacer()
        }
        .font(SonderTypography.subheadline)
    }

    // MARK: - Summary Section

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("About")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            Text(summary)
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    // MARK: - Type Tags

    private var typeTags: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Category")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            TagFlowLayout(spacing: SonderSpacing.xs) {
                ForEach(displayTypes, id: \.self) { type in
                    Text(type)
                        .font(SonderTypography.caption)
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.warmGray)
                        .foregroundColor(SonderColors.inkDark)
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
                .foregroundColor(.white)
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
            print("Log tapped")
        }
    }
}
