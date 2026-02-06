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
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                } else {
                    AuthenticationView()
                }
            }
            .environment(authService)
            .environment(locationService)
            .environment(googlePlacesService)
            .environment(photoService)
            .environment(syncEngine ?? createSyncEngine())
            .environment(placesCacheService ?? createPlacesCacheService())
            .environment(socialService ?? createSocialService())
            .environment(feedService ?? createFeedService())
            .environment(wantToGoService ?? createWantToGoService())
            .onAppear {
                initializeServices()
            }
            .onChange(of: authService.currentUser?.id) { _, newID in
                // Load social counts when user becomes authenticated
                if let userID = newID {
                    Task {
                        await socialService?.refreshCounts(for: userID)
                    }
                }
            }
            .task {
                // Also load counts on initial app launch if already authenticated
                if let userID = authService.currentUser?.id {
                    await socialService?.refreshCounts(for: userID)
                }
            }
            .onOpenURL { url in
                // Handle Google Sign-In callback URL
                GIDSignIn.sharedInstance.handle(url)
            }
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
}
