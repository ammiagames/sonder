//
//  FeedLogDetailView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI
import CoreLocation

// MARK: - Feed Log Detail View (Magazine Spread)

/// Detail view for a feed item — magazine spread layout with frosted glass
/// content panel overlapping the hero photo, wax seal rating, and staggered entrance.
struct FeedLogDetailView: View {
    let feedItem: FeedItem

    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService

    @State private var selectedUserID: String?
    @State private var photoPageIndex = 0
    @State private var selectedPlaceDetails: PlaceDetails?
    @State private var isLoadingDetails = false
    @State private var placeToLog: Place?
    @State private var contentAppeared = false
    @State private var showDirectionsDialog = false
    @State private var detailFetchTask: Task<Void, Never>?

    private var hasPhotos: Bool { !feedItem.log.photoURLs.isEmpty }

    var body: some View {
        ScrollView {
            ZStack(alignment: .bottom) {
                // Full-bleed photo extends behind content
                VStack(spacing: 0) {
                    if hasPhotos {
                        FeedItemCardShared.photoCarousel(
                            photoURLs: feedItem.log.photoURLs,
                            pageIndex: $photoPageIndex,
                            height: 520
                        )
                    } else {
                        noPhotoHero
                            .frame(height: 520)
                    }

                    // Extra space for content overlap
                    Color.clear.frame(height: 320)
                }

                // Frosted content panel overlapping the photo
                VStack(alignment: .leading, spacing: SonderSpacing.lg) {
                    // Place name — tappable
                    Button(action: { fetchPlaceDetails() }) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                                Text(feedItem.place.name)
                                    .font(.system(size: 28, weight: .bold, design: .serif))
                                    .foregroundStyle(SonderColors.inkDark)

                                HStack(spacing: SonderSpacing.xxs) {
                                    Image(systemName: "mappin")
                                        .font(.system(size: 11))
                                    Text(feedItem.place.cityName)
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(SonderColors.inkMuted)
                            }

                            Spacer()

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(SonderColors.inkLight)
                                .padding(.bottom, 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 20)

                    // Wax seal rating
                    waxSealRating
                        .opacity(contentAppeared ? 1 : 0)
                        .offset(y: contentAppeared ? 0 : 20)

                    // Note
                    if let note = feedItem.log.note, !note.isEmpty {
                        noteQuote(note)
                            .opacity(contentAppeared ? 1 : 0)
                            .offset(y: contentAppeared ? 0 : 20)
                    }

                    // Tags
                    if !feedItem.log.tags.isEmpty {
                        FlowLayoutTags(tags: feedItem.log.tags)
                            .opacity(contentAppeared ? 1 : 0)
                            .offset(y: contentAppeared ? 0 : 20)
                    }

                    // Divider
                    Rectangle()
                        .fill(SonderColors.warmGray)
                        .frame(height: 1)

                    // Byline
                    byline
                        .opacity(contentAppeared ? 1 : 0)
                        .offset(y: contentAppeared ? 0 : 20)
                }
                .padding(SonderSpacing.lg)
                .padding(.bottom, 80)
                // Oversized rating emoji watermark behind content
                .background(alignment: .topTrailing) {
                    Text(feedItem.rating.emoji)
                        .font(.system(size: 140))
                        .opacity(0.05)
                        .rotationEffect(.degrees(-15))
                        .offset(x: 20, y: -10)
                }
                .background(.ultraThinMaterial)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: SonderSpacing.radiusXl,
                        topTrailingRadius: SonderSpacing.radiusXl
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
                .padding(.top, 400)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                contentAppeared = true
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDirectionsDialog = true
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SonderColors.inkMuted)
                        .toolbarIcon()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                WantToGoButton(
                    placeID: feedItem.place.id,
                    placeName: feedItem.place.name,
                    placeAddress: feedItem.place.address,
                    photoReference: feedItem.place.photoReference,
                    sourceLogID: feedItem.log.id
                )
            }
        }
        .directionsConfirmationDialog(
            isPresented: $showDirectionsDialog,
            coordinate: CLLocationCoordinate2D(latitude: feedItem.place.latitude, longitude: feedItem.place.longitude),
            name: feedItem.place.name,
            address: feedItem.place.address
        )
        .navigationDestination(item: $selectedUserID) { userID in
            OtherUserProfileView(userID: userID)
        }
        .navigationDestination(item: $selectedPlaceDetails) { details in
            PlacePreviewView(details: details) {
                let place = cacheService.cachePlace(from: details)
                placeToLog = place
            }
        }
        .fullScreenCover(item: $placeToLog) { place in
            NavigationStack {
                RatePlaceView(place: place) { _ in
                    selectedPlaceDetails = nil
                    placeToLog = nil
                }
            }
        }
        .overlay {
            if isLoadingDetails {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .scaleEffect(1.2)
                    }
            }
        }
    }

    // MARK: - No-Photo Hero

    private var noPhotoHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.25, blue: 0.18),
                    Color(red: 0.28, green: 0.20, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            SonderColors.pinColor(for: feedItem.rating).opacity(0.15)

            Image(systemName: feedItem.place.categoryIcon)
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.06))
                .rotationEffect(.degrees(-15))
        }
    }

    // MARK: - Wax Seal Rating

    private var waxSealRating: some View {
        let color = SonderColors.pinColor(for: feedItem.rating)
        return HStack(spacing: SonderSpacing.md) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                    .shadow(color: color.opacity(0.4), radius: 0, x: 1, y: 1)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.25),
                                .clear,
                                .black.opacity(0.1)
                            ],
                            center: .init(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
                    .frame(width: 64, height: 64)

                Text(feedItem.rating.emoji)
                    .font(.system(size: 28))
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(feedItem.rating.displayName)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                Text(feedItem.createdAt.formatted(date: .long, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()
        }
    }

    // MARK: - Pull-Quote Note

    private func noteQuote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            Rectangle()
                .fill(SonderColors.terracotta)
                .frame(width: 3)

            Text(note.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 17, design: .serif))
                .italic()
                .foregroundStyle(SonderColors.inkDark)
                .lineSpacing(5)
        }
    }

    // MARK: - Byline

    private var byline: some View {
        Button(action: { selectedUserID = feedItem.user.id }) {
            HStack(spacing: SonderSpacing.sm) {
                FeedItemCardShared.bylineAvatar(
                    avatarURL: feedItem.user.avatarURL,
                    username: feedItem.user.username,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(feedItem.user.username)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SonderColors.inkDark)
                    Text(feedItem.createdAt.relativeDisplay)
                        .font(.system(size: 13))
                        .foregroundStyle(SonderColors.inkMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fetch Place Details

    private func fetchPlaceDetails() {
        detailFetchTask?.cancel()
        detailFetchTask = Task {
            isLoadingDetails = true
            guard !Task.isCancelled else { isLoadingDetails = false; return }
            if let details = await placesService.getPlaceDetails(placeId: feedItem.place.id) {
                guard !Task.isCancelled else { isLoadingDetails = false; return }
                selectedPlaceDetails = details
            }
            isLoadingDetails = false
        }
    }
}
