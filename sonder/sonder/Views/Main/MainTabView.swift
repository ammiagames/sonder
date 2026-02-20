//
//  MainTabView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "MainTabView")

struct MainTabView: View {
    var initialTab: Int = 0
    @AppStorage("sonder.lastSelectedTab") private var selectedTab = 0
    @State private var showLogFlow = false
    @State private var exploreFocusMyPlaces = false
    @State private var exploreHasSelection = false
    @State private var pendingPinDrop: CLLocationCoordinate2D?
    @State private var pendingLogCoord: CLLocationCoordinate2D?

    // Pop-to-root triggers: changing UUID causes .onChange to fire in child views
    @State private var feedPopTrigger = UUID()
    @State private var journalPopTrigger = UUID()
    @State private var profilePopTrigger = UUID()

    @State private var didSetInitialTab = false
    @State private var hideTabBarGradient = false

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(popToRoot: feedPopTrigger)
                .environment(\.isTabVisible, selectedTab == 0)
                .tag(0)

            ExploreMapView(focusMyPlaces: $exploreFocusMyPlaces, hasSelection: $exploreHasSelection, pendingPinDrop: $pendingPinDrop)
                .environment(\.isTabVisible, selectedTab == 1)
                .tag(1)

            JournalContainerView(popToRoot: journalPopTrigger)
                .environment(\.isTabVisible, selectedTab == 2)
                .tag(2)

            ProfileView(selectedTab: $selectedTab, exploreFocusMyPlaces: $exploreFocusMyPlaces, popToRoot: profilePopTrigger)
                .environment(\.isTabVisible, selectedTab == 3)
                .tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if !didSetInitialTab && initialTab != 0 {
                didSetInitialTab = true
                selectedTab = initialTab
            }
        }
        .toolbarColorScheme(.light, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            SonderTabBar(
                selectedTab: $selectedTab,
                onLogTap: { showLogFlow = true },
                hideGradient: hideTabBarGradient,
                onSameTabTap: { tab in
                    switch tab {
                    case 0: feedPopTrigger = UUID()
                    case 2: journalPopTrigger = UUID()
                    case 3: profilePopTrigger = UUID()
                    default: break
                    }
                }
            )
        }
        .overlay(alignment: .bottom) {
            PendingSyncOverlay()
                .padding(.bottom, 60)
        }
        .overlay(alignment: .top) {
            PhotoUploadBannerOverlay()
        }
        .onPreferenceChange(HideTabBarGradientKey.self) { hideTabBarGradient = $0 }
        .fullScreenCover(isPresented: $showLogFlow, onDismiss: {
            guard let coord = pendingLogCoord else { return }
            pendingLogCoord = nil
            pendingPinDrop = coord
        }) {
            SearchPlaceView { coord in
                pendingLogCoord = coord
                selectedTab = 1
                showLogFlow = false
            }
        }
    }
}

// MARK: - Tab Bar Gradient Preference

/// Child views set this to `true` to hide the tab bar's top gradient
/// (e.g. when a floating save button would otherwise appear behind it).
struct HideTabBarGradientKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Custom Tab Bar

struct SonderTabBar: View {
    @Binding var selectedTab: Int
    let onLogTap: () -> Void
    var hideGradient: Bool = false
    var onSameTabTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "bubble.left.and.bubble.right", label: "Feed", tag: 0)
            tabButton(icon: "safari", label: "Explore", tag: 1)
            logButton
            tabButton(icon: "book.closed", label: "Journal", tag: 2)
            tabButton(icon: "person", label: "Profile", tag: 3)
        }
        .padding(.top, SonderSpacing.xxs)
        .padding(.bottom, SonderSpacing.xxs)
        .offset(y: 16)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(SonderColors.cream.opacity(0.7))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Gradient fade above the bar — content dissolves into it
        .overlay(alignment: .top) {
            if !hideGradient {
                LinearGradient(
                    colors: [SonderColors.cream.opacity(0), SonderColors.cream.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)
                .offset(y: -24)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Tab Button

    private func tabButton(icon: String, label: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag

        return Button {
            if selectedTab == tag {
                onSameTabTap?(tag)
            } else {
                selectedTab = tag
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: SonderSpacing.xxs) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(SonderColors.terracotta.opacity(0.15))
                            .frame(width: 52, height: 30)
                    }

                    Image(systemName: icon)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 20))
                        .frame(width: 52, height: 30)
                }

                Text(label)
                    .font(.system(size: 10, design: .rounded))
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? SonderColors.terracotta : SonderColors.inkLight)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Elevated Log Button

    private var logButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLogTap()
        } label: {
            VStack(spacing: SonderSpacing.xxs) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SonderColors.terracotta, SonderColors.terracotta.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, x: 0, y: 3)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Log")
                    .font(.system(size: 10, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.terracotta)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -16)
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.9))
    }
}

