//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "square.grid.2x2")
                }
                .tag(0)
            
            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(1)
            
            TripsView()
                .tabItem {
                    Label("Trips", systemImage: "airplane")
                }
                .tag(2)
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(3)
        }
    }
}

// MARK: - Placeholder Views

struct FeedView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Feed will show friends' recent logs here")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .navigationTitle("Feed")
        }
    }
}

struct MapView: View {
    var body: some View {
        NavigationStack {
            Text("Map view will show all logged places")
                .foregroundStyle(.secondary)
            .navigationTitle("Map")
        }
    }
}

struct TripsView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("Trips list will appear here")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Trips")
        }
    }
}

struct ProfileView: View {
    @Environment(AuthenticationService.self) private var authService
    
    var body: some View {
        NavigationStack {
            List {
                if let user = authService.currentUser {
                    Section("Account") {
                        LabeledContent("Username", value: user.username)
                        LabeledContent("User ID", value: String(user.id.prefix(8)))
                    }
                }
                
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            try? await authService.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthenticationService())
}
