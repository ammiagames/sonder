//
//  UnifiedBottomCard.swift
//  sonder
//
//  Context-aware bottom card for the unified map.
//  Presented as a custom overlay with drag-to-expand / drag-to-dismiss.
//

import SwiftUI

struct UnifiedBottomCard: View {
    let pin: UnifiedMapPin
    let onDismiss: () -> Void
    let onNavigateToLog: (String, Place) -> Void
    var onNavigateToFeedItem: ((FeedItem) -> Void)? = nil
    var onFocusFriend: ((String, String) -> Void)? = nil
    var onExpandedChanged: ((Bool) -> Void)? = nil

    @State private var isExpandedState = false
    @State private var dragTranslation: CGFloat = 0
    @State private var compactHeight: CGFloat = 0
    @State private var scrollCooldown = false

    private var isExpanded: Bool { isExpandedState }
    private var isDragging: Bool { dragTranslation != 0 }

    /// Show expanded detail content during drag-up (at ~30% progress) — not just after snap.
    private var showExpandedContent: Bool { isExpandedState || dragProgress > 0.3 }

    /// Keep width stable while dragging to avoid text reflow jitter.
    /// Inset changes only when snapped compact/expanded.
    private var edgeInset: CGFloat { isExpandedState ? 0 : 10 }

    private var expandedHeight: CGFloat {
        UIScreen.main.bounds.height * 0.5
    }

    /// Height interpolated between compact and expanded based on drag translation.
    /// Negative dragTranslation = dragging up (expand), positive = dragging down (collapse/dismiss).
    private var displayHeight: CGFloat {
        let baseCompact = compactHeight > 0 ? compactHeight : 120
        if isExpandedState {
            // Expanded: drag down (positive translation) shrinks toward compact
            let h = expandedHeight - dragTranslation
            return max(baseCompact, min(expandedHeight, h))
        } else {
            // Compact: drag up grows toward expanded
            let h = baseCompact - dragTranslation
            return max(baseCompact, min(expandedHeight, h))
        }
    }

    /// Offset applied when dragging down from compact (for dismiss gesture).
    private var dismissOffset: CGFloat {
        if !isExpandedState && dragTranslation > 0 {
            return dragTranslation
        }
        return 0
    }

