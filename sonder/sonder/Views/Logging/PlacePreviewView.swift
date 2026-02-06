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
                VStack(alignment: .leading, spacing: 16) {
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
                }
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            logButton
        }
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
                            .foregroundColor(isBookmarked ? .accentColor : .primary)
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        photoPlaceholder
                            .overlay { ProgressView() }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        photoPlaceholder
                    @unknown default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
            }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(details.name)
                .font(.title2)
                .fontWeight(.bold)

            Text(details.formattedAddress)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 16) {
            // Rating
            if let rating = details.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .fontWeight(.medium)
                    if let count = details.userRatingCount {
                        Text("(\(count))")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Price level
            if let priceLevel = details.priceLevel {
                Text(priceLevel.displayString)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }

            // Distance
            if let distance = distanceFromUser {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text(formatDistance(distance))
                }
            }

            Spacer()
        }
        .font(.subheadline)
    }

    // MARK: - Summary Section

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)

            Text(summary)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Type Tags

    private var typeTags: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.headline)

            TagFlowLayout(spacing: 8) {
                ForEach(displayTypes, id: \.self) { type in
                    Text(type)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Log Button

    private var logButton: some View {
        Button(action: onLog) {
            Text("Log This Place")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(Color(.systemBackground))
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
