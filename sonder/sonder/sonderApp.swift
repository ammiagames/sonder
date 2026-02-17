//
//  sonderApp.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct sonderApp: App {
    // SwiftData model container
    let modelContainer: ModelContainer

    // Services
    @State private var authService = AuthenticationService()
    @State private var syncEngine: SyncEngine?
    @State private var locationService = LocationService()
    @State private var googlePlacesService = GooglePlacesService()
    @State private var placesCacheService: PlacesCacheService?
    @State private var photoService = PhotoService()
    @State private var socialService: SocialService?
    @State private var feedService: FeedService?
    @State private var wantToGoService: WantToGoService?
    @State private var tripService: TripService?
    @State private var proximityService = ProximityNotificationService()
    @State private var exploreMapService = ExploreMapService()
    @State private var photoSuggestionService = PhotoSuggestionService()

    init() {
        // Configure Google Places SDK
        GooglePlacesService.configure()

        // Configure Google Sign-In
        GoogleConfig.configure()

        // Configure UIKit appearance to match Sonder theme and prevent gray flashes
        let creamUI = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1.0)
        let inkDarkUI = UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1.0)
        let inkMutedUI = UIColor(red: 0.50, green: 0.46, blue: 0.42, alpha: 1.0)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = creamUI
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Serif (New York) fonts for navigation bar titles
        let serifLargeTitle = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)!, size: 0)
        let serifTitle = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).withDesign(.serif)!, size: 0)

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = creamUI
        navBarAppearance.shadowColor = .clear
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: inkDarkUI, .font: serifLargeTitle]
        navBarAppearance.titleTextAttributes = [.foregroundColor: inkDarkUI, .font: serifTitle]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.80, green: 0.45, blue: 0.35, alpha: 1.0) // terracotta

        do {
            // Configure SwiftData with all models
            let schema = Schema([
                User.self,
                Place.self,
                Log.self,
                Trip.self,
                TripInvitation.self,
                RecentSearch.self,
                Follow.self,
                WantToGo.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    /// Services that need ModelContext are initialized lazily on first body evaluation
    /// (not in init, because modelContainer.mainContext requires the main actor).
    @State private var servicesInitialized = false

    var body: some Scene {
        WindowGroup {
            Group {
                if servicesInitialized,
                   let syncEngine, let placesCacheService,
                   let socialService, let feedService,
                   let wantToGoService, let tripService {
                    RootView(
                        authService: authService,
                        locationService: locationService,
                        googlePlacesService: googlePlacesService,
                        photoService: photoService,
                        syncEngine: syncEngine,
                        placesCacheService: placesCacheService,
                        socialService: socialService,
                        feedService: feedService,
                        wantToGoService: wantToGoService,
                        tripService: tripService,
                        proximityService: proximityService,
                        exploreMapService: exploreMapService,
                        photoSuggestionService: photoSuggestionService
                    )
                } else {
                    SplashView()
                        .onAppear { initializeServices() }
                }
            }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Service Initialization

    private func initializeServices() {
        guard !servicesInitialized else { return }

        let ctx = modelContainer.mainContext

        // Initialize sync engine — defer the first sync so it doesn't compete with first render
        let engine = SyncEngine(modelContext: ctx, startAutomatically: false)
        syncEngine = engine

        let cache = PlacesCacheService(modelContext: ctx)
        placesCacheService = cache
        googlePlacesService.cachedPhotoReferenceLookup = { [weak cache] placeId in
            cache?.getPlace(by: placeId)?.photoReference
        }

        socialService = SocialService(modelContext: ctx)
        feedService = FeedService(modelContext: ctx)
        wantToGoService = WantToGoService(modelContext: ctx)
        tripService = TripService(modelContext: ctx)

        // Pass ModelContext to AuthenticationService for user caching
        authService.modelContext = ctx

        // Mark initialized — this triggers the RootView to appear
        servicesInitialized = true

        // Start sync after a short delay so the first frame renders first
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            engine.resumePeriodicSync()
        }
    }
}

// MARK: - Root View

struct RootView: View {
    let authService: AuthenticationService
    let locationService: LocationService
    let googlePlacesService: GooglePlacesService
    let photoService: PhotoService
    let syncEngine: SyncEngine
    let placesCacheService: PlacesCacheService
    let socialService: SocialService
    let feedService: FeedService
    let wantToGoService: WantToGoService
    let tripService: TripService
    let proximityService: ProximityNotificationService
    let exploreMapService: ExploreMapService
    let photoSuggestionService: PhotoSuggestionService

    var body: some View {
        contentView
            .environment(authService)
            .environment(locationService)
            .environment(googlePlacesService)
            .environment(photoService)
            .environment(syncEngine)
            .environment(placesCacheService)
            .environment(socialService)
            .environment(feedService)
            .environment(wantToGoService)
            .environment(tripService)
            .environment(proximityService)
            .environment(exploreMapService)
            .environment(photoSuggestionService)
            .onChange(of: authService.currentUser?.id) { _, newID in
                if let userID = newID {
                    Task {
                        await socialService.refreshCounts(for: userID)
                        // Configure proximity service (don't prompt — only resume if already authorized)
                        proximityService.configure(wantToGoService: wantToGoService, userID: userID)
                        proximityService.setupNotificationCategories()
                        await proximityService.resumeMonitoringIfAuthorized()
                    }
                    // Defer full sync so the feed can load first
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        await syncEngine.syncNow()
                    }
                } else {
                    // User logged out - stop monitoring
                    proximityService.stopMonitoring()
                }
            }
            .task {
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                    // Configure proximity service (don't prompt — only resume if already authorized)
                    proximityService.configure(wantToGoService: wantToGoService, userID: userID)
                    proximityService.setupNotificationCategories()
                    await proximityService.resumeMonitoringIfAuthorized()
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if authService.isCheckingSession {
            // Show splash while restoring session to avoid flashing the auth screen
            SplashView()
        } else if authService.isAuthenticated {
            MainTabView()
        } else {
            AuthenticationView()
        }
    }
}
