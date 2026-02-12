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

    init() {
        // Configure Google Sign-In
        GoogleConfig.configure()

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
            engine.photoService = photoService
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
        let engine = SyncEngine(modelContext: modelContainer.mainContext)
        engine.photoService = photoService
        return engine
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
            .onAppear(perform: onAppear)
            .onChange(of: authService.currentUser?.id) { _, newID in
                if let userID = newID {
                    Task {
                        await socialService.refreshCounts(for: userID)
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
        if authService.isAuthenticated {
            MainTabView()
        } else {
            AuthenticationView()
        }
    }
}
