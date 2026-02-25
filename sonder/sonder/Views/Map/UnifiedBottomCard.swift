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
    @State private var showDirectionsDialog = false
    @State private var dragTranslation: CGFloat = 0
    @State private var compactHeight: CGFloat = 0
    @State private var measuredExpandedHeight: CGFloat = 0
    @State private var scrollCooldown = false
    @State private var scrollCooldownTask: Task<Void, Never>?
    @State private var selectedTab: CombinedTab = .you
    @State private var tabPickerHeight: CGFloat = 0
    // Frozen heights — captured at drag start to prevent measurement feedback loops
    @State private var frozenCompactHeight: CGFloat = 0
    @State private var frozenExpandedHeight: CGFloat = 0
    // Freeze whether expanded content is shown while dragging to avoid heavy
    // view insertion/removal during live drag updates.
    @State private var frozenShowExpanded = false
    // Cached heavy content to avoid rebuilding large arrays on every drag frame.
    @State private var userGalleryPhotos: [GalleryPhoto] = []
    @State private var friendGalleryPhotos: [GalleryPhoto] = []
    @State private var userTimelineEntries: [TimelineEntry] = []
    @State private var friendTimelineEntries: [TimelineEntry] = []

    private enum CombinedTab: String, CaseIterable {
        case you = "You"
        case friends = "Friends"
    }

    private var isExpanded: Bool { isExpandedState }
    private var isDragging: Bool { dragTranslation != 0 }
    private var isCombinedPin: Bool { if case .combined = pin { return true }; return false }

    /// Keep expanded content visibility stable during drag to avoid layout churn.
    private var showExpandedContent: Bool {
        if isDragging { return frozenShowExpanded }
        return isExpandedState
    }

    /// Keep width stable while dragging to avoid text reflow jitter.
    /// Inset changes only when snapped compact/expanded.
    private var edgeInset: CGFloat {
        isExpandedState ? 0 : 10
    }

    private var expandedHeight: CGFloat {
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height ?? 844
        let maxHeight = screenHeight * 0.75
        if measuredExpandedHeight > 0 {
            return min(measuredExpandedHeight, maxHeight)
        }
        return screenHeight * 0.5  // fallback before measurement
    }

    /// Height interpolated between compact and expanded based on drag translation.
    /// Negative dragTranslation = dragging up (expand), positive = dragging down (collapse/dismiss).
    /// Uses frozen heights during drag to prevent measurement feedback loops.
    private var displayHeight: CGFloat {
        let baseCompact = isDragging ? frozenCompactHeight : (compactHeight > 0 ? compactHeight : 120)
        let targetExpanded = isDragging ? frozenExpandedHeight : expandedHeight
        if isExpandedState {
            // Expanded: drag down (positive translation) shrinks toward compact
            let h = targetExpanded - dragTranslation
            return max(baseCompact, min(targetExpanded, h))
        } else {
            // Compact: drag up grows toward expanded
            let h = baseCompact - dragTranslation
            return max(baseCompact, min(targetExpanded, h))
        }
    }

    /// Y-offset that positions the card without changing its bounds.
    ///
    /// The card frame is always `expandedHeight` tall. In compact state the card
    /// sits mostly below the screen; in expanded state it's fully visible.
    /// During drag only this offset changes — the layer bounds stay fixed so
    /// Core Animation never needs to re-render shadows or run layout passes.
    private var cardYOffset: CGFloat {
        let expandedH = isDragging ? frozenExpandedHeight : expandedHeight
        let compactH  = isDragging ? frozenCompactHeight  : (compactHeight > 0 ? compactHeight : 120)

        let baseOffset: CGFloat
        if isDragging {
            baseOffset = expandedH - displayHeight
        } else if isExpandedState {
            baseOffset = 0
        } else {
            baseOffset = expandedH - compactH
        }

        // When dragging down from compact, slide the card further off-screen (dismiss gesture).
        let dismissExtra: CGFloat = (!isExpandedState && dragTranslation > 0) ? dragTranslation : 0
        return baseOffset + dismissExtra
    }

    /// Opacity that fades the card out during a downward dismiss drag.
    private var dismissOpacity: Double {
        let d: CGFloat = (!isExpandedState && dragTranslation > 0) ? dragTranslation : 0
        return Double(d > 100 ? max(0, 1 - (d - 100) / 80) : 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle — visual indicator only; drag-from-anywhere is handled
            // by the simultaneousGesture on the parent container.
            Capsule()
                .fill(SonderColors.inkLight.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Tab picker lives OUTSIDE ScrollView so taps are never intercepted
            // by ScrollView's UIKit gesture recognizers.
            if isCombinedPin && showExpandedContent {
                combinedTabPicker
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.bottom, SonderSpacing.xs)
                    .background {
                        GeometryReader { geo in
                            Color.clear.onAppear { tabPickerHeight = geo.size.height }
                        }
                    }
            }

            ScrollView {
                cardContent
                    .padding(.top, SonderSpacing.sm)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.bottom, SonderSpacing.xxl)
                    .background {
                        if !isDragging {
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: CompactHeightKey.self,
                                        value: !isExpandedState ? geo.size.height + 19 : 0
                                    )
                                    .preference(
                                        key: ExpandedContentHeightKey.self,
                                        value: showExpandedContent ? geo.size.height + 40 + tabPickerHeight : 0
                                    )
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
        // Fixed height: the card is always expandedHeight tall. Visibility is
        // controlled by cardYOffset (a transform), so the layer bounds — and
        // therefore the shadow blurs — never change during drag. This keeps
        // every drag frame to a cheap transform-only GPU operation.
        .frame(height: expandedHeight, alignment: .top)
        .transaction { t in
            if isDragging { t.animation = nil }
        }
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .compositingGroup()
        .shadow(color: .black.opacity(isExpandedState ? 0.08 : 0.12), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.10), radius: 8, y: 6)
        .padding(.horizontal, edgeInset)
        .offset(y: cardYOffset)
        .opacity(dismissOpacity)
        // Hit-test area: full card in expanded/dragging state; in compact state restrict
        // to the bottom compactHeight of the layout frame, which is where the card is
        // visually rendered (offset moves rendering only, not the layout frame).
        .contentShape(
            Path(CGRect(
                x: 0,
                y: (isExpandedState || isDragging) ? 0 : expandedHeight - max(compactHeight, 120),
                width: 10000,
                height: (isExpandedState || isDragging) ? expandedHeight : max(compactHeight, 120)
            ))
        )
        // Compact: exclusive overlay captures all drags (scroll is disabled anyway).
        .overlay {
            if !isExpandedState {
                Color.clear
                    .contentShape(
                        Path(CGRect(
                            x: 0,
                            y: expandedHeight - max(compactHeight, 120),
                            width: 10000,
                            height: max(compactHeight, 120)
                        ))
                    )
                    .gesture(cardDragGesture)
            }
        }
        // Expanded: simultaneous gesture lets drags collapse the card from anywhere.
        // Taps still pass through (DragGesture needs 10pt movement).
        // When drag starts, isDragging disables scroll so card drag takes over.
        .simultaneousGesture(expandedDragGesture)
        .onPreferenceChange(CompactHeightKey.self) { value in
            if value > 0 && !isExpandedState && !isDragging {
                compactHeight = value
            }
        }
        .onPreferenceChange(ExpandedContentHeightKey.self) { value in
            if value > 0 && !isDragging {
                measuredExpandedHeight = value
            }
        }
        .onChange(of: isExpandedState) { _, expanded in
            onExpandedChanged?(expanded)
        }
        .onAppear {
            rebuildCachedContent()
        }
        .onDisappear {
            scrollCooldownTask?.cancel()
        }
        .onChange(of: pin.id) { _, _ in
            rebuildCachedContent()
        }
        .directionsConfirmationDialog(isPresented: $showDirectionsDialog, coordinate: pin.coordinate, name: pin.placeName, address: pin.placeAddress)
    }

    // MARK: - Drag Gesture (live tracking + snap on release)
    // Compact: scroll is disabled, so DragGesture captures all touch drags (live resize).
    // Expanded: scroll is enabled for content. DragGesture only fires on the handle area
    //   (top ~25pt, outside ScrollView's hit area) for collapse.

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if dragTranslation == 0 {
                    // First frame — freeze heights to prevent measurement feedback
                    frozenCompactHeight = compactHeight > 0 ? compactHeight : 120
                    frozenExpandedHeight = expandedHeight
                    frozenShowExpanded = isExpandedState
                }
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    dragTranslation = value.translation.height
                }
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
                        // Cooldown prevents scroll-based collapse from firing
                        // during the expand animation (stale negative offsets).
                        scrollCooldown = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isExpandedState = true
                            dragTranslation = 0
                        }
                        scrollCooldownTask?.cancel()
                        scrollCooldownTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            scrollCooldown = false
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

    /// Drag gesture active only when expanded. Fires simultaneously with ScrollView/buttons.
    /// Taps (< 10pt) don't activate, so buttons remain tappable.
    /// Only captures **downward** drags (positive Y) — upward drags pass through to ScrollView.
    /// When drag starts, isDragging becomes true → scrollDisabled(true) → card drag takes over.
    private var expandedDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard isExpandedState else { return }
                // Only capture downward drags; let upward drags scroll.
                guard value.translation.height > 0 else {
                    if dragTranslation > 0 {
                        // Was dragging down but user reversed — snap back
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragTranslation = 0
                        }
                    }
                    return
                }
                if dragTranslation == 0 {
                    frozenCompactHeight = compactHeight > 0 ? compactHeight : 120
                    frozenExpandedHeight = expandedHeight
                    frozenShowExpanded = isExpandedState
                }
                var t = Transaction()
                t.animation = nil
                withTransaction(t) {
                    dragTranslation = value.translation.height
                }
            }
            .onEnded { value in
                guard isExpandedState else { return }
                let ty = value.translation.height
                let predicted = value.predictedEndTranslation.height
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
            scrollCooldownTask?.cancel()
            scrollCooldownTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
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
                    photoGalleryHeader(photos: userGalleryPhotos)

                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkLight)
                            .lineLimit(6)
                    }

                    if !log.tags.isEmpty { tagCapsules(log.tags) }

                    Divider()

                    ratingDetailRow(log: log)

                    HStack {
                        Text(log.createdAt.formatted(date: .long, time: .omitted))
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkLight)
                        Spacer()
                        directionsButton
                    }

                    viewFullDetailButton { onNavigateToLog(log.id, place) }
                }
            } else {
                multiLogHeader(logs: logs, place: place)
                if showExpandedContent {
                    photoGalleryHeader(photos: userGalleryPhotos)
                    Divider()
                    timelineView(entries: userTimelineEntries)
                }
            }
        }
        // No .animation() here — layout animations conflict with the sheet controller
    }

    // MARK: - Compact Header (single personal log)

    private func compactHeader(log: LogSnapshot, logs: [LogSnapshot], place: Place) -> some View {
        let url = pinPhotoURL(userLogs: logs, photoReference: place.photoReference)
        return HStack(spacing: SonderSpacing.sm) {
            if let url {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 112, height: 112)) {
                    photoPlaceholder
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                .opacity(showExpandedContent ? 0 : 1)
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

    // MARK: - Multi-Log Compact Header (with rating + visit count)

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
            Spacer(minLength: 0)
            if let mostRecent = logs.first {
                VStack(spacing: 2) {
                    Text(mostRecent.rating.emoji).font(.system(size: 22))
                    Text("\(logs.count) visits")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
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

                photoGalleryHeader(photos: friendGalleryPhotos)

                HStack {
                    Spacer()
                    directionsButton
                    WantToGoButton(placeID: place.id, placeName: place.name, placeAddress: place.address, photoReference: place.photoReference)
                }

                if !place.logs.isEmpty {
                    Divider()
                    friendsSectionHeader(count: place.friendCount)
                    timelineView(entries: friendTimelineEntries)
                }
            }
        }
        // No .animation() here — layout animations conflict with the sheet controller
    }

    // MARK: - Combined Content

    private func combinedContent(logs: [LogSnapshot], place: Place, friendPlace: ExploreMapPlace) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Compact header with rating distinction
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

                VStack(alignment: .trailing, spacing: 4) {
                    // User's most recent rating
                    if let mostRecent = logs.first {
                        HStack(spacing: 3) {
                            Text(mostRecent.rating.emoji).font(.system(size: 22))
                            Text(mostRecent.rating.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(SonderColors.pinColor(for: mostRecent.rating))
                        }
                    }
                    // Friend count badge
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(friendPlace.friendCount)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(SonderColors.exploreCluster)
                    .clipShape(Capsule())
                }
            }

            if showExpandedContent {
                // Both tab contents are always in the hierarchy so the card height
                // stays stable (no jump when switching tabs). The inactive tab fades
                // out via opacity; hit-testing is disabled for it.
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                        photoGalleryHeader(photos: userGalleryPhotos)
                        Divider()
                        timelineView(entries: userTimelineEntries)
                    }
                    .opacity(selectedTab == .you ? 1 : 0)
                    .allowsHitTesting(selectedTab == .you)

                    VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                        photoGalleryHeader(photos: friendGalleryPhotos)
                        Divider()
                        timelineView(entries: friendTimelineEntries)
                    }
                    .opacity(selectedTab == .friends ? 1 : 0)
                    .allowsHitTesting(selectedTab == .friends)
                }
                .animation(.easeInOut(duration: 0.22), value: selectedTab)

                HStack {
                    Spacer()
                    directionsButton
                    WantToGoButton(placeID: friendPlace.id, placeName: friendPlace.name, placeAddress: friendPlace.address, photoReference: friendPlace.photoReference)
                }
            }
        }
        // No .animation() here — layout animations conflict with the sheet controller
    }

    // MARK: - Combined Tab Picker

    private var combinedTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(CombinedTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? .white : SonderColors.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(selectedTab == tab ? SonderColors.terracotta : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(SonderColors.warmGray))
        .animation(.easeInOut(duration: 0.15), value: selectedTab)
    }

    // MARK: - Photo Gallery Header

    @ViewBuilder
    private func photoGalleryHeader(photos: [GalleryPhoto]) -> some View {
        if photos.count == 1 {
            galleryCell(photo: photos[0], contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        } else if photos.count >= 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(photos) { photo in
                        galleryCell(photo: photo)
                            .frame(width: 135, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
            .frame(height: 180)
        }
    }

    private struct GalleryPhoto: Identifiable {
        let id: String
        let url: URL
        let isUser: Bool
        let avatarURL: String?
        let username: String?
    }

    private func collectGalleryPhotos(userLogs: [LogSnapshot], friendLogs: [FeedItem]) -> [GalleryPhoto] {
        var photos: [GalleryPhoto] = []
        for log in userLogs {
            if let urlString = log.photoURL, let url = URL(string: urlString) {
                photos.append(
                    GalleryPhoto(
                        id: "user-\(log.id)",
                        url: url,
                        isUser: true,
                        avatarURL: nil,
                        username: nil
                    )
                )
            }
        }
        for item in friendLogs {
            if let urlString = item.log.photoURL, let url = URL(string: urlString) {
                photos.append(
                    GalleryPhoto(
                        id: "friend-\(item.id)",
                        url: url,
                        isUser: false,
                        avatarURL: item.user.avatarURL,
                        username: item.user.username
                    )
                )
            }
        }
        return photos
    }

    private func galleryCell(photo: GalleryPhoto, contentMode: ContentMode = .fill) -> some View {
        ZStack(alignment: .bottomLeading) {
            DownsampledAsyncImage(url: photo.url, targetSize: CGSize(width: 180, height: 240), contentMode: contentMode) {
                photoPlaceholder
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Owner indicator
            if photo.isUser {
                Circle()
                    .fill(SonderColors.terracotta)
                    .frame(width: 8, height: 8)
                    .padding(6)
            } else if let avatarURLString = photo.avatarURL, let avatarURL = URL(string: avatarURLString) {
                DownsampledAsyncImage(url: avatarURL, targetSize: CGSize(width: 16, height: 16)) {
                    Circle().fill(SonderColors.warmGray)
                }
                .frame(width: 16, height: 16)
                .clipShape(Circle())
                .overlay { Circle().stroke(.white, lineWidth: 1) }
                .padding(4)
            } else if let username = photo.username {
                Text(username.prefix(1).uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.inkMuted)
                    .frame(width: 16, height: 16)
                    .background(SonderColors.warmGray, in: Circle())
                    .overlay { Circle().stroke(.white, lineWidth: 1) }
                    .padding(4)
            }
        }
    }

    // MARK: - Timeline View

    @ViewBuilder
    private func timelineView(entries: [TimelineEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: SonderSpacing.sm) {
                    // Timeline dot + line
                    VStack(spacing: 0) {
                        Circle()
                            .fill(entry.isUser ? SonderColors.terracotta : SonderColors.sage)
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)

                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(SonderColors.inkLight.opacity(0.2))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 10)

                    // Entry card
                    timelineEntryCard(entry: entry)
                        .padding(.bottom, index < entries.count - 1 ? SonderSpacing.xs : 0)
                }
            }
        }
    }

    private struct TimelineEntry: Identifiable {
        let id: String
        let isUser: Bool
        let rating: Rating
        let note: String?
        let tags: [String]
        let createdAt: Date
        let photoURL: String?
        // User entries
        let logID: String?
        let place: Place?
        // Friend entries
        let feedItem: FeedItem?
        let username: String?
        let avatarURL: String?
    }

    private func buildTimelineEntries(personalLogs: [LogSnapshot], place: Place?, friendLogs: [FeedItem]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        for log in personalLogs {
            entries.append(TimelineEntry(
                id: "user-\(log.id)",
                isUser: true,
                rating: log.rating,
                note: log.note,
                tags: log.tags,
                createdAt: log.createdAt,
                photoURL: log.photoURL,
                logID: log.id,
                place: place,
                feedItem: nil,
                username: nil,
                avatarURL: nil
            ))
        }

        for item in friendLogs {
            entries.append(TimelineEntry(
                id: "friend-\(item.id)",
                isUser: false,
                rating: item.rating,
                note: item.log.note,
                tags: item.log.tags,
                createdAt: item.createdAt,
                photoURL: item.log.photoURL,
                logID: nil,
                place: nil,
                feedItem: item,
                username: item.user.username,
                avatarURL: item.user.avatarURL
            ))
        }

        // Most recent first
        entries.sort { $0.createdAt > $1.createdAt }
        return entries
    }

    private func timelineEntryCard(entry: TimelineEntry) -> some View {
        Group {
            if entry.isUser {
                userTimelineCard(entry: entry)
            } else {
                friendTimelineCard(entry: entry)
            }
        }
    }

    /// Relative date string: "Today", "Yesterday", "3 days ago", "2 weeks ago", etc.
    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0

        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        case 7...13: return "1 week ago"
        case 14...20: return "2 weeks ago"
        case 21...27: return "3 weeks ago"
        default:
            let months = calendar.dateComponents([.month], from: date, to: now).month ?? 0
            if months < 1 { return "4 weeks ago" }
            if months == 1 { return "1 month ago" }
            if months < 12 { return "\(months) months ago" }
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func entryPhotoThumbnail(_ urlString: String?) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) {
                    photoPlaceholder
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            }
        }
    }

    private func userTimelineCard(entry: TimelineEntry) -> some View {
        Button {
            if let logID = entry.logID, let place = entry.place {
                onNavigateToLog(logID, place)
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Photo thumbnail
                entryPhotoThumbnail(entry.photoURL)

                // Date + note + tags
                VStack(alignment: .leading, spacing: 4) {
                    Text(relativeDate(entry.createdAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SonderColors.inkDark)

                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(2)
                    }
                    if !entry.tags.isEmpty { tagCapsules(entry.tags) }
                }

                Spacer(minLength: 0)

                // Rating + label
                VStack(spacing: 2) {
                    Text(entry.rating.emoji).font(.system(size: 18))
                    Text(entry.rating.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: entry.rating))
                }
                .frame(width: 44)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.warmGray.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .overlay(alignment: .leading) {
                // Rating-colored accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(SonderColors.pinColor(for: entry.rating))
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
    }

    private func friendTimelineCard(entry: TimelineEntry) -> some View {
        Button {
            if let item = entry.feedItem {
                onNavigateToFeedItem?(item)
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Photo thumbnail (or friend avatar if no photo)
                if entry.photoURL != nil {
                    entryPhotoThumbnail(entry.photoURL)
                } else if let avatarURLString = entry.avatarURL, let avatarURL = URL(string: avatarURLString) {
                    DownsampledAsyncImage(url: avatarURL, targetSize: CGSize(width: 40, height: 40)) {
                        friendAvatarPlaceholder(username: entry.username)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    friendAvatarPlaceholder(username: entry.username)
                        .frame(width: 40, height: 40)
                }

                // Username + date + note + tags
                VStack(alignment: .leading, spacing: 4) {
                    if let username = entry.username {
                        Text(username)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SonderColors.inkDark)
                    }
                    Text(relativeDate(entry.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(SonderColors.inkLight)

                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(2)
                    }
                    if !entry.tags.isEmpty { tagCapsules(entry.tags) }
                }

                Spacer(minLength: 0)

                // Rating + label
                VStack(spacing: 2) {
                    Text(entry.rating.emoji).font(.system(size: 18))
                    Text(entry.rating.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: entry.rating))
                }
                .frame(width: 44)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.warmGray.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .overlay(alignment: .leading) {
                // Rating-colored accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(SonderColors.pinColor(for: entry.rating))
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let item = entry.feedItem {
                Button { onFocusFriend?(item.user.id, item.user.username) } label: {
                    Label("Show only \(item.user.username)", systemImage: "person.crop.circle")
                }
            }
        }
    }

    private func friendAvatarPlaceholder(username: String?) -> some View {
        Circle()
            .fill(SonderColors.warmGray)
            .overlay {
                Text((username ?? "?").prefix(1).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.inkMuted)
            }
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

    private var friendsLovedBadge: some View {
        HStack(spacing: 4) {
            Text("\u{1F525}").font(.system(size: 12))
            Text("Friends Loved")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SonderColors.ratingMustSee)
        }
    }

    private var directionsButton: some View {
        Button { showDirectionsDialog = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "map")
                    .font(.system(size: 12, weight: .semibold))
                Text("Directions")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(SonderColors.inkDark)
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, 6)
            .background(SonderColors.warmGray)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
                photoPlaceholder
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Warm gradient placeholder with a subtle photo icon — used while images load
    /// or when no photo is available. Matches Sonder's earthy aesthetic.
    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [SonderColors.warmGray, SonderColors.warmGrayDark.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(SonderColors.inkLight.opacity(0.5))
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

    // MARK: - Caching

    private func rebuildCachedContent() {
        switch pin {
        case .personal(let logs, let place):
            userGalleryPhotos = collectGalleryPhotos(userLogs: logs, friendLogs: [])
            friendGalleryPhotos = []
            userTimelineEntries = buildTimelineEntries(personalLogs: logs, place: place, friendLogs: [])
            friendTimelineEntries = []
        case .friends(let place):
            userGalleryPhotos = []
            friendGalleryPhotos = collectGalleryPhotos(userLogs: [], friendLogs: place.logs)
            userTimelineEntries = []
            friendTimelineEntries = buildTimelineEntries(personalLogs: [], place: nil, friendLogs: place.logs)
        case .combined(let logs, let place, let friendPlace):
            userGalleryPhotos = collectGalleryPhotos(userLogs: logs, friendLogs: [])
            friendGalleryPhotos = collectGalleryPhotos(userLogs: [], friendLogs: friendPlace.logs)
            userTimelineEntries = buildTimelineEntries(personalLogs: logs, place: place, friendLogs: [])
            friendTimelineEntries = buildTimelineEntries(personalLogs: [], place: nil, friendLogs: friendPlace.logs)
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

private struct ExpandedContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