// MARK: - Pending Sync Badge Overlay

/// Isolated sub-view so SyncEngine observation doesn't re-render MainTabView.
struct PendingSyncOverlay: View {
    @Environment(SyncEngine.self) private var syncEngine
    @State private var showSyncAlert = false

    var body: some View {
        Group {
            if syncEngine.pendingCount > 0 {
                HStack {
                    Spacer()
                    Button { showSyncAlert = true } label: {
                        PendingSyncBadge(count: syncEngine.pendingCount)
                    }
                    .buttonStyle(.plain)
                        .padding(.trailing, 16)
                }
                .padding(.bottom, 56)
            }
        }
        .alert("\(syncEngine.pendingCount) log\(syncEngine.pendingCount == 1 ? "" : "s") stuck", isPresented: $showSyncAlert) {
            Button("Retry Sync") {
                Task { await syncEngine.forceSyncNow() }
            }
            Button("Dismiss", role: .destructive) {
                syncEngine.dismissStuckLogs()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("These logs failed to sync to the server. You can retry or dismiss them to clear the badge.")
        }
    }
}

// MARK: - Photo Upload Banner Overlay

/// Isolated sub-view so PhotoService observation doesn't re-render MainTabView.
struct PhotoUploadBannerOverlay: View {
    @Environment(PhotoService.self) private var photoService

    var body: some View {
        Group {
            if photoService.hasActiveUploads {
                PhotoUploadBanner(
                    completed: photoService.totalPhotosInFlight - photoService.totalPendingPhotos,
                    total: photoService.totalPhotosInFlight,
                    progress: photoService.overallProgress
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: photoService.hasActiveUploads)
    }
}

// MARK: - Photo Upload Banner

struct PhotoUploadBanner: View {
    let completed: Int
    let total: Int
    let progress: Double

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(SonderColors.terracotta.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(SonderColors.terracotta, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SonderColors.terracotta)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Uploading photos...")
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
                Text("\(completed) of \(total)")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.sm)
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, SonderSpacing.md)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(ProximityNotificationService.self) private var proximityService
    @Environment(\.modelContext) private var modelContext

    @State private var showSignOutAlert = false
    @State private var showClearCacheAlert = false
    @State private var showEditEmailAlert = false
    @State private var editedEmail = ""
    @State private var proximityAlertsEnabled = false
    @State private var signOutError: String?

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section {
                    if let user = authService.currentUser {
                        settingsRow(label: "Username", value: user.username)

                        Button {
                            editedEmail = user.email ?? ""
                            showEditEmailAlert = true
                        } label: {
                            settingsRow(label: "Email", value: user.email ?? "Not set")
                        }
                    }
                } header: {
                    settingsSectionHeader("Account")
                }
                .listRowBackground(SonderColors.warmGray)

                // Notifications section
                Section {
                    Toggle(isOn: $proximityAlertsEnabled) {
                        Label {
                            Text("Nearby Place Alerts")
                                .font(SonderTypography.body)
                                .foregroundStyle(SonderColors.inkDark)
                        } icon: {
                            Image(systemName: "location.fill")
                                .foregroundStyle(SonderColors.terracotta)
                        }
                    }
                    .onChange(of: proximityAlertsEnabled) { _, newValue in
                        Task {
                            if newValue {
                                await proximityService.startMonitoring()
                            } else {
                                proximityService.stopMonitoring()
                            }
                        }
                    }
                } header: {
                    settingsSectionHeader("Notifications")
                } footer: {
                    Text("Get notified when you're near a place on your Want to Go list")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)
                }
                .listRowBackground(SonderColors.warmGray)

