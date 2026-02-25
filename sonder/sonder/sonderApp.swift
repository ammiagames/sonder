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
struct SonderApp: App {
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
    @State private var savedListsService: SavedListsService?
    @State private var contactsService = ContactsService()
    @State private var photoSuggestionService = PhotoSuggestionService()
    @State private var photoIndexService: PhotoIndexService?
    @State private var placeImportService: PlaceImportService?

    init() {
        // Configure Google Places SDK
        GooglePlacesService.configure()

        // Configure Google Sign-In
        GoogleConfig.configure()

        // Configure UIKit appearance to match Sonder theme and prevent gray flashes
        let creamUI = SonderColors.creamUI
        let inkDarkUI = SonderColors.inkDarkUI

        // Prevent the white UIWindow background from flashing between the system
        // launch screen and SwiftUI's first rendered frame (especially visible on
        // slow debug builds where ModelContainer init takes a few seconds).
        UIWindow.appearance().backgroundColor = creamUI

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = creamUI
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Serif (New York) fonts for navigation bar titles
        let largeTitleDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let headlineDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        let serifLargeTitle = UIFont(descriptor: largeTitleDescriptor.withDesign(.serif) ?? largeTitleDescriptor, size: 0)
        let serifTitle = UIFont(descriptor: headlineDescriptor.withDesign(.serif) ?? headlineDescriptor, size: 0)

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = creamUI
        navBarAppearance.shadowColor = .clear
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: inkDarkUI, .font: serifLargeTitle]
        navBarAppearance.titleTextAttributes = [.foregroundColor: inkDarkUI, .font: serifTitle]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = SonderColors.terracottaUI

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
                WantToGo.self,
                PhotoLocationIndex.self,
                SavedList.self
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
    @State private var showSplash = true

