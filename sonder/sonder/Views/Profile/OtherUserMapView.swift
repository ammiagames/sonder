//
//  OtherUserMapView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import MapKit

/// View another user's logged places on a map (read-only)
struct OtherUserMapView: View {
    let userID: String
    let username: String
    let logs: [FeedItem]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedItem: FeedItem?

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedItem) {
            ForEach(logs) { item in
                Marker(
                    item.place.name,
                    systemImage: markerIcon(for: item.rating),
                    coordinate: CLLocationCoordinate2D(
                        latitude: item.place.latitude,
                        longitude: item.place.longitude
                    )
                )
                .tint(markerColor(for: item.rating))
                .tag(item)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            if let item = selectedItem {
                selectedPlaceCard(item)
            }
        }
        .navigationTitle("\(username)'s Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fitMapToLogs()
        }
    }

    // MARK: - Selected Place Card

    private func selectedPlaceCard(_ item: FeedItem) -> some View {
        NavigationLink {
            FeedLogDetailView(feedItem: item)
        } label: {
            HStack(spacing: 12) {
                // Photo
                if let photoRef = item.place.photoReference,
                   let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                        photoPlaceholder
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    photoPlaceholder
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.place.name)
                            .font(SonderTypography.headline)
                            .lineLimit(1)
                            .foregroundColor(SonderColors.inkDark)

                        Spacer()

                        Text(item.rating.emoji)
                    }

                    Text(item.place.address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)

                    if let note = item.log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(SonderColors.inkLight)
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.cream.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(SonderSpacing.md)
        }
        .buttonStyle(.plain)
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    // MARK: - Helpers

    private func markerIcon(for rating: Rating) -> String {
        switch rating {
        case .mustSee: return "star.fill"
        case .solid: return "hand.thumbsup.fill"
        case .skip: return "hand.thumbsdown.fill"
        }
    }

    private func markerColor(for rating: Rating) -> Color {
        switch rating {
        case .mustSee: return SonderColors.ratingMustSee
        case .solid: return SonderColors.ratingSolid
        case .skip: return SonderColors.ratingSkip
        }
    }

    private func fitMapToLogs() {
        guard !logs.isEmpty else { return }

        let coordinates = logs.map {
            CLLocationCoordinate2D(latitude: $0.place.latitude, longitude: $0.place.longitude)
        }

        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )

        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

#Preview {
    NavigationStack {
        OtherUserMapView(
            userID: "user123",
            username: "johndoe",
            logs: []
        )
    }
}
