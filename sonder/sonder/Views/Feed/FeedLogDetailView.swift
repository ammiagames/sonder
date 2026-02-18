//
//  FeedLogDetailView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

// MARK: - Detail Style Enum

private enum DetailStyle: String, CaseIterable {
    case cinematic, journal, story

    var label: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .journal: return "Journal"
        case .story: return "Story"
        }
    }
}

// MARK: - Outer Shell

/// Detail view for a feed item — three switchable visual variants.
struct FeedLogDetailView: View {
    let feedItem: FeedItem

    @State private var style: DetailStyle = .cinematic
    @State private var selectedUserID: String?
    @State private var photoPageIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            switch style {
            case .cinematic:
                CinematicDetailView(
                    feedItem: feedItem,
                    photoPageIndex: $photoPageIndex,
                    onUserTap: { selectedUserID = feedItem.user.id }
                )
            case .journal:
                JournalDetailView(
                    feedItem: feedItem,
                    photoPageIndex: $photoPageIndex,
                    onUserTap: { selectedUserID = feedItem.user.id }
                )
            case .story:
                StoryDetailView(
                    feedItem: feedItem,
                    photoPageIndex: $photoPageIndex,
                    onUserTap: { selectedUserID = feedItem.user.id }
                )
            }

            stylePicker
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .navigationDestination(item: $selectedUserID) { userID in
            OtherUserProfileView(userID: userID)
        }
    }

    // MARK: - Style Picker Pill

    private var stylePicker: some View {
        HStack(spacing: 0) {
            ForEach(DetailStyle.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        style = option
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: style == option ? .semibold : .regular))
                        .foregroundStyle(style == option ? SonderColors.inkDark : SonderColors.inkMuted)
                        .padding(.horizontal, SonderSpacing.md)
                        .padding(.vertical, SonderSpacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.bottom, SonderSpacing.lg)
    }
}

// MARK: - Shared Helpers

private let pinColor = { (item: FeedItem) -> Color in
    SonderColors.pinColor(for: item.rating)
}

// MARK: =============================================
// MARK: Variant A — Cinematic Hero
// MARK: =============================================

private struct CinematicDetailView: View {
    let feedItem: FeedItem
    @Binding var photoPageIndex: Int
    let onUserTap: () -> Void

    private var hasPhotos: Bool { !feedItem.log.photoURLs.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Photo hero / fallback
                ZStack(alignment: .bottomLeading) {
                    if hasPhotos {
                        FeedItemCardShared.photoCarousel(
                            photoURLs: feedItem.log.photoURLs,
                            pageIndex: $photoPageIndex,
                            height: 420
                        )
                    } else {
                        noPhotoHero
                    }

                    // Gradient overlay
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.6), location: 0.55),
                            .init(color: .black.opacity(0.85), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    // Place name on photo
                    VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                        Text(feedItem.place.name)
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(.white)

                        HStack(spacing: SonderSpacing.xxs) {
                            Image(systemName: "mappin")
                                .font(.system(size: 11))
                            Text(feedItem.place.cityName)
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(SonderSpacing.lg)
                }
                .frame(height: hasPhotos ? 420 : 320)
                .clipped()

                // Content area
                VStack(alignment: .leading, spacing: SonderSpacing.lg) {
                    // Rating badge
                    ratingBadge

                    // Note
                    if let note = feedItem.log.note, !note.isEmpty {
                        noteQuote(note)
                    }

                    // Tags
                    if !feedItem.log.tags.isEmpty {
                        FlowLayoutTags(tags: feedItem.log.tags)
                    }

                    // Divider
                    Rectangle()
                        .fill(SonderColors.warmGray)
                        .frame(height: 1)

                    // Byline
                    byline
                }
                .padding(SonderSpacing.lg)
                .padding(.bottom, 80)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
    }

    // MARK: No-Photo Hero

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

            pinColor(feedItem).opacity(0.15)

