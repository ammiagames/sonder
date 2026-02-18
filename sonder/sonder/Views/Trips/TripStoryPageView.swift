//
//  TripStoryPageView.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI

/// Full-screen swipe-through story experience for a trip's logs
struct TripStoryPageView: View {
    @Environment(\.dismiss) private var dismiss

    let logs: [Log]
    let places: [Place]
    let tripName: String
    let startIndex: Int

    @State private var currentIndex: Int

    init(logs: [Log], places: [Place], tripName: String, startIndex: Int) {
        self.logs = logs
        self.places = places
        self.tripName = tripName
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            SonderColors.cream
                .ignoresSafeArea()

            // Pages
            TabView(selection: $currentIndex) {
                ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                    let place = places.first(where: { $0.id == log.placeID })
                    StoryPage(log: log, place: place)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

            // Top overlay: progress bar + controls
            topOverlay
        }
        .statusBarHidden()
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        VStack(spacing: SonderSpacing.xs) {
            // Progress bar
            progressBar

            // Controls row
            HStack {
                // Trip name
                Text(tripName)
                    .font(SonderTypography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                Spacer()

                // Page counter
                Text("\(currentIndex + 1) / \(logs.count)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SonderColors.inkMuted)

                // Close button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SonderColors.inkDark)
                        .frame(width: 32, height: 32)
                        .background(SonderColors.warmGray)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.top, SonderSpacing.xs)
        .padding(.bottom, SonderSpacing.xs)
        .background(
            SonderColors.cream.opacity(0.95)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<logs.count, id: \.self) { i in
                Capsule()
                    .fill(i <= currentIndex ? SonderColors.terracotta : SonderColors.warmGrayDark.opacity(0.5))
                    .frame(height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentIndex)
    }
}

// MARK: - Story Page

private struct StoryPage: View {
    let log: Log
    let place: Place?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Photo
                photoView
                    .frame(height: 400)
                    .frame(maxWidth: .infinity)
                    .clipped()

                // Content
                VStack(alignment: .leading, spacing: SonderSpacing.md) {
                    // Place name
                    Text(place?.name ?? "Unknown Place")
                        .font(SonderTypography.largeTitle)
                        .foregroundStyle(SonderColors.inkDark)

                    // Address
                    if let address = place?.address {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 12))
                            Text(address)
                        }
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.inkMuted)
                    }

                    // Rating pill
                    ratingPill

                    // Date
                    Text(log.createdAt.formatted(date: .long, time: .shortened))
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)

                    // Note
                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkDark)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Tags
                    if !log.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: SonderSpacing.xxs) {
                                ForEach(log.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(SonderTypography.caption)
                                        .foregroundStyle(SonderColors.terracotta)
                                        .padding(.horizontal, SonderSpacing.xs)
                                        .padding(.vertical, 4)
                                        .background(SonderColors.terracotta.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(SonderSpacing.lg)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Rating Pill

    private var ratingPill: some View {
        HStack(spacing: 6) {
            Text(log.rating.emoji)
                .font(.system(size: 16))
            Text(log.rating.displayName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(SonderColors.pinColor(for: log.rating).opacity(0.15))
        .foregroundStyle(SonderColors.pinColor(for: log.rating))
        .clipShape(Capsule())
    }

    // MARK: - Photo Chain

    @ViewBuilder
    private var photoView: some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 400)) {
                placePhotoView
            }
        } else {
            placePhotoView
        }
    }

    @ViewBuilder
    private var placePhotoView: some View {
        if let photoRef = place?.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 400)) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
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
                    .font(.system(size: 40))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.5))
            }
    }
}

#Preview {
    TripStoryPageView(
        logs: [
            Log(
                userID: "user1",
                placeID: "place1",
                rating: .mustSee,
                note: "Amazing coffee! The pour-over was exceptional.",
                tags: ["coffee", "cafe"]
            ),
            Log(
                userID: "user1",
                placeID: "place2",
                rating: .solid,
                note: "Great ramen spot.",
                tags: ["ramen", "japanese"]
            )
        ],
        places: [
            Place(id: "place1", name: "Blue Bottle Coffee", address: "123 Main St, San Francisco", latitude: 37.77, longitude: -122.41),
            Place(id: "place2", name: "Mensho Tokyo", address: "456 Market St, San Francisco", latitude: 37.78, longitude: -122.40)
        ],
        tripName: "Japan 2024",
        startIndex: 0
    )
}
