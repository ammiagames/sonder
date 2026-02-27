//
//  OtherUserProfileView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "OtherUserProfileView")

/// View another user's profile (read-only)
struct OtherUserProfileView: View {
    let userID: String

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService
    @Environment(FeedService.self) private var feedService
    @Environment(TripService.self) private var tripService

    @Environment(\.modelContext) private var modelContext
    @State private var myLogs: [Log] = []
    @State private var myPlaces: [Place] = []

    @State private var user: User?
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    @State private var followerCount = 0
    @State private var followingCount = 0
    @State private var userLogs: [FeedItem] = []
    @State private var userTrips: [Trip] = []

    // Cached derived data — rebuilt when userLogs/myLogs change
    @State private var cachedUniqueCities: Set<String> = []
    @State private var cachedUniqueCountries: Set<String> = []
    @State private var cachedCityCounts: [(city: String, count: Int)] = []
    @State private var cachedTopTagsWithCounts: [(tag: String, count: Int)] = []
    @State private var cachedInCommonPlaces: [InCommonPlace] = []
    @State private var cachedInCommonCities: [String] = []

    // Card style exploration
    @State private var cardStyle: ProfileCardStyle = .classic

    // Profile stats (computed from FeedItems)
    @State private var theirProfileStats: ProfileStats?
    @State private var myProfileStats: ProfileStats?
    @State private var tasteMatch: TasteMatchResult?

    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: SonderSpacing.md) {
                    ProgressView()
                        .tint(SonderColors.terracotta)
                    Text("Loading profile...")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else if let user = user {
                VStack(spacing: 0) {
                    // Hero cover image + Profile header
                    heroCoverSection(user)

                    VStack(spacing: SonderSpacing.lg) {
                        // Card style picker (exploration)
                        ProfileCardStylePicker(style: $cardStyle)

                        // Stats bar
                        statsSection

                        // Follow button
                        if user.id != authService.currentUser?.id {
                            followButton
                                .padding(.horizontal, SonderSpacing.xs)
                        }

                        // Taste match score
                        if let match = tasteMatch {
                            tasteMatchSection(match)
                        }

                        // In common
                        if !inCommonPlaces.isEmpty || !inCommonCities.isEmpty {
                            inCommonSection
                        }

                        // View their map banner
                        if !userLogs.isEmpty {
                            viewTheirMapBanner
                        }

                        // Photo highlights
                        if !photoHighlights.isEmpty {
                            photoHighlightsSection
                        }

                        // Enhanced rating section
                        if let stats = theirProfileStats, stats.totalLogs > 0 {
                            enhancedRatingSection(stats: stats)
                        }

                        // Taste DNA radar chart
                        if let theirStats = theirProfileStats, theirStats.totalLogs >= 3, !theirStats.tasteDNA.isEmpty {
                            if let myStats = myProfileStats, myStats.totalLogs >= 3, !myStats.tasteDNA.isEmpty {
                                ComparisonTasteDNARadarChart(theirDNA: theirStats.tasteDNA, myDNA: myStats.tasteDNA)
                            } else {
                                TasteDNARadarChart(tasteDNA: theirStats.tasteDNA)
                            }
                        }

                        // Recent trips film strip
                        if !recentTrips.isEmpty {
                            recentTripsSection
                        }

                        // They love (tags)
                        if !topTagsWithCounts.isEmpty {
                            theyLoveSection
                        }

                        // Recent activity
                        if !userLogs.isEmpty {
                            recentActivitySection
                        }

                        // Top cities photo mosaic
                        if !uniqueCities.isEmpty {
                            topCitiesPhotoMosaic
                        }

                        // See all places button
                        if !userLogs.isEmpty {
                            seeAllPlacesButton
                        }
                    }
                    .padding(SonderSpacing.md)
                }
                .padding(.bottom, SonderSpacing.xxl)
            } else {
                ContentUnavailableView {
                    Label("User Not Found", systemImage: "person.slash")
                        .foregroundStyle(SonderColors.inkMuted)
                } description: {
                    Text("This user doesn't exist or has been deleted")
                        .foregroundStyle(SonderColors.inkLight)
                }
                .padding(.top, 80)
            }
        }
        .environment(\.profileCardStyle, cardStyle)
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle(user?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let user = user {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OtherUserMapView(userID: user.id, username: user.username, logs: userLogs)
                    } label: {
                        Image(systemName: "map")
                            .foregroundStyle(SonderColors.terracotta)
                    }
                }
            }
        }
        .task {
            refreshMyData()
            await loadData()
        }
    }

    private func refreshMyData() {
        guard let myUserID = authService.currentUser?.id else { return }
        let logDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == myUserID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        myLogs = (try? modelContext.fetch(logDescriptor)) ?? []
        myPlaces = (try? modelContext.fetch(FetchDescriptor<Place>())) ?? []
    }

    // MARK: - Hero Cover Section

    private func heroCoverSection(_ user: User) -> some View {
        ZStack(alignment: .bottom) {
            // Background: blurred hero photo or warm gradient
            if let heroURL = bestHeroPhotoURL {
                DownsampledAsyncImage(url: heroURL, targetSize: CGSize(width: 400, height: 280)) {
                    heroFallbackGradient
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .blur(radius: 20)
                .clipped()
            } else {
                heroFallbackGradient
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }

            // Gradient overlay fading to cream
            LinearGradient(
                colors: [.clear, SonderColors.cream.opacity(0.6), SonderColors.cream],
                startPoint: .top,
                endPoint: .bottom
            )

            // Profile header
            profileHeader(user)
                .padding(.bottom, SonderSpacing.sm)
        }
    }

    private var heroFallbackGradient: some View {
        LinearGradient(
            colors: [SonderColors.terracotta.opacity(0.15), SonderColors.cream],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Best photo URL for hero: highest-rated log with a photo
    private var bestHeroPhotoURL: URL? {
        let ratingOrder: [Rating] = [.mustSee, .great, .okay, .skip]
        for rating in ratingOrder {
            if let item = userLogs.first(where: { $0.rating == rating && $0.log.photoURL != nil }),
               let urlString = item.log.photoURL,
               let url = URL(string: urlString) {
                return url
            }
        }
        return nil
    }

    // MARK: - Profile Header

    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: SonderSpacing.sm) {
            // Avatar
            if let urlString = user.avatarURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 100, height: 100)) {
                    avatarPlaceholder(for: user)
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(SonderColors.cream, lineWidth: 4)
                )
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            } else {
                avatarPlaceholder(for: user)
                    .overlay(
                        Circle()
                            .stroke(SonderColors.cream, lineWidth: 4)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }

            // Username
            Text("@\(user.username)")
                .font(SonderTypography.largeTitle)
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Archetype badge
            if let stats = theirProfileStats, stats.totalLogs > 0 {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: stats.archetype.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(stats.archetype.displayName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(SonderColors.terracotta)
                .padding(.horizontal, SonderSpacing.sm)
                .padding(.vertical, SonderSpacing.xxs)
                .background(SonderColors.terracotta.opacity(0.12))
                .clipShape(Capsule())
            }

            // Bio
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(SonderTypography.subheadline)
                    .italic()
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            // Journey stats subtitle
            if !userLogs.isEmpty {
                let parts: [String] = {
                    var p = ["\(userLogs.count) places"]
                    if uniqueCities.count > 1 { p.append("\(uniqueCities.count) cities") }
                    if uniqueCountries.count > 1 { p.append("\(uniqueCountries.count) countries") }
                    return p
                }()
                Text(parts.joined(separator: " · "))
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            // Member since
            Text("Journaling since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
        }
        .frame(maxWidth: .infinity)
    }

    private func avatarPlaceholder(for user: User) -> some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .frame(width: 100, height: 100)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 0) {
            NavigationLink {
                FollowListView(
                    userID: userID,
                    username: user?.username ?? "",
                    initialTab: .followers
                )
            } label: {
                statItem(value: followerCount, label: "Followers")
            }
            .buttonStyle(.plain)

            statDivider

            NavigationLink {
                FollowListView(
                    userID: userID,
                    username: user?.username ?? "",
                    initialTab: .following
                )
            } label: {
                statItem(value: followingCount, label: "Following")
            }
            .buttonStyle(.plain)

            statDivider

            statItem(value: userLogs.count, label: "Places")
        }
        .padding(.vertical, SonderSpacing.sm)
        .padding(.horizontal, SonderSpacing.lg)
        .background(SonderColors.warmGray.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .padding(.horizontal, SonderSpacing.lg)
    }

    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: SonderSpacing.xxs) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(SonderColors.inkDark)
            Text(label)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGrayDark)
            .frame(width: 1, height: 32)
    }

    // MARK: - Follow Button

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            HStack(spacing: SonderSpacing.xs) {
                if isFollowLoading {
                    ProgressView()
                        .tint(isFollowing ? SonderColors.inkDark : .white)
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isFollowing ? "Following" : "Follow")
                        .font(SonderTypography.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.sm)
            .background(isFollowing ? SonderColors.warmGray : SonderColors.terracotta)
            .foregroundStyle(isFollowing ? SonderColors.inkDark : .white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .disabled(isFollowLoading)
    }

    // MARK: - Taste Match Section

    private func tasteMatchSection(_ match: TasteMatchResult) -> some View {
        VStack(spacing: SonderSpacing.sm) {
            // Circular progress ring
            ZStack {
                Circle()
                    .stroke(SonderColors.warmGrayDark.opacity(0.3), lineWidth: 6)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: CGFloat(match.overallScore))
                    .stroke(
                        SonderColors.terracotta,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                Text("\(match.displayPercentage)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.inkDark)
            }

            Text(match.label)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(SonderColors.inkDark)

            Text("Based on places, ratings, and tags")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .profileSectionCard(tint: SonderColors.terracotta)
    }

    // MARK: - Photo Highlights

    private var photoHighlights: [FeedItem] {
        userLogs
            .filter { $0.log.photoURL != nil && ($0.rating == .mustSee || $0.rating == .great) }
            .sorted { ($0.rating == .mustSee ? 1 : 0) > ($1.rating == .mustSee ? 1 : 0) }
            .prefix(10)
            .map { $0 }
    }

    private var photoHighlightsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Photo highlights")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.sm) {
                    ForEach(photoHighlights) { item in
                        NavigationLink {
                            FeedLogDetailView(feedItem: item)
                        } label: {
                            photoHighlightCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .profileSectionCard(tint: SonderColors.ochre, isFullBleed: true)
    }

    private func photoHighlightCard(_ item: FeedItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = item.log.photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 180, height: 140)) {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                        .fill(SonderColors.warmGrayDark.opacity(0.3))
                }
                .frame(width: 180, height: 140)
                .clipped()
            }

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Place name + rating badge
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                HStack(spacing: 4) {
                    Text(item.rating.emoji)
                        .font(.system(size: 12))
                    Text(item.place.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(SonderSpacing.sm)
        }
        .frame(width: 180, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    // MARK: - Enhanced Rating Section

    private func enhancedRatingSection(stats: ProfileStats) -> some View {
        let dist = stats.ratingDistribution
        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Ratings")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            if dist.total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if dist.skipCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingSkip)
                                .frame(width: geo.size.width * dist.skipPercentage)
                        }
                        if dist.okayCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingOkay)
                                .frame(width: geo.size.width * dist.okayPercentage)
                        }
                        if dist.greatCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingGreat)
                                .frame(width: geo.size.width * dist.greatPercentage)
                        }
                        if dist.mustSeeCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingMustSee)
                                .frame(width: geo.size.width * dist.mustSeePercentage)
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Legend
                HStack(spacing: SonderSpacing.sm) {
                    ratingLegendItem(emoji: "\u{1F44E}", count: dist.skipCount, color: SonderColors.ratingSkip)
                    ratingLegendItem(emoji: "\u{1F44C}", count: dist.okayCount, color: SonderColors.ratingOkay)
                    ratingLegendItem(emoji: "\u{2B50}", count: dist.greatCount, color: SonderColors.ratingGreat)
                    ratingLegendItem(emoji: "\u{1F525}", count: dist.mustSeeCount, color: SonderColors.ratingMustSee)
                }
            }

            Text(dist.philosophy)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .italic()
                .padding(.top, SonderSpacing.xxs)
        }
        .profileSectionCard(tint: SonderColors.ochre)
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        let recentLogs = Array(userLogs.sorted { $0.createdAt > $1.createdAt }.prefix(3))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Recent activity")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(recentLogs) { item in
                NavigationLink {
                    FeedLogDetailView(feedItem: item)
                } label: {
                    HStack(spacing: SonderSpacing.sm) {
                        Text(item.rating.emoji)
                            .font(.system(size: 20))
                            .frame(width: 36, height: 36)
                            .background(SonderColors.pinColor(for: item.rating).opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SonderColors.inkDark)
                                .lineLimit(1)

                            Text(item.createdAt.relativeDisplay)
                                .font(.system(size: 12))
                                .foregroundStyle(SonderColors.inkLight)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SonderColors.inkLight)
                    }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)

                if item.id != recentLogs.last?.id {
                    Divider()
                }
            }
        }
        .profileSectionCard(tint: SonderColors.terracotta)
    }

    // MARK: - Recent Trips (Boarding Pass)

    private var recentTrips: [Trip] {
        Array(sortTripsReverseChronological(userTrips).prefix(5))
    }

    // MARK: - Computed Stats

    private var uniqueCities: Set<String> { cachedUniqueCities }
    private var uniqueCountries: Set<String> { cachedUniqueCountries }
    private var cityCounts: [(city: String, count: Int)] { cachedCityCounts }
    private var topTagsWithCounts: [(tag: String, count: Int)] { cachedTopTagsWithCounts }



    private func cityPhotoURL(_ city: String, maxWidth: Int = 400) -> URL? {
        let cityItems = userLogs.filter { ProfileStatsService.extractCity(from: $0.place.address) == city }

        // Priority 1: user-uploaded photo
        if let userPhoto = cityItems.sorted(by: { $0.createdAt > $1.createdAt })
            .first(where: { $0.log.photoURL != nil })?.log.photoURL,
           let url = URL(string: userPhoto) {
            return url
        }

        // Priority 2: Google Places photo
        if let ref = cityItems.first(where: { $0.place.photoReference != nil })?.place.photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: maxWidth) {
            return url
        }

        return nil
    }

    private func tripDateText(_ trip: Trip) -> String? {
        ProfileShared.tripDateText(trip)
    }

    private func tripCoverURL(_ trip: Trip) -> URL? {
        if let cover = trip.coverPhotoURL, let url = URL(string: cover) {
            return url
        }
        return nil
    }

    @ViewBuilder
    private func tripCoverPhoto(_ trip: Trip, size: CGSize) -> some View {
        ProfileShared.tripCoverPhoto(trip, size: size, coverURL: tripCoverURL(trip))
    }

    private func tripPlaceholderGradient(_ trip: Trip) -> some View {
        ProfileShared.tripPlaceholderGradient(trip)
    }

    private var recentTripsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Recent trips")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.sm) {
                    ForEach(recentTrips, id: \.id) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                        } label: {
                            boardingPassCard(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func boardingPassCard(trip: Trip) -> some View {
        HStack(spacing: 0) {
            tripCoverPhoto(trip, size: CGSize(width: 72, height: 100))
                .frame(width: 72, height: 100)
                .clipped()

            VStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle()
                        .fill(SonderColors.cream)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 12)
            .background(SonderColors.warmGray)

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text("DESTINATION")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(SonderColors.inkLight)
                    .tracking(0.5)

                Text(trip.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: SonderSpacing.md) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DATE")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(SonderColors.inkLight)
                            .tracking(0.5)
                        Text(tripDateText(trip) ?? "—")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SonderColors.inkDark)
                    }
                }

                RoundedRectangle(cornerRadius: 1)
                    .fill(SonderColors.terracotta)
                    .frame(height: 3)
            }
            .padding(SonderSpacing.sm)
            .frame(width: 140, height: 100, alignment: .leading)
            .background(SonderColors.warmGray)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                .stroke(SonderColors.warmGrayDark, lineWidth: 0.5)
        )
    }




    private func ratingLegendItem(emoji: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(emoji) \(count)")
                .font(.system(size: 12))
                .foregroundStyle(SonderColors.inkDark)
        }
    }

    // MARK: - They Love Section

    private var theyLoveSection: some View {
        let tagData = topTagsWithCounts
        let maxCount = tagData.first?.count ?? 1

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("\(user?.username ?? "They") love\(user?.username != nil ? "s" : "")")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            FlowLayoutWrapper {
                ForEach(tagData, id: \.tag) { item in
                    tagChip(tag: item.tag, count: item.count, isTop: item.tag == tagData.first?.tag, maxCount: maxCount)
                }
            }
        }
        .profileSectionCard(tint: SonderColors.sage)
    }

    private func tagChip(tag: String, count: Int, isTop: Bool, maxCount: Int) -> some View {
        ProfileShared.tagChip(tag: tag, count: count, isTop: isTop, maxCount: maxCount)
    }

    // MARK: - Top Cities Photo Mosaic

    private var topCitiesPhotoMosaic: some View {
        let items = Array(cityCounts.prefix(5))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("\(user?.username ?? "Their")'s top cities")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            if let hero = items.first {
                NavigationLink {
                    OtherUserCityLogsView(
                        title: hero.city,
                        logs: userLogs.filter { ProfileStatsService.extractCity(from: $0.place.address) == hero.city },
                        trips: userTrips
                    )
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        if let url = cityPhotoURL(hero.city, maxWidth: 600) {
                            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 180)) {
                                cityPhotoFallback(index: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipped()
                        } else {
                            cityPhotoFallback(index: 0)
                                .frame(maxWidth: .infinity)
                                .frame(height: 160)
                        }

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Spacer()
                            Text(hero.city)
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                            Text("\(hero.count) place\(hero.count == 1 ? "" : "s") logged")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(SonderSpacing.md)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }
                .buttonStyle(.plain)
            }

            if items.count > 1 {
                let rest = Array(items.dropFirst())
                let columns = [
                    GridItem(.flexible(), spacing: SonderSpacing.xs),
                    GridItem(.flexible(), spacing: SonderSpacing.xs)
                ]

                LazyVGrid(columns: columns, spacing: SonderSpacing.xs) {
                    ForEach(Array(rest.enumerated()), id: \.element.city) { index, item in
                        NavigationLink {
                            OtherUserCityLogsView(
                                title: item.city,
                                logs: userLogs.filter { ProfileStatsService.extractCity(from: $0.place.address) == item.city },
                                trips: userTrips
                            )
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let url = cityPhotoURL(item.city) {
                                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 200, height: 120)) {
                                        cityPhotoFallback(index: index + 1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 100)
                                    .clipped()
                                } else {
                                    cityPhotoFallback(index: index + 1)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 100)
                                }

                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.6)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )

                                VStack(alignment: .leading, spacing: 1) {
                                    Spacer()
                                    Text(item.city)
                                        .font(.system(size: 14, weight: .bold, design: .serif))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("\(item.count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .padding(SonderSpacing.sm)
                            }
                            .frame(height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .profileSectionCard(tint: SonderColors.warmBlue, isFullBleed: true)
    }

    private func cityPhotoFallback(index: Int) -> some View {
        ProfileShared.cityPhotoFallback(index: index)
    }

    // MARK: - In Common

    private var inCommonPlaces: [InCommonPlace] { cachedInCommonPlaces }
    private var inCommonCities: [String] { cachedInCommonCities }

    private var citiesNarrative: String? {
        let cities = inCommonCities
        guard !cities.isEmpty else { return nil }
        switch cities.count {
        case 1: return "You've both explored \(cities[0])"
        case 2: return "You've both explored \(cities[0]) and \(cities[1])"
        case 3: return "You've both explored \(cities[0]), \(cities[1]), and \(cities[2])"
        default:
            let first3 = cities.prefix(3).joined(separator: ", ")
            return "You've both explored \(first3), and \(cities.count - 3) more"
        }
    }

    private var inCommonSection: some View {
        NavigationLink {
            InCommonDetailView(
                places: inCommonPlaces,
                citiesNarrative: citiesNarrative,
                username: user?.username ?? ""
            )
        } label: {
            VStack(alignment: .leading, spacing: SonderSpacing.sm) {
                HStack {
                    Text("In common")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    if !inCommonPlaces.isEmpty {
                        HStack(spacing: 4) {
                            Text("\(inCommonPlaces.count) place\(inCommonPlaces.count == 1 ? "" : "s")")
                                .font(SonderTypography.caption)
                                .foregroundStyle(SonderColors.inkLight)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(SonderColors.inkLight)
                        }
                    }
                }

                if let narrative = citiesNarrative {
                    Text(narrative)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(SonderColors.inkDark)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                if !inCommonPlaces.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SonderSpacing.sm) {
                            ForEach(inCommonPlaces) { place in
                                inCommonCard(place)
                            }
                        }
                    }
                }
            }
            .profileSectionCard(tint: SonderColors.warmBlue)
        }
        .buttonStyle(.plain)
    }

    private func inCommonCard(_ place: InCommonPlace) -> some View {
        VStack(spacing: 0) {
            // Photo
            ZStack {
                if let url = place.photoURL {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 200)) {
                        inCommonPhotoPlaceholder(place)
                    }
                } else {
                    inCommonPhotoPlaceholder(place)
                }
            }
            .frame(width: 155, height: 100)
            .clipped()

            // Place name + city
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                if !place.city.isEmpty {
                    Text(place.city)
                        .font(.system(size: 11))
                        .foregroundStyle(SonderColors.inkLight)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xs)

            // Split rating comparison
            HStack(spacing: 0) {
                // You
                VStack(spacing: 2) {
                    Text("You")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SonderColors.inkLight)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(place.myRating.emoji)
                        .font(.system(size: 18))
                    Text(place.myRating.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: place.myRating))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.xs)
                .background(SonderColors.pinColor(for: place.myRating).opacity(0.08))

                // Divider
                Rectangle()
                    .fill(SonderColors.cream)
                    .frame(width: 1)

                // Them
                VStack(spacing: 2) {
                    Text("Them")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SonderColors.inkLight)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(place.theirRating.emoji)
                        .font(.system(size: 18))
                    Text(place.theirRating.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: place.theirRating))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.xs)
                .background(SonderColors.pinColor(for: place.theirRating).opacity(0.08))
            }
        }
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                .stroke(SonderColors.warmGrayDark, lineWidth: 0.5)
        )
        .frame(width: 155)
    }

    private func inCommonPhotoPlaceholder(_ place: InCommonPlace) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
        ]
        let grad = gradients[abs(place.id.hashValue) % gradients.count]
        return LinearGradient(
            colors: [grad.0.opacity(0.6), grad.1.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "mappin.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - View Their Map Banner

    private var viewTheirMapBanner: some View {
        NavigationLink {
            OtherUserMapView(userID: user?.id ?? userID, username: user?.username ?? "", logs: userLogs)
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: "map.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SonderColors.terracotta)
                    .frame(width: 36, height: 36)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(user?.username ?? "their")'s map")
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)

                    Text("\(userLogs.count) place\(userLogs.count == 1 ? "" : "s")")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SonderColors.inkLight)
            }
            .profileSectionCard(tint: SonderColors.sage)
        }
        .buttonStyle(.plain)
    }

    // MARK: - See All Places Button

    private var seeAllPlacesButton: some View {
        NavigationLink {
            OtherUserAllPlacesView(userLogs: userLogs, username: user?.username ?? "")
        } label: {
            HStack {
                Spacer()
                Text("See all \(userLogs.count) places")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.terracotta)
                Spacer()
            }
            .padding(.vertical, SonderSpacing.md)
            .background(SonderColors.terracotta.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cache Rebuild

    private func rebuildOtherUserCaches() {
        // Unique cities & countries
        cachedUniqueCities = Set(userLogs.compactMap { ProfileStatsService.extractCity(from: $0.place.address) })
        cachedUniqueCountries = Set(userLogs.compactMap { ProfileStatsService.extractCountry(from: $0.place.address) })

        // City counts
        var cityCts: [String: Int] = [:]
        for item in userLogs {
            if let city = ProfileStatsService.extractCity(from: item.place.address) {
                cityCts[city, default: 0] += 1
            }
        }
        cachedCityCounts = cityCts.map { (city: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        // Top tags
        let allTags = userLogs.flatMap { $0.log.tags }
        if allTags.isEmpty {
            cachedTopTagsWithCounts = []
        } else {
            let tagCounts = Dictionary(grouping: allTags, by: { $0 })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            cachedTopTagsWithCounts = Array(tagCounts.prefix(6).map { (tag: $0.key, count: $0.value) })
        }

        // Profile stats (their stats from FeedItems, my stats from SwiftData)
        let theirs = ProfileStatsService.computeFromFeedItems(userLogs)
        theirProfileStats = theirs

        let loggedPlaceIDs = Set(myLogs.map { $0.placeID })
        let myUserPlaces = myPlaces.filter { loggedPlaceIDs.contains($0.id) }
        let mine = ProfileStatsService.compute(logs: myLogs, places: myUserPlaces)
        myProfileStats = mine

        // Taste match (both need 3+ logs)
        if theirs.totalLogs >= 3 && mine.totalLogs >= 3 {
            let myTagSet = Set(myLogs.flatMap { $0.tags })
            let theirTagSet = Set(userLogs.flatMap { $0.log.tags })
            tasteMatch = ProfileStatsService.computeTasteMatch(
                myDNA: mine.tasteDNA,
                theirDNA: theirs.tasteDNA,
                myTags: myTagSet,
                theirTags: theirTagSet,
                myRatingDist: mine.ratingDistribution,
                theirRatingDist: theirs.ratingDistribution
            )
        } else {
            tasteMatch = nil
        }

        // In common places
        let myPlacesByID = Dictionary(myPlaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let myLogsByPlaceID: [String: Log] = {
            let grouped = Dictionary(grouping: myLogs, by: { $0.placeID })
            return grouped.compactMapValues { $0.sorted { $0.createdAt > $1.createdAt }.first }
        }()
        let theirLogsByPlaceID = Dictionary(grouping: userLogs, by: { $0.place.id })
        let myPlaceIDs = Set(myLogs.map { $0.placeID })
        let commonIDs = myPlaceIDs.intersection(Set(theirLogsByPlaceID.keys))

        cachedInCommonPlaces = commonIDs.compactMap { placeID -> InCommonPlace? in
            guard let myLog = myLogsByPlaceID[placeID],
                  let theirItems = theirLogsByPlaceID[placeID],
                  let theirItem = theirItems.first else { return nil }

            let place = myPlacesByID[placeID]
            let name = place?.name ?? theirItem.place.name
            let address = place?.address ?? theirItem.place.address
            let city = ProfileStatsService.extractCity(from: address) ?? ""

            let photoURL: URL? = {
                if let url = theirItem.log.photoURL, let u = URL(string: url) { return u }
                if let url = myLog.photoURL, let u = URL(string: url) { return u }
                if let ref = theirItem.place.photoReference ?? place?.photoReference {
                    return GooglePlacesService.photoURL(for: ref, maxWidth: 300)
                }
                return nil
            }()

            return InCommonPlace(
                id: placeID,
                name: name,
                city: city,
                myRating: myLog.rating,
                theirRating: theirItem.rating,
                photoURL: photoURL,
                latestDate: max(myLog.createdAt, theirItem.createdAt)
            )
        }
        .sorted { $0.latestDate > $1.latestDate }
        .prefix(10)
        .map { $0 }

        // In common cities
        let myCities = Set(myPlaces.compactMap { ProfileStatsService.extractCity(from: $0.address) })
        let theirCities = cachedUniqueCities
        cachedInCommonCities = Array(myCities.intersection(theirCities)).sorted()
    }

    // MARK: - Data Loading

    private func loadData() async {
        // Skip reload if data already exists (preserves scroll position on back-navigation)
        guard user == nil else { return }

        isLoading = true

        // Load user
        do {
            user = try await socialService.getUser(id: userID)
        } catch {
            logger.error("Error loading user: \(error.localizedDescription)")
        }

        // Load follow status and counts concurrently
        async let followStatus: Bool = {
            if let currentUserID = authService.currentUser?.id {
                return await socialService.isFollowingAsync(userID: userID, currentUserID: currentUserID)
            }
            return false
        }()
        async let fetchedFollowerCount = socialService.getFollowerCount(for: userID)
        async let fetchedFollowingCount = socialService.getFollowingCount(for: userID)

        isFollowing = await followStatus
        followerCount = await fetchedFollowerCount
        followingCount = await fetchedFollowingCount

        // Load logs (all profiles are public)
        do {
            userLogs = try await feedService.fetchUserLogs(userID: userID)
        } catch {
            logger.error("Error loading user logs: \(error.localizedDescription)")
        }

        // Load trips
        do {
            userTrips = try await tripService.fetchTrips(for: userID)
        } catch {
            logger.error("Error loading user trips: \(error.localizedDescription)")
        }

        rebuildOtherUserCaches()
        isLoading = false
    }

    private func toggleFollow() {
        guard let currentUserID = authService.currentUser?.id else { return }

        isFollowLoading = true

        Task {
            do {
                if isFollowing {
                    try await socialService.unfollowUser(userID: userID, currentUserID: currentUserID)
                    followerCount = max(0, followerCount - 1)
                } else {
                    try await socialService.followUser(userID: userID, currentUserID: currentUserID)
                    followerCount += 1
                }
                isFollowing.toggle()

                SonderHaptics.impact(.light)
            } catch {
                logger.error("Follow error: \(error.localizedDescription)")
            }
            isFollowLoading = false
        }
    }
}

// MARK: - In Common Data

struct InCommonPlace: Identifiable {
    let id: String
    let name: String
    let city: String
    let myRating: Rating
    let theirRating: Rating
    let photoURL: URL?
    let latestDate: Date
}

// MARK: - In Common Detail View

struct InCommonDetailView: View {
    let places: [InCommonPlace]
    let citiesNarrative: String?
    let username: String

    private let columns = [
        GridItem(.flexible(), spacing: SonderSpacing.sm),
        GridItem(.flexible(), spacing: SonderSpacing.sm)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SonderSpacing.md) {
                // Narrative header
                if let narrative = citiesNarrative {
                    Text(narrative)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(SonderColors.inkDark)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SonderSpacing.md)
                }

                if places.isEmpty {
                    VStack(spacing: SonderSpacing.md) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [SonderColors.terracotta.opacity(0.15), SonderColors.ochre.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 32))
                                    .foregroundStyle(SonderColors.terracotta.opacity(0.6))
                            }

                        Text("No shared spots yet")
                            .font(SonderTypography.title)
                            .foregroundStyle(SonderColors.inkDark)

                        Text("You haven't been to the same places — but you've explored the same cities")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, SonderSpacing.xxl)
                } else {
                    // 2-column masonry grid of comparison cards
                    LazyVGrid(columns: columns, spacing: SonderSpacing.sm) {
                        ForEach(places) { place in
                            inCommonGridCard(place)
                        }
                    }
                    .padding(.horizontal, SonderSpacing.md)
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, SonderSpacing.sm)
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle("In Common")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inCommonGridCard(_ place: InCommonPlace) -> some View {
        VStack(spacing: 0) {
            // Photo
            ZStack {
                if let url = place.photoURL {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 200)) {
                        gridPhotoPlaceholder(place)
                    }
                } else {
                    gridPhotoPlaceholder(place)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()

            // Place name + city
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                if !place.city.isEmpty {
                    Text(place.city)
                        .font(.system(size: 11))
                        .foregroundStyle(SonderColors.inkLight)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xs)

            // Split rating comparison
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("You")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SonderColors.inkLight)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(place.myRating.emoji)
                        .font(.system(size: 20))
                    Text(place.myRating.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: place.myRating))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.xs)
                .background(SonderColors.pinColor(for: place.myRating).opacity(0.08))

                Rectangle()
                    .fill(SonderColors.cream)
                    .frame(width: 1)

                VStack(spacing: 2) {
                    Text("Them")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SonderColors.inkLight)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Text(place.theirRating.emoji)
                        .font(.system(size: 20))
                    Text(place.theirRating.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SonderColors.pinColor(for: place.theirRating))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SonderSpacing.xs)
                .background(SonderColors.pinColor(for: place.theirRating).opacity(0.08))
            }
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                .stroke(SonderColors.warmGrayDark, lineWidth: 0.5)
        )
    }

    private func gridPhotoPlaceholder(_ place: InCommonPlace) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
        ]
        let grad = gradients[abs(place.id.hashValue) % gradients.count]
        return LinearGradient(
            colors: [grad.0.opacity(0.6), grad.1.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "mappin.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Other User Log Row

struct OtherUserLogRow: View {
    let feedItem: FeedItem

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo
            if let urlString = feedItem.log.photoURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                    placePhoto
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            } else {
                placePhoto
            }

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                HStack {
                    Text(feedItem.place.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    Spacer()

                    Text(feedItem.rating.emoji)
                }

                Text(feedItem.place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .lineLimit(1)

                Text(feedItem.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11))
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = feedItem.place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                photoPlaceholder
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
            .fill(
                SonderColors.placeholderGradient
            )
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(SonderColors.terracotta.opacity(0.5))
            }
    }
}

// MARK: - Other User All Places View

struct OtherUserAllPlacesView: View {
    let userLogs: [FeedItem]
    let username: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SonderSpacing.sm) {
                ForEach(userLogs.sorted { $0.createdAt > $1.createdAt }) { item in
                    NavigationLink {
                        FeedLogDetailView(feedItem: item)
                    } label: {
                        OtherUserLogRow(feedItem: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle("\(username)'s Places")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        OtherUserProfileView(userID: "user123")
    }
}
