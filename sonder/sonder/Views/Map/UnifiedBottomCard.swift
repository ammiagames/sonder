//
//  UnifiedBottomCard.swift
//  sonder
//
//  Context-aware bottom card for the unified map.
//  Shows different content based on pin type.
//

import SwiftUI

struct UnifiedBottomCard: View {
    let pin: UnifiedMapPin
    let onDismiss: () -> Void
    let onNavigateToLog: (String, Place) -> Void  // (logID, place)
    var onNavigateToFeedItem: ((FeedItem) -> Void)? = nil
    var onFocusFriend: ((String, String) -> Void)? = nil // (friendID, username)

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(SonderColors.inkLight.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, SonderSpacing.sm)
                .padding(.bottom, SonderSpacing.xs)

            Group {
                switch pin {
                case .personal(let logs, let place):
                    personalCard(logs: logs, place: place)
                case .friends(let friendPlace):
                    friendsCard(place: friendPlace)
                case .combined(let logs, let place, let friendPlace):
                    combinedCard(logs: logs, place: place, friendPlace: friendPlace)
                }
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)
        }
        .background(SonderColors.cream.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.md)
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
                        onDismiss()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
        )
    }

    // MARK: - Personal Card

    private func personalCard(logs: [LogSnapshot], place: Place) -> some View {
        Group {
            if logs.count <= 1, let log = logs.first {
                // Single log: keep original compact layout
                Button {
                    onNavigateToLog(log.id, place)
                } label: {
                    HStack(spacing: SonderSpacing.sm) {
                        pinPhoto(userLogs: logs, photoReference: place.photoReference)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(SonderTypography.headline)
                                .foregroundColor(SonderColors.inkDark)
                                .lineLimit(2)

                            Text(place.address)
                                .font(SonderTypography.caption)
                                .foregroundColor(SonderColors.inkMuted)
                                .lineLimit(1)

                            if let note = log.note, !note.isEmpty {
                                Text(note)
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.inkLight)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text(log.rating.emoji)
                            .font(.system(size: 24))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Multiple logs: place header + scrollable log rows
                VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                    // Place header
                    HStack(spacing: SonderSpacing.sm) {
                        pinPhoto(userLogs: logs, photoReference: place.photoReference)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(SonderTypography.headline)
                                .foregroundColor(SonderColors.inkDark)
                                .lineLimit(2)

                            Text(place.address)
                                .font(SonderTypography.caption)
                                .foregroundColor(SonderColors.inkMuted)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    personalLogsSection(logs: logs, place: place)
                }
            }
        }
    }

    // MARK: - Friends Card

    private func friendsCard(place: ExploreMapPlace) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Header: place info + bookmark
            HStack(alignment: .top) {
                pinPhoto(photoReference: place.photoReference, friendLogs: place.logs)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    Text(place.address)
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)

                    if place.isFriendsLoved {
                        HStack(spacing: 4) {
                            Text("\u{1F525}")
                                .font(.system(size: 12))
                            Text("Friends Loved")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(SonderColors.ratingMustSee)
                        }
                    }
                }

                Spacer()

                WantToGoButton(placeID: place.id)
            }

            // Friends' reviews
            if !place.logs.isEmpty {
                friendReviewsSection(
                    logs: Array(place.logs.prefix(5)),
                    count: place.friendCount
                )
            }
        }
    }

    // MARK: - Combined Card

    private func combinedCard(logs: [LogSnapshot], place: Place, friendPlace: ExploreMapPlace) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Your logs section
            VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                HStack {
                    Label(
                        logs.count > 1 ? "Your logs (\(logs.count))" : "Your log",
                        systemImage: "mappin.circle.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SonderColors.terracotta)

                    Spacer()
                }

                if logs.count <= 1, let log = logs.first {
                    // Single log: inline row
                    Button {
                        onNavigateToLog(log.id, place)
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            pinPhoto(userLogs: logs, photoReference: place.photoReference, friendLogs: friendPlace.logs, size: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name)
                                    .font(SonderTypography.headline)
                                    .foregroundColor(SonderColors.inkDark)
                                    .lineLimit(2)

                                if let note = log.note, !note.isEmpty {
                                    Text(note)
                                        .font(SonderTypography.caption)
                                        .foregroundColor(SonderColors.inkLight)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 0)

                            Text(log.rating.emoji)
                                .font(.system(size: 22))

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SonderColors.inkLight)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Multiple logs: scrollable list
                    personalLogsSection(logs: logs, place: place)
                }
            }

            // Friends section
            if !friendPlace.logs.isEmpty {
                friendReviewsSection(
                    logs: Array(friendPlace.logs.prefix(5)),
                    count: friendPlace.friendCount,
                    trailingContent: AnyView(WantToGoButton(placeID: friendPlace.id))
                )
            }
        }
    }

    // MARK: - Personal Logs Section (multi-log)

    private func personalLogsSection(logs: [LogSnapshot], place: Place) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SonderSpacing.xs) {
                    ForEach(logs, id: \.id) { log in
                        Button {
                            onNavigateToLog(log.id, place)
                        } label: {
                            HStack(spacing: SonderSpacing.sm) {
                                // Date
                                Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12))
                                    .foregroundColor(SonderColors.inkLight)
                                    .frame(width: 70, alignment: .leading)

                                // Note snippet
                                if let note = log.note, !note.isEmpty {
                                    Text(note)
                                        .font(SonderTypography.caption)
                                        .foregroundColor(SonderColors.inkMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                // Rating emoji
                                Text(log.rating.emoji)
                                    .font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(SonderColors.pinColor(for: log.rating).opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SonderColors.inkLight)
                            }
                            .padding(SonderSpacing.xs)
                            .background(SonderColors.warmGray.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    // MARK: - Friends Reviews Section (shared)

    private func friendReviewsSection(logs: [FeedItem], count: Int, trailingContent: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Divider()

            // Section header
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(SonderColors.inkMuted)
                Text("\(count) friend\(count == 1 ? "" : "s") logged this")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SonderColors.inkDark)

                Spacer()

                if let trailing = trailingContent {
                    trailing
                }
            }

            // Review cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SonderSpacing.xs) {
                    ForEach(logs, id: \.id) { item in
                        friendReviewCard(item)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    // MARK: - Friend Review Card

    private func friendReviewCard(_ item: FeedItem) -> some View {
        Button {
            onNavigateToFeedItem?(item)
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Avatar
                if let urlString = item.user.avatarURL, let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 32, height: 32)) {
                        avatarPlaceholder(for: item.user)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder(for: item.user)
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Username + date
                    HStack(spacing: 4) {
                        Text(item.user.username)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)

                        Spacer()

                        Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.inkLight)
                    }

                    // Note (if any)
                    if let note = item.log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(2)
                    }
                }

                // Rating pill
                Text(item.rating.emoji)
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .background(SonderColors.pinColor(for: item.rating).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            }
            .padding(SonderSpacing.xs)
            .background(SonderColors.warmGray.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onFocusFriend?(item.user.id, item.user.username)
            } label: {
                Label("Show only \(item.user.username)", systemImage: "person.crop.circle")
            }
        }
    }

    // MARK: - Pin Photo (priority: user photo > Google Places > friend photo)

    /// Resolves the best photo URL for a pin based on priority:
    /// 1. First user log with a photo
    /// 2. Google Places API photo (via photoReference)
    /// 3. First friend log with a photo
    private func pinPhotoURL(
        userLogs: [LogSnapshot] = [],
        photoReference: String? = nil,
        friendLogs: [FeedItem] = [],
        size: CGFloat = 56
    ) -> URL? {
        // 1. User's own log photo
        if let userPhoto = userLogs.first(where: { $0.photoURL != nil })?.photoURL,
           let url = URL(string: userPhoto) {
            return url
        }

        // 2. Google Places photo
        if let ref = photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: Int(size * 2)) {
            return url
        }

        // 3. Friend's log photo
        if let friendPhoto = friendLogs.first(where: { $0.log.photoURL != nil })?.log.photoURL,
           let url = URL(string: friendPhoto) {
            return url
        }

        return nil
    }

    @ViewBuilder
    private func pinPhoto(
        userLogs: [LogSnapshot] = [],
        photoReference: String? = nil,
        friendLogs: [FeedItem] = [],
        size: CGFloat = 56,
        cornerRadius: CGFloat = SonderSpacing.radiusSm
    ) -> some View {
        if let url = pinPhotoURL(userLogs: userLogs, photoReference: photoReference, friendLogs: friendLogs, size: size) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) {
                photoPlaceholder
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            photoPlaceholder
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }

    // MARK: - Helpers

    private func avatarPlaceholder(for user: FeedItem.FeedUser) -> some View {
        Circle()
            .fill(SonderColors.warmGray)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.inkMuted)
            }
    }
}
