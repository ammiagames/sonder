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

    @Query private var myLogs: [Log]
    @Query private var myPlaces: [Place]

    @State private var user: User?
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    @State private var followerCount = 0
    @State private var followingCount = 0
    @State private var userLogs: [FeedItem] = []
    @State private var userTrips: [Trip] = []

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
                VStack(spacing: SonderSpacing.lg) {
                    // Profile header card
                    profileHeader(user)

                    // Stats bar
                    statsSection

                    // Follow button
                    if user.id != authService.currentUser?.id {
                        followButton
                            .padding(.horizontal, SonderSpacing.xs)
                    }

                    // View their map banner
                    if !userLogs.isEmpty {
                        viewTheirMapBanner
                    }

                    // In common
                    if !inCommonPlaces.isEmpty || !inCommonCities.isEmpty {
                        inCommonSection
                    }

                    // Rating breakdown
                    if !userLogs.isEmpty {
                        ratingBreakdownSection
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
            await loadData()
        }
    }

    // MARK: - Profile Header

    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: SonderSpacing.sm) {
            // Avatar
            if let urlString = user.avatarURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 88, height: 88)) {
                    avatarPlaceholder(for: user)
                }
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(SonderColors.warmGray, lineWidth: 3)
                )
            } else {
                avatarPlaceholder(for: user)
                    .overlay(
                        Circle()
                            .stroke(SonderColors.warmGray, lineWidth: 3)
                    )
            }

            // Username
            Text("@\(user.username)")
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

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
            HStack(spacing: SonderSpacing.xxs) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SonderColors.sage)
                Text("Exploring since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func avatarPlaceholder(for user: User) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 88, height: 88)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
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
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Recent Trips (Boarding Pass)

    private var recentTrips: [Trip] {
        Array(sortTripsReverseChronological(userTrips).prefix(5))
    }

    // MARK: - Computed Stats

    private var uniqueCities: Set<String> {
        Set(userLogs.compactMap { ProfileStatsService.extractCity(from: $0.place.address) })
    }

    private var uniqueCountries: Set<String> {
        Set(userLogs.compactMap { ProfileStatsService.extractCountry(from: $0.place.address) })
    }

    private var cityCounts: [(city: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in userLogs {
            if let city = ProfileStatsService.extractCity(from: item.place.address) {
                counts[city, default: 0] += 1
            }
        }
        return counts.map { (city: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var ratingCounts: (skip: Int, okay: Int, great: Int, mustSee: Int) {
        var skip = 0, okay = 0, great = 0, mustSee = 0
        for item in userLogs {
            switch item.rating {
            case .skip: skip += 1
            case .okay: okay += 1
            case .great: great += 1
            case .mustSee: mustSee += 1
            }
        }
        return (skip, okay, great, mustSee)
    }

    private var skipCount: Int { ratingCounts.skip }
    private var okayCount: Int { ratingCounts.okay }
    private var greatCount: Int { ratingCounts.great }
    private var mustSeeCount: Int { ratingCounts.mustSee }

    private var ratingPhilosophy: String {
        let total = userLogs.count
        guard total > 0 else { return "" }
        let counts = ratingCounts
        let mustSeePct = Double(counts.mustSee) / Double(total)
        let skipPct = Double(counts.skip) / Double(total)
        let positivePct = Double(counts.great + counts.mustSee) / Double(total)

        if mustSeePct > 0.5 {
            return "Generous — \(Int(mustSeePct * 100))% of their places are Must-See"
        } else if skipPct > 0.4 {
            return "High standards — only the best make the cut"
        } else if mustSeePct < 0.15 && total >= 3 {
            return "A discerning palate — saves Must-See for the truly special"
        } else if positivePct > 0.6 && total >= 3 {
            return "Finds the good in most places — a true optimist"
        } else {
            return "Every place tells a story"
        }
    }

    private var topTagsWithCounts: [(tag: String, count: Int)] {
        let allTags = userLogs.flatMap { $0.log.tags }
        guard !allTags.isEmpty else { return [] }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return Array(tagCounts.prefix(6).map { (tag: $0.key, count: $0.value) })
    }

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

    private static let tripDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private func tripDateText(_ trip: Trip) -> String? {
        let formatter = Self.tripDateFormatter
        if let start = trip.startDate, let end = trip.endDate {
            let startText = formatter.string(from: start)
            let endText = formatter.string(from: end)
            return startText == endText ? startText : "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = trip.startDate {
            return formatter.string(from: start)
        } else if let end = trip.endDate {
            return formatter.string(from: end)
        }
        return nil
    }

    private func tripCoverURL(_ trip: Trip) -> URL? {
        if let cover = trip.coverPhotoURL, let url = URL(string: cover) {
            return url
        }
        return nil
    }

    @ViewBuilder
    private func tripCoverPhoto(_ trip: Trip, size: CGSize) -> some View {
        if let url = tripCoverURL(trip) {
            DownsampledAsyncImage(url: url, targetSize: size) {
                tripPlaceholderGradient(trip)
            }
        } else {
            tripPlaceholderGradient(trip)
        }
    }

    private func tripPlaceholderGradient(_ trip: Trip) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        let grad = gradients[abs(trip.id.hashValue) % gradients.count]
        return LinearGradient(
            colors: [grad.0.opacity(0.7), grad.1.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "airplane")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
        }
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




    // MARK: - Rating Breakdown Section

    private var ratingBreakdownSection: some View {
        let total = userLogs.count

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Ratings")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        if skipCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingSkip)
                                .frame(width: geo.size.width * Double(skipCount) / Double(total))
                        }
                        if okayCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingOkay)
                                .frame(width: geo.size.width * Double(okayCount) / Double(total))
                        }
                        if greatCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingGreat)
                                .frame(width: geo.size.width * Double(greatCount) / Double(total))
                        }
                        if mustSeeCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingMustSee)
                                .frame(width: geo.size.width * Double(mustSeeCount) / Double(total))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Legend
                HStack(spacing: SonderSpacing.sm) {
                    ratingLegendItem(emoji: "👎", count: skipCount, color: SonderColors.ratingSkip)
                    ratingLegendItem(emoji: "👌", count: okayCount, color: SonderColors.ratingOkay)
                    ratingLegendItem(emoji: "⭐", count: greatCount, color: SonderColors.ratingGreat)
                    ratingLegendItem(emoji: "🔥", count: mustSeeCount, color: SonderColors.ratingMustSee)
                }
            }

            Text(ratingPhilosophy)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .italic()
                .padding(.top, SonderSpacing.xxs)
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
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
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    private func tagChip(tag: String, count: Int, isTop: Bool, maxCount: Int) -> some View {
        let weight = CGFloat(count) / CGFloat(maxCount)
        let fontSize: CGFloat = isTop ? 16 : (12 + 4 * weight)
        let hPad: CGFloat = isTop ? SonderSpacing.md : SonderSpacing.sm
        let vPad: CGFloat = isTop ? SonderSpacing.xs : (SonderSpacing.xxs + 2)
        let bgColor: Color = isTop ? SonderColors.terracotta : SonderColors.terracotta.opacity(0.08 + 0.12 * Double(weight))
        let textColor: Color = isTop ? .white : SonderColors.terracotta
        let countColor: Color = isTop ? .white.opacity(0.8) : SonderColors.terracotta.opacity(0.6)

        return HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: fontSize, weight: isTop ? .bold : .medium))
                .foregroundStyle(textColor)
            Text("\(count)")
                .font(.system(size: fontSize - 2, weight: .regular))
                .foregroundStyle(countColor)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(bgColor)
        .clipShape(Capsule())
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
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    private func cityPhotoFallback(index: Int) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        let grad = gradients[index % gradients.count]
        return LinearGradient(
            colors: [grad.0, grad.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - In Common

    /// Places both users have logged, sorted by most recent, capped at 10.
    private var inCommonPlaces: [InCommonPlace] {
        let myPlacesByID = Dictionary(uniqueKeysWithValues: myPlaces.map { ($0.id, $0) })
        let myLogsByPlaceID: [String: Log] = {
            let grouped = Dictionary(grouping: myLogs, by: { $0.placeID })
            return grouped.compactMapValues { $0.sorted { $0.createdAt > $1.createdAt }.first }
        }()
        let theirLogsByPlaceID = Dictionary(grouping: userLogs, by: { $0.place.id })

        let myPlaceIDs = Set(myLogs.map { $0.placeID })
        let commonIDs = myPlaceIDs.intersection(Set(theirLogsByPlaceID.keys))

        return commonIDs.compactMap { placeID -> InCommonPlace? in
            guard let myLog = myLogsByPlaceID[placeID],
                  let theirItems = theirLogsByPlaceID[placeID],
                  let theirItem = theirItems.first else { return nil }

            let place = myPlacesByID[placeID]
            let name = place?.name ?? theirItem.place.name
            let address = place?.address ?? theirItem.place.address
            let city = ProfileStatsService.extractCity(from: address) ?? ""

            // Photo: prefer either user's uploaded photo, then Google reference
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
    }

    /// Cities both users have logged in.
    private var inCommonCities: [String] {
        let myCities = Set(myPlaces.compactMap { ProfileStatsService.extractCity(from: $0.address) })
        let theirCities = Set(userLogs.compactMap { ProfileStatsService.extractCity(from: $0.place.address) })
        return Array(myCities.intersection(theirCities)).sorted()
    }

    private var citiesNarrative: String? {
        let cities = inCommonCities
        guard !cities.isEmpty else { return nil }
        switch cities.count {
        case 1: return "You've both explored \(cities[0])"
        case 2: return "You've both explored \(cities[0]) and \(cities[1])"
        case 3: return "You've both explored \(cities[0]), \(cities[1]), and \(cities[2])"
        default:
            return "You've both explored \(cities[0]), \(cities[1]), \(cities[2]), and \(cities.count - 3) more"
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
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
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
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
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

                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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
