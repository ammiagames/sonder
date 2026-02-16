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

    init() {
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

    var body: some Scene {
        WindowGroup {
            RootView(
                authService: authService,
                locationService: locationService,
                googlePlacesService: googlePlacesService,
                photoService: photoService,
                syncEngine: syncEngine ?? createSyncEngine(),
                placesCacheService: placesCacheService ?? createPlacesCacheService(),
                socialService: socialService ?? createSocialService(),
                feedService: feedService ?? createFeedService(),
                wantToGoService: wantToGoService ?? createWantToGoService(),
                tripService: tripService ?? createTripService(),
                proximityService: proximityService,
                exploreMapService: exploreMapService,
                onAppear: initializeServices
            )
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Service Initialization

    private func initializeServices() {
        // Initialize sync engine
        if syncEngine == nil {
            let engine = SyncEngine(modelContext: modelContainer.mainContext)
            syncEngine = engine
        }

        // Initialize places cache service
        if placesCacheService == nil {
            placesCacheService = PlacesCacheService(modelContext: modelContainer.mainContext)
        }

        // Initialize social services
        if socialService == nil {
            socialService = SocialService(modelContext: modelContainer.mainContext)
        }

        if feedService == nil {
            feedService = FeedService(modelContext: modelContainer.mainContext)
        }

        if wantToGoService == nil {
            wantToGoService = WantToGoService(modelContext: modelContainer.mainContext)
        }

        if tripService == nil {
            tripService = TripService(modelContext: modelContainer.mainContext)
        }
    }

    private func createSyncEngine() -> SyncEngine {
        SyncEngine(modelContext: modelContainer.mainContext)
    }

    private func createPlacesCacheService() -> PlacesCacheService {
        PlacesCacheService(modelContext: modelContainer.mainContext)
    }

    private func createSocialService() -> SocialService {
        SocialService(modelContext: modelContainer.mainContext)
    }

    private func createFeedService() -> FeedService {
        FeedService(modelContext: modelContainer.mainContext)
    }

    private func createWantToGoService() -> WantToGoService {
        WantToGoService(modelContext: modelContainer.mainContext)
    }

    private func createTripService() -> TripService {
        TripService(modelContext: modelContainer.mainContext)
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
    let onAppear: () -> Void

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
            .onAppear(perform: onAppear)
            .onChange(of: authService.currentUser?.id) { _, newID in
                if let userID = newID {
                    Task {
                        await socialService.refreshCounts(for: userID)
                        // Pull remote data immediately on login
                        await syncEngine.syncNow()
                        // Configure and start proximity monitoring
                        proximityService.configure(wantToGoService: wantToGoService, userID: userID)
                        proximityService.setupNotificationCategories()
                        await proximityService.startMonitoring()
                    }
                } else {
                    // User logged out - stop monitoring
                    proximityService.stopMonitoring()
                }
            }
            .task {
                if let userID = authService.currentUser?.id {
                    await socialService.refreshCounts(for: userID)
                    // Start proximity monitoring for existing session
                    proximityService.configure(wantToGoService: wantToGoService, userID: userID)
                    proximityService.setupNotificationCategories()
                    await proximityService.startMonitoring()
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