    /// Progress from 0 (compact) to 1 (expanded) for interpolating visual properties.
    private var dragProgress: CGFloat {
        let baseCompact = compactHeight > 0 ? compactHeight : 120
        let range = expandedHeight - baseCompact
        guard range > 0 else { return isExpandedState ? 1 : 0 }
        return (displayHeight - baseCompact) / range
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle — always outside ScrollView so touch-drag works for collapse
            Capsule()
                .fill(SonderColors.inkLight.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 2)

            ScrollView {
                cardContent
                    .padding(.top, SonderSpacing.sm)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.bottom, SonderSpacing.md)
                    .background {
                        if !isExpandedState && !isDragging {
                            GeometryReader { geo in
                                Color.clear.preference(key: CompactHeightKey.self, value: geo.size.height + 17)
                            }
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(!isExpanded || isDragging)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, offset in
                handleScrollOffset(offset)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isDragging ? displayHeight : (isExpanded ? expandedHeight : (compactHeight > 0 ? compactHeight : 120)), alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(SonderColors.cream)
                .shadow(color: .black.opacity(isExpandedState ? 0 : 0.12), radius: 12, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, edgeInset)
        .padding(.bottom, edgeInset)
        .offset(y: dismissOffset)
        .opacity(Double(dismissOffset > 100 ? max(0, 1 - (dismissOffset - 100) / 80) : 1))
        .contentShape(Rectangle())
        // Compact: allow drag from anywhere on the card.
        .overlay {
            if !isExpandedState {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(cardDragGesture)
            }
        }
        // Expanded: only handle-zone drag should collapse, so scrolling stays smooth.
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(cardDragGesture)
        }
        .onPreferenceChange(CompactHeightKey.self) { value in
            if value > 0 && !isExpandedState && !isDragging {
                compactHeight = value
            }
        }
        .onChange(of: isExpandedState) { _, expanded in
            onExpandedChanged?(expanded)
        }
    }

    // MARK: - Drag Gesture (live tracking + snap on release)
    // Compact: scroll is disabled, so DragGesture captures all touch drags (live resize).
    // Expanded: scroll is enabled for content. DragGesture only fires on the handle area
    //   (top ~25pt, outside ScrollView's hit area) for collapse.

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let ty = value.translation.height
                let predicted = value.predictedEndTranslation.height

                if isExpandedState {
                    if ty > 60 || predicted > 150 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isExpandedState = false
                            dragTranslation = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragTranslation = 0
                        }
                    }
                } else {
                    if ty < -25 || predicted < -120 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isExpandedState = true
                            dragTranslation = 0
                        }
                    } else if ty > 50 || predicted > 120 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragTranslation = 0
                        }
                    }
                }
            }
    }

    // MARK: - Scroll-based collapse (for two-finger trackpad in iPhone Mirroring)
    // Only handles expanded→collapse via top overscroll. Compact→expand is handled by DragGesture.
    // Cooldown prevents rapid re-triggering when scroll offset is still stale after state change.

    private func handleScrollOffset(_ offset: CGFloat) {
        guard !isDragging, !scrollCooldown else { return }
        if isExpandedState && offset < -30 {
            scrollCooldown = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpandedState = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                scrollCooldown = false
            }
        }
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        switch pin {
        case .personal(let logs, let place):
            personalContent(logs: logs, place: place)
        case .friends(let friendPlace):
            friendsContent(place: friendPlace)
        case .combined(let logs, let place, let friendPlace):
            combinedContent(logs: logs, place: place, friendPlace: friendPlace)
        }
    }

    // MARK: - Personal Content

    private func personalContent(logs: [LogSnapshot], place: Place) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            if logs.count <= 1, let log = logs.first {
                compactHeader(log: log, logs: logs, place: place)

                if showExpandedContent {
                    heroImage(logs: logs, place: place)

                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkLight)
                            .lineLimit(6)
                    }

                    if !log.tags.isEmpty { tagCapsules(log.tags) }

                    Divider()

                    ratingDetailRow(log: log)

                    Text(log.createdAt.formatted(date: .long, time: .omitted))
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)

                    viewFullDetailButton { onNavigateToLog(log.id, place) }
                }
            } else {
                multiLogHeader(logs: logs, place: place)
                if showExpandedContent {
                    Divider()
                    VStack(spacing: SonderSpacing.xs) {
                        ForEach(logs, id: \.id) { log in
                            personalLogRow(log: log, place: place)
                        }
                    }
                }
            }
        }
        // No .animation() here — layout animations conflict with the sheet controller
    }

    // MARK: - Compact Header

    private func compactHeader(log: LogSnapshot, logs: [LogSnapshot], place: Place) -> some View {
        let url = pinPhotoURL(userLogs: logs, photoReference: place.photoReference)
        return HStack(spacing: SonderSpacing.sm) {
            if let url {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 112, height: 112)) {
                    Rectangle().fill(SonderColors.warmGray)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                .opacity(1 - dragProgress)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)
                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(log.rating.emoji).font(.system(size: 22))
                Text(log.rating.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SonderColors.pinColor(for: log.rating))
            }
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private func heroImage(logs: [LogSnapshot] = [], place: Place? = nil,
                           photoReference: String? = nil, friendLogs: [FeedItem] = []) -> some View {
        let ref = photoReference ?? place?.photoReference
        let url = pinPhotoURL(userLogs: logs, photoReference: ref, friendLogs: friendLogs)
        if let url {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 200)) {
                Rectangle().fill(SonderColors.warmGray)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
    }

    private func multiLogHeader(logs: [LogSnapshot], place: Place) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            pinPhoto(userLogs: logs, photoReference: place.photoReference)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(2)
                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Friends Content

    private func friendsContent(place: ExploreMapPlace) -> some View {
        let topLog = place.logs.first
        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack(spacing: SonderSpacing.sm) {
                pinPhoto(photoReference: place.photoReference, friendLogs: place.logs)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)
                    Text(place.address)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let log = topLog {
                    VStack(spacing: 2) {
                        Text(log.rating.emoji).font(.system(size: 22))
                        Text(log.rating.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SonderColors.pinColor(for: log.rating))
                    }
                }
            }

            if showExpandedContent {
                if place.isFriendsLoved { friendsLovedBadge }

                HStack {
                    Spacer()
                    WantToGoButton(placeID: place.id, placeName: place.name, placeAddress: place.address, photoReference: place.photoReference)
                }

                if !place.logs.isEmpty {
                    Divider()
                    friendsSectionHeader(count: place.friendCount)
                    VStack(spacing: SonderSpacing.xs) {
                        ForEach(place.logs, id: \.id) { friendReviewCard($0) }
                    }
                }
            }
        }
        // No .animation() here — layout animations conflict with the sheet controller
    }

    // MARK: - Combined Content

    private func combinedContent(logs: [LogSnapshot], place: Place, friendPlace: ExploreMapPlace) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack(spacing: SonderSpacing.sm) {
                pinPhoto(userLogs: logs, photoReference: place.photoReference, friendLogs: friendPlace.logs, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(2)
                    Text(place.address)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if showExpandedContent {
                Divider()

                HStack {
                    Label(
                        logs.count > 1 ? "Your logs (\(logs.count))" : "Your log",
                        systemImage: "mappin.circle.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SonderColors.terracotta)
                    Spacer()
                }

                if logs.count <= 1, let log = logs.first {
                    Button { onNavigateToLog(log.id, place) } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            if let note = log.note, !note.isEmpty {
                                Text(note)
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkLight)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text(log.rating.emoji).font(.system(size: 22))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SonderColors.inkLight)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: SonderSpacing.xs) {
                        ForEach(logs, id: \.id) { personalLogRow(log: $0, place: place) }
                    }
                }

                if !friendPlace.logs.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        friendsSectionHeader(count: friendPlace.friendCount)
                        Spacer()
                        WantToGoButton(placeID: friendPlace.id, placeName: friendPlace.name, placeAddress: friendPlace.address, photoReference: friendPlace.photoReference)
                    }
                    VStack(spacing: SonderSpacing.xs) {
                        ForEach(friendPlace.logs, id: \.id) { friendReviewCard($0) }
                    }
                }
            }
        }
        // No .animation() here — layout animations conflict with the sheet controller
    }

    // MARK: - Shared Components

    private func friendsSectionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(SonderColors.inkMuted)
            Text("\(count) friend\(count == 1 ? "" : "s") logged this")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SonderColors.inkDark)
        }
    }

    private func personalLogRow(log: LogSnapshot, place: Place) -> some View {
        Button { onNavigateToLog(log.id, place) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: SonderSpacing.sm) {
                    Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(SonderColors.inkLight)
                        .frame(width: 70, alignment: .leading)
                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(log.rating.emoji)
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                        .background(SonderColors.pinColor(for: log.rating).opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SonderColors.inkLight)
                }
                if !log.tags.isEmpty { tagCapsules(log.tags) }
            }
            .padding(SonderSpacing.xs)
            .background(SonderColors.warmGray.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
    }

    private func ratingDetailRow(log: LogSnapshot) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            Text(log.rating.emoji).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text(log.rating.displayName)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                Text(log.rating.subtitle)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }
            Spacer()
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.pinColor(for: log.rating).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    private func tagCapsules(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tags.prefix(5), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SonderColors.terracotta.opacity(0.1))
                        .foregroundStyle(SonderColors.terracotta)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func friendReviewCard(_ item: FeedItem) -> some View {
        Button { onNavigateToFeedItem?(item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: SonderSpacing.sm) {
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
                        HStack(spacing: 4) {
                            Text(item.user.username)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SonderColors.inkDark)
                            Spacer()
                            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11))
                                .foregroundStyle(SonderColors.inkLight)
                        }
                        if let note = item.log.note, !note.isEmpty {
                            Text(note)
                                .font(SonderTypography.caption)
                                .foregroundStyle(SonderColors.inkMuted)
                                .lineLimit(3)
                        }
                    }
                    Text(item.rating.emoji)
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                        .background(SonderColors.pinColor(for: item.rating).opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }
                if !item.log.tags.isEmpty { tagCapsules(item.log.tags) }
            }
            .padding(SonderSpacing.xs)
            .background(SonderColors.warmGray.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onFocusFriend?(item.user.id, item.user.username) } label: {
                Label("Show only \(item.user.username)", systemImage: "person.crop.circle")
            }
        }
    }

    private var friendsLovedBadge: some View {
        HStack(spacing: 4) {
            Text("\u{1F525}").font(.system(size: 12))
            Text("Friends Loved")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SonderColors.ratingMustSee)
        }
    }

    private func viewFullDetailButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text("View Full Detail").font(SonderTypography.headline)
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(SonderSpacing.sm)
            .background(SonderColors.terracotta)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
    }

    // MARK: - Pin Photo helpers

    private func pinPhotoURL(
        userLogs: [LogSnapshot] = [], photoReference: String? = nil,
        friendLogs: [FeedItem] = [], size: CGFloat = 56
    ) -> URL? {
        if let p = userLogs.first(where: { $0.photoURL != nil })?.photoURL, let u = URL(string: p) { return u }
        if let r = photoReference, let u = GooglePlacesService.photoURL(for: r, maxWidth: Int(size * 2)) { return u }
        if let p = friendLogs.first(where: { $0.log.photoURL != nil })?.log.photoURL, let u = URL(string: p) { return u }
        return nil
    }

    @ViewBuilder
    private func pinPhoto(
        userLogs: [LogSnapshot] = [], photoReference: String? = nil,
        friendLogs: [FeedItem] = [], size: CGFloat = 56,
        cornerRadius: CGFloat = SonderSpacing.radiusSm
    ) -> some View {
        if let url = pinPhotoURL(userLogs: userLogs, photoReference: photoReference, friendLogs: friendLogs, size: size) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) {
                Rectangle().fill(SonderColors.warmGray)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    private func avatarPlaceholder(for user: FeedItem.FeedUser) -> some View {
        Circle()
            .fill(SonderColors.warmGray)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.inkMuted)
            }
    }
}

// MARK: - Preference Key for compact height measurement

private struct CompactHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