    /// True only on the very first launch after install.
    private var isFirstLaunchEver: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if servicesInitialized,
                       let syncEngine, let placesCacheService,
                       let socialService, let feedService,
                       let wantToGoService, let tripService,
                       let savedListsService, let placeImportService {
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
                            contactsService: contactsService,
                            photoSuggestionService: photoSuggestionService,
                            savedListsService: savedListsService,
                            placeImportService: placeImportService
                        )
                    } else {
                        SonderColors.cream.ignoresSafeArea()
                            .onAppear { initializeServices() }
                    }
                }

                // Splash overlay — stays until feed is ready or user needs to log in
                if showSplash {
                    SplashView(isFirstLaunch: isFirstLaunchEver)
                        .transition(.splashLift)
                        .zIndex(1)
                }
            }
            .tint(SonderColors.terracotta)
            .task { await dismissSplashWhenReady() }
            .onAppear { installGlobalKeyboardDismiss() }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Splash Dismissal

    /// First launch: waits for the full typewriter animation, then dismisses
    /// when content is ready. Subsequent launches: dismisses immediately when
    /// content is ready — no minimum wait.
    private func dismissSplashWhenReady() async {
        let firstLaunch = isFirstLaunchEver

        if firstLaunch {
            // Let the typewriter + subtitle animation complete
            try? await Task.sleep(for: .seconds(1.8))
            // Mark so future launches skip the animation
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }

        // Poll until content is ready (max 7s safety timeout)
        for _ in 0..<70 {
            if contentReadyForReveal { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard showSplash else { return }
        // Spring with dampingFraction: 1 = critically damped (smooth, no bounce)
        withAnimation(.spring(response: 0.55, dampingFraction: 1.0)) {
            showSplash = false
        }
    }

    /// True when the screen behind the splash has meaningful content.
    private var contentReadyForReveal: Bool {
        guard servicesInitialized else { return false }
        if authService.isCheckingSession { return false }
        if !authService.isAuthenticated { return true }
        return feedService?.hasLoadedOnce ?? false
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
        savedListsService = SavedListsService(modelContext: ctx)

        // Pass ModelContext to AuthenticationService for user caching
        authService.modelContext = ctx

        // Read current contacts permission state (non-prompting)
        contactsService.checkCurrentStatus()

        // Read current photo permission state (non-prompting)
        photoSuggestionService.checkCurrentAuthorizationStatus()

        // Wire place import service
        placeImportService = PlaceImportService(
            googlePlacesService: googlePlacesService,
            wantToGoService: wantToGoService!,
            savedListsService: savedListsService!,
            placesCacheService: cache
        )

        // Wire photo spatial index
        let photoIndex = PhotoIndexService(modelContainer: modelContainer)
        photoIndexService = photoIndex
        photoSuggestionService.photoIndexService = photoIndex

        // Restore local session synchronously — views depend on currentUser
        authService.restoreLocalSession()

        // Mark initialized — this triggers the RootView to appear
        servicesInitialized = true

        // Refresh user from network in background (also clears isCheckingSession)
        Task {
            await authService.checkSession()
        }

        // Start sync after a short delay so the first frame renders first
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            engine.resumePeriodicSync()
        }

        // Build photo spatial index in background — defer 5s to avoid competing
        // with map/feed loading for CPU, memory, and I/O on cold start
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            let level = photoSuggestionService.authorizationLevel
            if level == .full || level == .limited {
                photoIndex.buildIndexIfNeeded(accessLevel: level == .full ? "full" : "limited")
            }
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
    let contactsService: ContactsService
    let photoSuggestionService: PhotoSuggestionService
    let savedListsService: SavedListsService
    let placeImportService: PlaceImportService

    @Environment(\.modelContext) private var modelContext

    @State private var onboardingComplete = false
    @State private var initialTab: Int = 0

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
            .environment(contactsService)
            .environment(photoSuggestionService)
            .environment(savedListsService)
            .environment(placeImportService)
            .onChange(of: authService.currentUser?.id) { _, newID in
                if let userID = newID {
                    Task {
                        await socialService.refreshCounts(for: userID)
                        // Configure proximity service (don't prompt — only resume if already authorized)
                        proximityService.configure(wantToGoService: wantToGoService, userID: userID)
                        proximityService.setupNotificationCategories()
                        await proximityService.resumeMonitoringIfAuthorized()
                    }
                    // Bootstrap saved lists
                    Task {
                        await savedListsService.fetchLists(for: userID)
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
                    // Bootstrap saved lists
                    await savedListsService.fetchLists(for: userID)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if authService.isCheckingSession {
            // App-level splash overlay covers this
            SonderColors.cream.ignoresSafeArea()
        } else if authService.isAuthenticated {
            if hasCompletedOnboarding {
                MainTabView(initialTab: initialTab)
            } else {
                OnboardingView {
                    markOnboardingComplete()
                    onboardingComplete = true
                }
            }
        } else {
            AuthenticationView()
        }
    }

    // MARK: - Onboarding Gate

    /// Check if onboarding is completed for the current user.
    /// Uses UserDefaults keyed by user ID, with a fallback heuristic:
    /// if the user already has logs, they're not new.
    private var hasCompletedOnboarding: Bool {
        if onboardingComplete { return true }

        guard let userID = authService.currentUser?.id else { return false }

        // Primary: UserDefaults flag
        if UserDefaults.standard.bool(forKey: "onboarding_completed_\(userID)") {
            return true
        }

        // Fallback: existing users who have logs skip onboarding
        if userHasExistingLogs(userID: userID) {
            // Set the flag so we don't re-check next time
            markOnboardingComplete()
            return true
        }

        return false
    }

    private func userHasExistingLogs(userID: String) -> Bool {
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    private func markOnboardingComplete() {
        guard let userID = authService.currentUser?.id else { return }
        UserDefaults.standard.set(true, forKey: "onboarding_completed_\(userID)")
    }
}

// MARK: - Global Keyboard Dismiss

/// Installs a single UIKit tap recognizer on the key window.
/// Because it runs at the UIKit layer (not SwiftUI's gesture system),
/// it fires for ALL views — including Form, UITextField, TextEditor —
/// regardless of how they are backed.  cancelsTouchesInView = false
/// ensures buttons, scroll views, and every other interactive element
/// still receive their taps normally.
private func installGlobalKeyboardDismiss() {
    let keyWindow = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
    guard let window = keyWindow else { return }

    // Guard against installing more than once (onAppear can fire multiple times).
    let alreadyInstalled = window.gestureRecognizers?.contains { $0 is KeyboardDismissTapRecognizer } ?? false
    guard !alreadyInstalled else { return }

    let tap = KeyboardDismissTapRecognizer(
        target: KeyboardDismissTarget.shared,
        action: #selector(KeyboardDismissTarget.dismiss)
    )
    tap.cancelsTouchesInView = false
    window.addGestureRecognizer(tap)
}

/// Marker subclass used to detect whether the gesture was already installed.
private final class KeyboardDismissTapRecognizer: UITapGestureRecognizer {}

/// Objective-C-compatible target that resigns the first responder.
private final class KeyboardDismissTarget: NSObject {
    static let shared = KeyboardDismissTarget()
    @objc func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}
