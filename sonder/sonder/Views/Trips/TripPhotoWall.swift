//
//  TripPhotoWall.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Masonry photo grid of all trip photos — tap any photo to expand into the editorial entry.
struct TripPhotoWall: View {
    @Environment(\.dismiss) private var dismiss

    let tripName: String
    let logs: [Log]
    let places: [Place]

    @State private var selectedLog: Log?
    @Namespace private var photoNamespace

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    /// Logs that have photos, sorted chronologically
    private var photoLogs: [Log] {
        logs.filter { $0.photoURL != nil || placesByID[$0.placeID]?.photoReference != nil }
            .sorted { $0.visitedAt < $1.visitedAt }
    }

    /// Split into two columns for masonry
    private var columns: ([Log], [Log]) {
        var left: [Log] = []
        var right: [Log] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for log in photoLogs {
            let height = estimatedHeight(for: log)
            if leftHeight <= rightHeight {
                left.append(log)
                leftHeight += height
            } else {
                right.append(log)
                rightHeight += height
            }
        }
        return (left, right)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SonderColors.cream.ignoresSafeArea()

                if photoLogs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        // Trip header
                        VStack(spacing: 4) {
                            Text(tripName)
                                .font(.system(size: 24, weight: .light, design: .serif))
                                .foregroundColor(SonderColors.inkDark)
                            Text("\(photoLogs.count) moments".uppercased())
                                .font(.system(size: 11, weight: .medium))
                                .tracking(2.0)
                                .foregroundColor(SonderColors.inkLight)
                        }
                        .padding(.vertical, 24)

                        // Masonry grid
                        HStack(alignment: .top, spacing: 2) {
                            LazyVStack(spacing: 2) {
                                ForEach(columns.0, id: \.id) { log in
                                    photoCell(log: log)
                                }
                            }
                            LazyVStack(spacing: 2) {
                                ForEach(columns.1, id: \.id) { log in
                                    photoCell(log: log)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
                    }
                }
            }
            .sheet(item: $selectedLog) { log in
                if let place = placesByID[log.placeID] {
                    PhotoWallDetail(log: log, place: place)
                }
            }
        }
    }

    // MARK: - Photo Cell

    private func photoCell(log: Log) -> some View {
        let place = placesByID[log.placeID]
        let aspectRatio = estimatedAspectRatio(for: log)

        return Button {
            selectedLog = log
        } label: {
            ZStack(alignment: .bottomLeading) {
                photoImage(log: log, place: place)
                    .aspectRatio(aspectRatio, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                // Subtle overlay with rating
                LinearGradient(
                    colors: [.clear, .black.opacity(0.3)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 4) {
                    Text(log.rating.emoji)
                        .font(.system(size: 10))
                    if let name = place?.name {
                        Text(name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                .padding(6)
            }
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: log.id, in: photoNamespace)
    }

    // MARK: - Photo Loading

    @ViewBuilder
    private func photoImage(log: Log, place: Place?) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 300)) {
                placePhoto(place: place)
            }
        } else {
            placePhoto(place: place)
        }
    }

    @ViewBuilder
    private func placePhoto(place: Place?) -> some View {
        if let photoRef = place?.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 400) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 300)) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(SonderColors.warmGray)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(SonderColors.inkLight)
            Text("No photos yet")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    // MARK: - Layout Helpers

    private func estimatedHeight(for log: Log) -> CGFloat {
        // Vary heights for visual interest
        let hash = abs(log.id.hashValue)
        let variants: [CGFloat] = [160, 200, 180, 220, 170]
        return variants[hash % variants.count]
    }

    private func estimatedAspectRatio(for log: Log) -> CGFloat {
        let hash = abs(log.id.hashValue)
        let variants: [CGFloat] = [3/4, 1, 4/5, 3/4, 2/3]
        return variants[hash % variants.count]
    }
}

// MARK: - Detail Sheet

private struct PhotoWallDetail: View {
    let log: Log
    let place: Place

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Full photo
                detailPhoto
                    .aspectRatio(3/2, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 12) {
                    // Place name
                    Text(place.name)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundColor(SonderColors.inkDark)
                        .padding(.top, 16)

                    // Rating
                    HStack(spacing: 6) {
                        Text(log.rating.emoji)
                            .font(.system(size: 18))
                        Text(log.rating.displayName)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(SonderColors.pinColor(for: log.rating))
                    }

                    // Address
                    Text(place.address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)

                    // Note
                    if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        Text(note)
                            .font(.system(size: 16))
                            .foregroundColor(SonderColors.inkDark)
                            .lineSpacing(7)
                            .padding(.top, 8)
                    }

                    // Tags
                    if !log.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(log.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.terracotta)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(SonderColors.terracotta.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 8)
                    }

                    // Date
                    Text(log.visitedAt.formatted(date: .long, time: .omitted))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(SonderColors.inkLight)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(SonderColors.cream)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var detailPhoto: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 400)) {
                placeDetailPhoto
            }
        } else {
            placeDetailPhoto
        }
    }

    @ViewBuilder
    private var placeDetailPhoto: some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 400)) {
                Rectangle().fill(SonderColors.warmGray)
            }
        } else {
            Rectangle().fill(SonderColors.warmGray)
                .frame(height: 200)
        }
    }
}
