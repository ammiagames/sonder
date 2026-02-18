//
//  ProfileView.swift
//  sonder
//
//  Extracted from MainTabView.swift
//

import SwiftUI
import SwiftData
import CoreLocation

/// Routing enum for programmatic navigation in ProfileView
enum ProfileDestination: Hashable {
    case followers
    case following
    case wantToGo
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
    @Query private var allLogs: [Log]
    @Query private var places: [Place]
    @Query(sort: \Trip.updatedAt, order: .reverse) private var allTrips: [Trip]

    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var showShareProfile = false
    @State private var wantToGoCount = 0
    @State private var profileStats: ProfileStats?
    @State private var activeDestination: ProfileDestination?

    @Binding var selectedTab: Int
    @Binding var exploreFocusMyPlaces: Bool
    var popToRoot: UUID = UUID()

    /// Logs filtered to current user only
    private var logs: [Log] {
        guard let userID = authService.currentUser?.id else { return [] }
        return allLogs.filter { $0.userID == userID }
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
                        heroStatSection

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

                        // Streak + insights
                        if let stats = profileStats {
                            ProfileInsightsSection(stats: stats)
                        }

                        // Bookends
                        if let stats = profileStats, let bookends = stats.bookends {
                            bookendsSection(bookends: bookends)
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
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                }
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
                case .city(let name):
                    CityLogsView(title: name, logs: logsForCity(name))
                case .tag(let name):
                    FilteredLogsListView(title: name, logs: logsForTag(name))
                case .logDetail(let logID, let placeID):
                    if let log = logs.first(where: { $0.id == logID }),
                       let place = places.first(where: { $0.id == placeID }) {
                        LogDetailView(log: log, place: place)
                    }
                case .trip(let trip):
                    TripDetailView(trip: trip)
                }
            }
            .onChange(of: popToRoot) {
                activeDestination = nil
            }
            .onChange(of: logs.count) {
                recomputeStats()
            }
            .onAppear {
                recomputeStats()
            }
        }
    }

    // MARK: - Recent Trips (Shared Helpers)

    private var userTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        let filtered = allTrips.filter { $0.createdBy == userID || $0.collaboratorIDs.contains(userID) }
        return sortTripsReverseChronological(filtered)
    }

    private var recentTrips: [Trip] {
        Array(userTrips.prefix(5))
    }

    private func tripLogCount(_ trip: Trip) -> Int {
        logs.filter { $0.tripID == trip.id }.count
    }

    private func tripDateText(_ trip: Trip) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
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
        let tripLogs = logs.filter { $0.tripID == trip.id }
            .sorted { $0.createdAt > $1.createdAt }
        if let photoURL = tripLogs.first(where: { $0.photoURL != nil })?.photoURL,
           let url = URL(string: photoURL) {
            return url
        }
        return nil
    }

    private func tripGradient(_ trip: Trip) -> (Color, Color) {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        return gradients[abs(trip.id.hashValue) % gradients.count]
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
        let grad = tripGradient(trip)
        return LinearGradient(
            colors: [grad.0.opacity(0.7), grad.1.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "airplane")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Recent Trips Section

    private var recentTripsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Recent trips")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
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
                    .foregroundColor(SonderColors.inkLight)
                    .tracking(0.5)

                Text(trip.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: SonderSpacing.md) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DATE")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(SonderColors.inkLight)
                            .tracking(0.5)
                        Text(tripDateText(trip) ?? "—")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("PLACES")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(SonderColors.inkLight)
                            .tracking(0.5)
                        Text("\(tripLogCount(trip))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
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


    // MARK: - Stats Computation

    private func recomputeStats() {
        let userPlaceIDs = Set(logs.map { $0.placeID })
        let relevantPlaces = places.filter { userPlaceIDs.contains($0.id) }
        profileStats = ProfileStatsService.compute(logs: logs, places: relevantPlaces)
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
                            .foregroundColor(SonderColors.inkDark)
                    } else {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .frame(height: 28)
                    }
                    Text("Followers")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
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
                            .foregroundColor(SonderColors.inkDark)
                    } else {
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .frame(height: 28)
                    }
                    Text("Following")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Want to Go Link

    private var wantToGoLink: some View {
        Button {
            activeDestination = .wantToGo
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Bookmark icon with warm background
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16))
                    .foregroundColor(SonderColors.terracotta)
                    .frame(width: 36, height: 36)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Want to Go")
                        .font(SonderTypography.headline)
                        .foregroundColor(SonderColors.inkDark)

                    if wantToGoCount > 0 {
                        Text("\(wantToGoCount) saved")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    } else {
                        Text("Save places to visit later")
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SonderColors.inkLight)
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
        .buttonStyle(.plain)
        .task {
            await loadWantToGoCount()
        }
    }

    private func loadWantToGoCount() async {
        guard let userID = authService.currentUser?.id else { return }
        do {
            let items = try await wantToGoService.fetchWantToGoWithPlaces(for: userID)
            wantToGoCount = items.count
        } catch {
            print("Error loading want to go count: \(error)")
        }
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
                            .foregroundColor(.white)
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
                .foregroundColor(SonderColors.inkDark)

            // Archetype badge
            if let stats = profileStats, stats.totalLogs > 0 {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: stats.archetype.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(stats.archetype.displayName)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(SonderColors.terracotta)
                .padding(.horizontal, SonderSpacing.sm)
                .padding(.vertical, SonderSpacing.xxs)
                .background(SonderColors.terracotta.opacity(0.12))
                .clipShape(Capsule())
            }

            // Bio
            if let bio = authService.currentUser?.bio, !bio.isEmpty {
                Text(bio)
                    .font(SonderTypography.body)
                    .foregroundColor(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SonderSpacing.lg)
            }

            // Member since
            if let user = authService.currentUser {
                Text("Journaling since \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
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
                    .foregroundColor(SonderColors.inkDark)
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
                    .foregroundColor(SonderColors.terracotta)
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
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(authService.currentUser?.username.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Hero Stat Section

    private var heroStatSection: some View {
        VStack(spacing: SonderSpacing.xs) {
            Text("\(logs.count)")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundColor(SonderColors.inkDark)

            Text("places logged")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkMuted)

            // Breakdown line
            let parts: [String] = {
                var p: [String] = []
                if uniqueCities.count > 1 {
                    p.append("\(uniqueCities.count) cities")
                }
                if uniqueCountries.count > 1 {
                    p.append("\(uniqueCountries.count) countries")
                }
                return p
            }()

            if !parts.isEmpty {
                Text("across " + parts.joined(separator: " in "))
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkLight)
            }

            // Momentum indicator
            let thisMonthCount = logsThisMonth
            if thisMonthCount > 0 {
                Text("\(thisMonthCount) place\(thisMonthCount == 1 ? "" : "s") this month")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SonderColors.terracotta)
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xxs)
                    .background(SonderColors.terracotta.opacity(0.1))
                    .clipShape(Capsule())
                    .padding(.top, SonderSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SonderSpacing.lg)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Enhanced Rating Section

    private func enhancedRatingSection(stats: ProfileStats) -> some View {
        let dist = stats.ratingDistribution
        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Ratings")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
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
                        if dist.solidCount > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SonderColors.ratingSolid)
                                .frame(width: geo.size.width * dist.solidPercentage)
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
                HStack(spacing: SonderSpacing.md) {
                    ratingLegendItem(emoji: "👎", label: "Skip", count: dist.skipCount, color: SonderColors.ratingSkip)
                    ratingLegendItem(emoji: "👍", label: "Solid", count: dist.solidCount, color: SonderColors.ratingSolid)
                    ratingLegendItem(emoji: "🔥", label: "Must-See", count: dist.mustSeeCount, color: SonderColors.ratingMustSee)
                }
            }

            // Philosophy one-liner
            Text(dist.philosophy)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
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
                .foregroundColor(SonderColors.inkDark)
        }
    }

    // MARK: - Bookends Section

    private func bookendsSection(bookends: Bookends) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Your journey")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: SonderSpacing.sm) {
                // First log
                VStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 16))
                        .foregroundColor(SonderColors.sage)
                    Text(bookends.firstPlaceName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let city = bookends.firstCity {
                        Text(city)
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.inkMuted)
                    }
                    Text(bookends.firstDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundColor(SonderColors.inkLight)
                }
                .frame(maxWidth: .infinity)

                // Arrow + days
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SonderColors.terracotta)
                    Text("\(bookends.daysBetween)d")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SonderColors.inkMuted)
                }

                // Latest log
                VStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(SonderColors.terracotta)
                    Text(bookends.latestPlaceName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let city = bookends.latestCity {
                        Text(city)
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.inkMuted)
                    }
                    Text(bookends.latestDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundColor(SonderColors.inkLight)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - You Love Section

    private var youLoveSection: some View {
        let tagData = topTagsWithCounts
        let maxCount = tagData.first?.count ?? 1

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("You love")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
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
                .foregroundColor(textColor)
            Text("\(count)")
                .font(.system(size: fontSize - 2, weight: .regular))
                .foregroundColor(countColor)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(bgColor)
        .clipShape(Capsule())
    }

    // MARK: - City Data (shared)

    private var cityCounts: [(city: String, count: Int)] {
        var counts: [String: Int] = [:]
        for place in userPlaces {
            if let city = extractCity(from: place.address) {
                counts[city, default: 0] += 1
            }
        }
        return counts.map { (city: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - City Photo Helper

    private func cityPhotoURL(_ city: String, maxWidth: Int = 400) -> URL? {
        let cityPlaces = userPlaces.filter { extractCity(from: $0.address) == city }
        let cityLogs = logs.filter { log in cityPlaces.contains(where: { $0.id == log.placeID }) }

        if let userPhoto = cityLogs.sorted(by: { $0.createdAt > $1.createdAt })
            .first(where: { $0.photoURL != nil })?.photoURL,
           let url = URL(string: userPhoto) {
            return url
        }

        let placesByLogCount = cityPlaces.sorted { p1, p2 in
            cityLogs.filter { $0.placeID == p1.id }.count > cityLogs.filter { $0.placeID == p2.id }.count
        }
        if let ref = placesByLogCount.first(where: { $0.photoReference != nil })?.photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: maxWidth) {
            return url
        }

        return nil
    }

    // MARK: - Top Cities Photo Mosaic

    private var cityOption7_PhotoMosaic: some View {
        let items = Array(cityCounts.prefix(5))

        return VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Your top cities")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
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
                                .foregroundColor(.white)
                            Text("\(hero.count) place\(hero.count == 1 ? "" : "s") logged")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
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
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text("\(item.count)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
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

    // MARK: - Computed Stats

    private var userPlaces: [Place] {
        let loggedPlaceIDs = Set(logs.map { $0.placeID })
        return places.filter { loggedPlaceIDs.contains($0.id) }
    }

    private var uniqueCities: Set<String> {
        Set(userPlaces.compactMap { extractCity(from: $0.address) })
    }

    private var uniqueCountries: Set<String> {
        Set(userPlaces.compactMap { extractCountry(from: $0.address) })
    }

    private var topTagsForShare: [String] {
        let allTags = logs.flatMap { $0.tags }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return Array(tagCounts.prefix(4).map { $0.key })
    }

    private var topTagsWithCounts: [(tag: String, count: Int)] {
        let allTags = logs.flatMap { $0.tags }
        guard !allTags.isEmpty else { return [] }
        let tagCounts = Dictionary(grouping: allTags, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return Array(tagCounts.prefix(6).map { (tag: $0.key, count: $0.value) })
    }

    private var topTags: [String] {
        topTagsWithCounts.map(\.tag)
    }

    private var logsThisMonth: Int {
        let now = Date()
        let calendar = Calendar.current
        return logs.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }.count
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
        let components = address.components(separatedBy: ", ")
        guard components.count >= 2 else { return nil }
        if components.count >= 3 {
            return components[components.count - 3]
        }
        return components[0]
    }

    private func extractCountry(from address: String) -> String? {
        let components = address.components(separatedBy: ", ")
        guard let last = components.last else { return nil }
        let trimmed = last.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 2 || trimmed.allSatisfy({ $0.isNumber }) {
            return components.count >= 2 ? components[components.count - 2] : nil
        }
        return trimmed
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
                        LogDetailView(log: log, place: place)
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
                                    .foregroundColor(SonderColors.inkDark)
                                    .lineLimit(1)

                                Text(place.address)
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.inkMuted)
                                    .lineLimit(1)

                                Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12))
                                    .foregroundColor(SonderColors.inkLight)
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
