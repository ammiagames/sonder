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

    init() {
        // Configure Google Sign-In
        GoogleConfig.configure()

        do {
            // Configure SwiftData with all models
            let schema = Schema([
                User.self,
                Place.self,
                Log.self,
                Trip.self
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
            .onAppear {
                // Initialize sync engine after model context is available
                if syncEngine == nil {
                    syncEngine = SyncEngine(modelContext: modelContainer.mainContext)
                }
            }
            .onOpenURL { url in
                // Handle Google Sign-In callback URL
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .modelContainer(modelContainer)
    }
}