            Image(systemName: feedItem.place.categoryIcon)
                .font(.system(size: 120, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.06))
                .rotationEffect(.degrees(-15))
        }
    }

    // MARK: Rating Badge

    private var ratingBadge: some View {
        HStack(spacing: SonderSpacing.sm) {
            Text(feedItem.rating.emoji)
                .font(.system(size: 36))

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
        .padding(SonderSpacing.md)
        .background(pinColor(feedItem).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: Pull-Quote Note

    private func noteQuote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            Rectangle()
                .fill(SonderColors.terracotta)
                .frame(width: 3)

            Text(note)
                .font(.system(size: 17, design: .serif))
                .italic()
                .foregroundStyle(SonderColors.inkDark)
                .lineSpacing(5)
        }
    }

    // MARK: Byline

    private var byline: some View {
        Button(action: onUserTap) {
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
}

// MARK: =============================================
// MARK: Variant B — Journal / Polaroid
// MARK: =============================================

private struct JournalDetailView: View {
    let feedItem: FeedItem
    @Binding var photoPageIndex: Int
    let onUserTap: () -> Void

    private var hasPhotos: Bool { !feedItem.log.photoURLs.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.lg) {
                Spacer().frame(height: SonderSpacing.md)

                // Polaroid
                polaroidFrame

                // Rating
                VStack(spacing: SonderSpacing.xxs) {
                    Text(feedItem.rating.emoji)
                        .font(.system(size: 56))
                    Text(feedItem.rating.displayName)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(SonderColors.inkDark)
                }
                .frame(maxWidth: .infinity)

                // Place name
                VStack(spacing: SonderSpacing.xxs) {
                    Text(feedItem.place.name)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(SonderColors.inkDark)
                        .multilineTextAlignment(.center)

                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                        Text(feedItem.place.address)
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SonderSpacing.lg)

                // City dateline
                Text(feedItem.place.cityName.uppercased())
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(SonderColors.terracotta)

                // Note
                if let note = feedItem.log.note, !note.isEmpty {
                    journalNote(note)
                }

                // Tags
                if !feedItem.log.tags.isEmpty {
                    FlowLayoutTags(tags: feedItem.log.tags)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, SonderSpacing.lg)
                }

                // Byline
                journalByline
                    .padding(.top, SonderSpacing.sm)

                Spacer().frame(height: 80)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
    }

    // MARK: Polaroid Frame

    private var polaroidFrame: some View {
        VStack(spacing: 0) {
            if hasPhotos {
                FeedItemCardShared.photoCarousel(
                    photoURLs: feedItem.log.photoURLs,
                    pageIndex: $photoPageIndex,
                    height: 340
                )
                .clipped()
            } else {
                // No-photo polaroid interior
                Rectangle()
                    .fill(SonderColors.cream)
                    .frame(height: 340)
                    .overlay {
                        Image(systemName: feedItem.place.categoryIcon)
                            .font(.system(size: 80, weight: .ultraLight))
                            .foregroundStyle(SonderColors.terracotta.opacity(0.2))
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .rotationEffect(.degrees(-1.5))
        .padding(.horizontal, SonderSpacing.xl)
    }

    // MARK: Journal Note with Curly Quotes

    private func journalNote(_ note: String) -> some View {
        VStack(spacing: SonderSpacing.xxs) {
            Text("\u{201C}")
                .font(.system(size: 40, weight: .thin, design: .serif))
                .foregroundStyle(SonderColors.terracotta.opacity(0.5))

            Text(note)
                .font(.system(size: 17, design: .serif))
                .italic()
                .foregroundStyle(SonderColors.inkDark)
                .lineSpacing(6)
                .multilineTextAlignment(.center)

            Text("\u{201D}")
                .font(.system(size: 40, weight: .thin, design: .serif))
                .foregroundStyle(SonderColors.terracotta.opacity(0.5))
        }
        .padding(.horizontal, SonderSpacing.xl)
    }

    // MARK: Journal Byline (centered)

    private var journalByline: some View {
        Button(action: onUserTap) {
            HStack(spacing: SonderSpacing.xs) {
                FeedItemCardShared.bylineAvatar(
                    avatarURL: feedItem.user.avatarURL,
                    username: feedItem.user.username,
                    size: 32
                )

                Text("@\(feedItem.user.username)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SonderColors.inkMuted)

                Text("\u{00B7}")
                    .foregroundStyle(SonderColors.inkLight)

                Text(feedItem.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(SonderColors.inkMuted)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: =============================================
// MARK: Variant C — Story (Card-based)
// MARK: =============================================

private struct StoryDetailView: View {
    let feedItem: FeedItem
    @Binding var photoPageIndex: Int
    let onUserTap: () -> Void

    private var hasPhotos: Bool { !feedItem.log.photoURLs.isEmpty }

    private let cardShadow: (Color, CGFloat, CGFloat) = (.black.opacity(0.06), 8, 2)

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.md) {
                // Parallax photo header
                parallaxHeader

                // Place card
                placeCard

                // Rating card
                ratingCard

                // Note + Tags card
                if feedItem.log.note != nil || !feedItem.log.tags.isEmpty {
                    noteTagsCard
                }

                // Byline card
                bylineCard

                Spacer().frame(height: 80)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
    }

    // MARK: Parallax Header

    private var parallaxHeader: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretchHeight = max(0, minY)

            Group {
                if hasPhotos {
                    FeedItemCardShared.photoCarousel(
                        photoURLs: feedItem.log.photoURLs,
                        pageIndex: $photoPageIndex,
                        height: 380 + stretchHeight
                    )
                } else {
                    // Warm gradient fallback
                    ZStack {
                        LinearGradient(
                            colors: [
                                SonderColors.terracotta.opacity(0.2),
                                SonderColors.ochre.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        Image(systemName: feedItem.place.categoryIcon)
                            .font(.system(size: 80, weight: .ultraLight))
                            .foregroundStyle(SonderColors.terracotta.opacity(0.15))
                    }
                    .frame(height: 380 + stretchHeight)
                }
            }
            .frame(height: 380 + stretchHeight)
            .clipped()
            .offset(y: minY > 0 ? -minY : 0)
        }
        .frame(height: 380)
    }

    // MARK: Place Card

    private var placeCard: some View {
        HStack(spacing: SonderSpacing.sm) {
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(feedItem.place.name)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)

                Text(feedItem.place.cityName)
                    .font(.system(size: 14))
                    .foregroundStyle(SonderColors.inkMuted)

                Text(feedItem.place.address)
                    .font(.system(size: 13))
                    .foregroundStyle(SonderColors.inkLight)
            }

            Spacer()

            Image(systemName: feedItem.place.categoryIcon)
                .font(.system(size: 24))
                .foregroundStyle(SonderColors.terracotta.opacity(0.5))
        }
        .padding(SonderSpacing.lg)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: cardShadow.0, radius: cardShadow.1, y: cardShadow.2)
        .padding(.horizontal, SonderSpacing.md)
    }

    // MARK: Rating Card

    private var ratingCard: some View {
        HStack(spacing: SonderSpacing.md) {
            Text(feedItem.rating.emoji)
                .font(.system(size: 44))

            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                Text(feedItem.rating.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SonderColors.inkDark)

                // Visual rating bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SonderColors.warmGray)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(pinColor(feedItem))
                            .frame(width: geo.size.width * ratingFill, height: 6)
                    }
                }
                .frame(height: 6)
            }

            Spacer()
        }
        .padding(SonderSpacing.lg)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: cardShadow.0, radius: cardShadow.1, y: cardShadow.2)
        .padding(.horizontal, SonderSpacing.md)
    }

    private var ratingFill: CGFloat {
        switch feedItem.rating {
        case .skip: return 0.2
        case .solid: return 0.6
        case .mustSee: return 1.0
        }
    }

    // MARK: Note + Tags Card

    private var noteTagsCard: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.md) {
            if let note = feedItem.log.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineSpacing(4)
            }

            if !feedItem.log.tags.isEmpty {
                FlowLayoutTags(tags: feedItem.log.tags)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SonderSpacing.lg)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: cardShadow.0, radius: cardShadow.1, y: cardShadow.2)
        .padding(.horizontal, SonderSpacing.md)
    }

    // MARK: Byline Card

    private var bylineCard: some View {
        Button(action: onUserTap) {
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
            .padding(SonderSpacing.lg)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
            .shadow(color: cardShadow.0, radius: cardShadow.1, y: cardShadow.2)
            .padding(.horizontal, SonderSpacing.md)
        }
        .buttonStyle(.plain)
    }
}