                // Privacy section
                Section {
                    NavigationLink {
                        Text("Privacy Policy")
                            .navigationTitle("Privacy Policy")
                    } label: {
                        Label {
                            Text("Privacy Policy")
                                .font(SonderTypography.body)
                                .foregroundStyle(SonderColors.inkDark)
                        } icon: {
                            Image(systemName: "hand.raised")
                                .foregroundStyle(SonderColors.terracotta)
                        }
                    }

                    NavigationLink {
                        Text("Terms of Service")
                            .navigationTitle("Terms of Service")
                    } label: {
                        Label {
                            Text("Terms of Service")
                                .font(SonderTypography.body)
                                .foregroundStyle(SonderColors.inkDark)
                        } icon: {
                            Image(systemName: "doc.text")
                                .foregroundStyle(SonderColors.terracotta)
                        }
                    }
                } header: {
                    settingsSectionHeader("Privacy")
                }
                .listRowBackground(SonderColors.warmGray)

                // Data section
                Section {
                    Button {
                        showClearCacheAlert = true
                    } label: {
                        Label {
                            Text("Clear Cache")
                                .font(SonderTypography.body)
                                .foregroundStyle(SonderColors.terracotta)
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(SonderColors.terracotta)
                        }
                    }
                } header: {
                    settingsSectionHeader("Data")
                }
                .listRowBackground(SonderColors.warmGray)

                // About section
                Section {
                    settingsRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    settingsRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                } header: {
                    settingsSectionHeader("About")
                }
                .listRowBackground(SonderColors.warmGray)

                // Sign out section
                Section {
                    Button {
                        showSignOutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(SonderTypography.headline)
                                .foregroundStyle(SonderColors.dustyRose)
                            Spacer()
                        }
                    }
                }
                .listRowBackground(SonderColors.warmGray)
            }
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.colorScheme, .light)
            .tint(SonderColors.terracotta)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    Task {
                        do {
                            try await authService.signOut()
                            dismiss()
                        } catch {
                            signOutError = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Sign Out Failed", isPresented: Binding(
                get: { signOutError != nil },
                set: { if !$0 { signOutError = nil } }
            )) {
                Button("OK", role: .cancel) { signOutError = nil }
            } message: {
                Text(signOutError ?? "An unknown error occurred.")
            }
            .alert("Clear Cache", isPresented: $showClearCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("This will clear cached place data. Your logs will not be affected.")
            }
            .alert("Edit Email", isPresented: $showEditEmailAlert) {
                TextField("Email", text: $editedEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    saveEmail()
                }
            } message: {
                Text("Enter your email address")
            }
            .onAppear {
                proximityAlertsEnabled = proximityService.isMonitoring
            }
        }
    }

    // MARK: - Settings Helpers

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SonderTypography.caption)
            .foregroundStyle(SonderColors.terracotta)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func settingsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
            Spacer()
            Text(value)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
    }

    private func saveEmail() {
        guard let user = authService.currentUser else { return }
        let trimmedEmail = editedEmail.trimmingCharacters(in: .whitespaces)

        user.email = trimmedEmail.isEmpty ? nil : trimmedEmail
        user.updatedAt = Date()

        try? modelContext.save()

        // Sync the update
        Task {
            await syncEngine.syncNow()
        }
    }

    private func clearCache() {
        // Clear shared image caches (memory + disk URLCache).
        ImageDownsampler.clearCaches()

        // Clear recent searches
        do {
            let descriptor = FetchDescriptor<RecentSearch>()
            let searches = try modelContext.fetch(descriptor)
            for search in searches {
                modelContext.delete(search)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to clear cache: \(error.localizedDescription)")
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthenticationService())
}
