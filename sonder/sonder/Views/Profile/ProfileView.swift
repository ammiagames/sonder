//
//  ProfileView.swift
//  sonder
//
//  Extracted from MainTabView.swift
//

import SwiftUI
import SwiftData
import CoreLocation
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "ProfileView")

/// Routing enum for programmatic navigation in ProfileView
enum ProfileDestination: Hashable {
    case followers
    case following
    case wantToGo
    case savedLists
    case city(String)
    case tag(String)
    case logDetail(logID: String, placeID: String)
    case trip(Trip)
}

struct ProfileView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(SocialService.self) private var socialService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(SavedListsService.self) private var savedListsService
    @Environment(\.modelContext) private var modelContext
    @State private var logs: [Log] = []
    @Query private var places: [Place]
    @State private var trips: [Trip] = []

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showShareProfile = false
@State private var profileStats: ProfileStats?
    @State private var activeDestination: ProfileDestination?

    @Binding var selectedTab: Int
    @Binding var exploreFocusMyPlaces: Bool
    var popToRoot: UUID = UUID()

    // Cached computed stats — rebuilt when logs/places change
    @State private var cachedUserPlaces: [Place] = []
    @State private var cachedUniqueCities: Set<String> = []
    @State private var cachedUniqueCountries: Set<String> = []
    @State private var cachedTopTagsWithCounts: [(tag: String, count: Int)] = []
    @State private var cachedCityCounts: [(city: String, count: Int)] = []
    @State private var cachedTripLogCounts: [String: Int] = [:]
    @State private var cachedCityPhotoURLs: [String: URL] = [:]

    private func refreshData() {
        guard let userID = authService.currentUser?.id else { return }
        let logDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        logs = (try? modelContext.fetch(logDescriptor)) ?? []

        let tripDescriptor = FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let allTrips = (try? modelContext.fetch(tripDescriptor)) ?? []
        trips = allTrips.filter { $0.isAccessible(by: userID) }

        rebuildProfileCaches()
    }

    private func rebuildProfileCaches() {
        // User places
        let loggedPlaceIDs = Set(logs.map { $0.placeID })
        let uPlaces = places.filter { loggedPlaceIDs.contains($0.id) }
        cachedUserPlaces = uPlaces

        // Cities + countries
        cachedUniqueCities = Set(uPlaces.compactMap { extractCity(from: $0.address) })
        cachedUniqueCountries = Set(uPlaces.compactMap { extractCountry(from: $0.address) })

        // Tags
        let allTags = logs.flatMap { $0.tags }
        if allTags.isEmpty {
            cachedTopTagsWithCounts = []
        } else {
            cachedTopTagsWithCounts = Dictionary(grouping: allTags, by: { $0 })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
                .prefix(6)
                .map { (tag: $0.key, count: $0.value) }
        }

        // City counts
        var counts: [String: Int] = [:]
        for place in uPlaces {
            if let city = extractCity(from: place.address) {
                counts[city, default: 0] += 1
            }
        }
        cachedCityCounts = counts.map { (city: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        // Trip log counts
        var tripCounts: [String: Int] = [:]
        for log in logs {
            if let tripID = log.tripID { tripCounts[tripID, default: 0] += 1 }
        }
        cachedTripLogCounts = tripCounts

        // City photo URLs (pre-computed with O(n) placeID→logCount dictionary)
        var logCountByPlaceID: [String: Int] = [:]
        for log in logs { logCountByPlaceID[log.placeID, default: 0] += 1 }

        var cityURLs: [String: URL] = [:]
        for (city, _) in cachedCityCounts.prefix(5) {
            let cityPlaces = uPlaces.filter { extractCity(from: $0.address) == city }
            let cityPlaceIDs = Set(cityPlaces.map(\.id))
            let cityLogs = logs.filter { cityPlaceIDs.contains($0.placeID) }

            if let userPhoto = cityLogs.sorted(by: { $0.createdAt > $1.createdAt })
                .first(where: { $0.photoURL != nil })?.photoURL,
               let url = URL(string: userPhoto) {
                cityURLs[city] = url
                continue
            }

            let placesByLogCount = cityPlaces.sorted { p1, p2 in
                (logCountByPlaceID[p1.id] ?? 0) > (logCountByPlaceID[p2.id] ?? 0)
            }
            if let ref = placesByLogCount.first(where: { $0.photoReference != nil })?.photoReference,
               let url = GooglePlacesService.photoURL(for: ref, maxWidth: 400) {
                cityURLs[city] = url
            }
        }
        cachedCityPhotoURLs = cityURLs

        // Profile stats
        profileStats = ProfileStatsService.compute(logs: logs, places: uPlaces)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.lg) {
                    // Profile header (avatar + username + bio + archetype badge)
                    profileHeader

                    // Social stats (followers/following)
                    socialStatsSection

                    // Want to Go link
                    wantToGoLink

                    // Recent trips
                    if !recentTrips.isEmpty {
                        recentTripsSection
                    }

                    // Journey stats (only show if has logs)
                    if !logs.isEmpty {
                        // Taste DNA radar chart (needs >= 3 logs)
                        if let stats = profileStats, stats.totalLogs >= 3, !stats.tasteDNA.isEmpty {
                            TasteDNARadarChart(tasteDNA: stats.tasteDNA)
                        }

                        // Enhanced rating section
                        if let stats = profileStats {
                            enhancedRatingSection(stats: stats)
                        }

                        if !topTags.isEmpty {
                            youLoveSection
                        }


                    }

                    // Top cities
                    if !uniqueCities.isEmpty {
                        cityOption7_PhotoMosaic
                    }

                }
                .padding(SonderSpacing.md)
                .padding(.bottom, 80)
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Your Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(SonderColors.inkDark)
                            .toolbarIcon()
                    }
                }
            }
            .tint(SonderColors.terracotta)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showShareProfile) {
                ShareProfileCardView(
                    placesCount: logs.count,
                    citiesCount: uniqueCities.count,
                    countriesCount: uniqueCountries.count,
                    topTags: topTagsForShare,
                    mustSeeCount: logs.filter { $0.rating == .mustSee }.count
                )
            }
            .refreshable {
                await syncEngine.forceSyncNow()
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                }
            }
            .task {
                refreshData()
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                    if wantToGoService.items.isEmpty {
                        wantToGoService.items = wantToGoService.getWantToGoList(for: userID)
                    }
                }
            }
            .onChange(of: syncEngine.lastSyncDate) { _, _ in
                refreshData()
            }
            .onChange(of: places.count) { _, _ in
                rebuildProfileCaches()
            }
            .navigationDestination(item: $activeDestination) { dest in
                switch dest {
                case .followers:
                    FollowListView(
                        userID: authService.currentUser?.id ?? "",
                        username: authService.currentUser?.username ?? "",
                        initialTab: .followers
                    )
                case .following:
                    FollowListView(
                        userID: authService.currentUser?.id ?? "",
                        username: authService.currentUser?.username ?? "",
                        initialTab: .following
                    )
                case .wantToGo:
                    WantToGoListView()
                case .savedLists:
                    WantToGoListView()
                case .city(let name):
                    CityLogsView(title: name, logs: logsForCity(name))
                case .tag(let name):
                    FilteredLogsListView(title: name, logs: logsForTag(name))
                case .logDetail(let logID, let placeID):
                    if let log = logs.first(where: { $0.id == logID }),
                       let place = places.first(where: { $0.id == placeID }) {
                        LogViewScreen(log: log, place: place)
                    } else {
                        // Data became stale — pop back
                        Color.clear.onAppear { activeDestination = nil }
                    }
                case .trip(let trip):
                    TripDetailView(trip: trip)
                }
            }
            .onChange(of: popToRoot) {
                activeDestination = nil
            }
        }
    }

    // MARK: - Recent Trips (Shared Helpers)

    private var sortedTrips: [Trip] {
        sortTripsReverseChronological(trips)
    }

    private var recentTrips: [Trip] {
        Array(sortedTrips.prefix(5))
    }

    private func tripLogCount(_ trip: Trip) -> Int {
        cachedTripLogCounts[trip.id] ?? 0
    }

    private func tripDateText(_ trip: Trip) -> String? {
        ProfileShared.tripDateText(trip)
    }

    private func tripCoverURL(_ trip: Trip) -> URL? {
        if let cover = trip.coverPhotoURL, let url = URL(string: cover) {
            return url
        }
        let tripLogs = logs.filter { $0.tripID == trip.id }
            .sorted { $0.createdAt > $1.createdAt }
        if let photoURL = tripLogs.first(where: { $0.photoURL != nil })?.photoURL,
           let url = URL(string: photoURL) {
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

    // MARK: - Recent Trips Section

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
                        Button {
                            activeDestination = .trip(trip)
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
            // Left: photo stub
            tripCoverPhoto(trip, size: CGSize(width: 72, height: 100))
                .frame(width: 72, height: 100)
                .clipped()

            // Perforated divider
            VStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle()
                        .fill(SonderColors.cream)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 12)
            .background(SonderColors.warmGray)

            // Right: ticket info
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

                    VStack(alignment: .leading, spacing: 1) {
                        Text("PLACES")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(SonderColors.inkLight)
                            .tracking(0.5)
                        Text("\(tripLogCount(trip))")
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


    // MARK: - Social Stats Section

    private var socialStatsSection: some View {
        HStack(spacing: SonderSpacing.xxl) {
            Button {
                activeDestination = .followers
            } label: {
                VStack(spacing: SonderSpacing.xxs) {
                    if socialService.countsLoaded {
                        Text("\(socialService.followerCount)")
                            .font(SonderTypography.title)
                            .foregroundStyle(SonderColors.inkDark)
                    } else {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .frame(height: 28)
                    }
                    Text("Followers")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .buttonStyle(.plain)

            // Divider dot
            Circle()
                .fill(SonderColors.inkLight)
                .frame(width: 4, height: 4)

            Button {
                activeDestination = .following
            } label: {
                VStack(spacing: SonderSpacing.xxs) {
                    if socialService.countsLoaded {
                        Text("\(socialService.followingCount)")
                            .font(SonderTypography.title)
                            .foregroundStyle(SonderColors.inkDark)
                    } else {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .frame(height: 28)
                    }
                    Text("Following")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Want to Go Link

    private var wantToGoLink: some View {
        let listCount = savedListsService.lists.count

        return Button {
            activeDestination = .savedLists
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Bookmark icon with warm background
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SonderColors.terracotta)
                    .frame(width: 36, height: 36)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved Lists")
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)

                    if listCount > 0 {
                        Text("\(listCount) list\(listCount == 1 ? "" : "s")")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    } else {
                        Text("Save places to visit later")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
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

    // MARK: - Profile Header

    private var hasAvatarPhoto: Bool {
        authService.currentUser?.avatarURL != nil
    }

    private var profileHeader: some View {
        VStack(spacing: SonderSpacing.sm) {
            // Avatar (tappable to edit profile)
            Button {
                showEditProfile = true
            } label: {
                ZStack {
                    if let urlString = authService.currentUser?.avatarURL,
                       let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 100, height: 100)) {
                            avatarPlaceholder
                        }
                        .id(urlString)
                    } else {
                        avatarPlaceholder
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(SonderColors.cream, lineWidth: 4)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .overlay(alignment: .bottomTrailing) {
                    if !hasAvatarPhoto {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(SonderColors.terracotta)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(SonderColors.cream, lineWidth: 2)
                            }
                            .offset(x: 4, y: 4)
                    }
                }
            }
            .buttonStyle(.plain)

            // Username
            Text(authService.currentUser?.username ?? "User")
                .font(SonderTypography.largeTitle)
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Archetype badge
            if let stats = profileStats, stats.totalLogs > 0 {
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

            // Journey stats subtitle
            if !logs.isEmpty {
                let parts: [String] = {
                    var p = ["\(logs.count) places"]
                    if uniqueCities.count > 1 { p.append("\(uniqueCities.count) cities") }
                    if uniqueCountries.count > 1 { p.append("\(uniqueCountries.count) countries") }
                    return p
                }()
                Text(parts.joined(separator: " · "))
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }




            // Member since
            if let user = authService.currentUser {
                Text("Journaling since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkLight)
            }

            // Edit Profile & Share buttons
            HStack(spacing: SonderSpacing.sm) {
                Button {
                    showEditProfile = true
                } label: {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "pencil")
                        Text("Edit Profile")
                    }
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(SonderColors.warmGray)
                    .clipShape(Capsule())
                }

                Button {
                    showShareProfile = true
                } label: {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.terracotta)
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(SonderColors.terracotta.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, SonderSpacing.sm)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .overlay {
                Text(authService.currentUser?.username.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
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

            // Rating bar
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
                    ratingLegendItem(emoji: "👎", label: "Skip", count: dist.skipCount, color: SonderColors.ratingSkip)
                    ratingLegendItem(emoji: "👌", label: "Okay", count: dist.okayCount, color: SonderColors.ratingOkay)
                    ratingLegendItem(emoji: "⭐", label: "Great", count: dist.greatCount, color: SonderColors.ratingGreat)
                    ratingLegendItem(emoji: "🔥", label: "Must-See", count: dist.mustSeeCount, color: SonderColors.ratingMustSee)
                }
            }

            // Philosophy one-liner
            Text(dist.philosophy)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .italic()
                .padding(.top, SonderSpacing.xxs)
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    private func ratingLegendItem(emoji: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(emoji) \(count)")
                .font(.system(size: 12))
                .foregroundStyle(SonderColors.inkDark)
        }
    }

    // MARK: - You Love Section

    private var youLoveSection: some View {
        let tagData = topTagsWithCounts
        let maxCount = tagData.first?.count ?? 1

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("You love")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            FlowLayoutWrapper {
                ForEach(tagData, id: \.tag) { item in
                    Button {
                        activeDestination = .tag(item.tag)
                    } label: {
                        tagChip(tag: item.tag, count: item.count, isTop: item.tag == tagData.first?.tag, maxCount: maxCount)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    private func tagChip(tag: String, count: Int, isTop: Bool, maxCount: Int) -> some View {
        ProfileShared.tagChip(tag: tag, count: count, isTop: isTop, maxCount: maxCount)
    }

    // MARK: - City Data (shared)

    private var cityCounts: [(city: String, count: Int)] { cachedCityCounts }

    // MARK: - City Photo Helper

    private func cityPhotoURL(_ city: String, maxWidth: Int = 400) -> URL? {
        cachedCityPhotoURLs[city]
    }

    // MARK: - Top Cities Photo Mosaic

    private var cityOption7_PhotoMosaic: some View {
        let items = Array(cityCounts.prefix(5))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Your top cities")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            if let hero = items.first {
                Button {
                    activeDestination = .city(hero.city)
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
                        Button {
                            activeDestination = .city(item.city)
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
        ProfileShared.cityPhotoFallback(index: index)
    }

    // MARK: - Computed Stats

    private var userPlaces: [Place] { cachedUserPlaces }
    private var uniqueCities: Set<String> { cachedUniqueCities }
    private var uniqueCountries: Set<String> { cachedUniqueCountries }

    private var topTagsForShare: [String] {
        Array(cachedTopTagsWithCounts.prefix(4).map(\.tag))
    }

    private var topTagsWithCounts: [(tag: String, count: Int)] { cachedTopTagsWithCounts }

    private var topTags: [String] {
        cachedTopTagsWithCounts.map(\.tag)
    }

    private func logsForTag(_ tag: String) -> [Log] {
        logs.filter { $0.tags.contains(tag) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func logsForCity(_ city: String) -> [Log] {
        logs.filter { log in
            guard let place = places.first(where: { $0.id == log.placeID }) else { return false }
            return extractCity(from: place.address) == city
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func extractCity(from address: String) -> String? {
        ProfileStatsService.extractCity(from: address)
    }

    private func extractCountry(from address: String) -> String? {
        ProfileStatsService.extractCountry(from: address)
    }
}

// MARK: - Filtered Logs List View

struct FilteredLogsListView: View {
    let title: String
    let logs: [Log]
    @Query private var places: [Place]

    var body: some View {
        List {
            ForEach(logs, id: \.id) { log in
                if let place = places.first(where: { $0.id == log.placeID }) {
                    NavigationLink {
                        LogViewScreen(log: log, place: place)
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Text(log.rating.emoji)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .background(SonderColors.pinColor(for: log.rating).opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(SonderColors.inkDark)
                                    .lineLimit(1)

                                Text(place.address)
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkMuted)
                                    .lineLimit(1)

                                Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12))
                                    .foregroundStyle(SonderColors.inkLight)
                            }

                            Spacer()
                        }
                    }
                    .listRowBackground(SonderColors.warmGray)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SonderColors.cream)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
