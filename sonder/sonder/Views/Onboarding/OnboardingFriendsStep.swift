//
//  OnboardingFriendsStep.swift
//  sonder
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "OnboardingFriendsStep")

/// Step 4: Find and follow friends — contacts-first with username search fallback
struct OnboardingFriendsStep: View {
    let onComplete: () -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService
    @Environment(ContactsService.self) private var contactsService

    enum ViewMode { case contacts, search }

    @State private var viewMode: ViewMode = .contacts
    @State private var followedCount = 0

    // Username search state
    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false

    // Invite
    @State private var inviteContact: ContactsService.UnmatchedContact?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SonderSpacing.xs) {
                Text("Travel is better together")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)

                Text("See where your friends go and share your discoveries")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, SonderSpacing.lg)
            .padding(.horizontal, SonderSpacing.lg)

            // Content based on mode
            switch viewMode {
            case .contacts:
                contactsContent
            case .search:
                searchContent
            }

            // Bottom section
            bottomSection
        }
        .background(SonderColors.cream)
        .sheet(item: $inviteContact) { contact in
            SMSInviteView(
                phoneNumber: contact.phoneNumber,
                inviteURL: URL(string: "https://apps.apple.com/app/sonder")!
            ) {
                inviteContact = nil
            }
        }
    }

    // MARK: - Contacts Content

    @ViewBuilder
    private var contactsContent: some View {
        switch contactsService.authorizationStatus {
        case .notDetermined:
            contactsPermissionPrompt
        case .authorized:
            contactsResults
                .task {
                    guard let userID = authService.currentUser?.id else { return }
                    await contactsService.findContactsOnSonder(excludeUserID: userID)
                }
        case .denied:
            contactsDeniedView
        }
    }

    // MARK: - Permission Prompt

    private var contactsPermissionPrompt: some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()

            VStack(spacing: SonderSpacing.md) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(SonderColors.terracotta)

                Text("Find friends from your contacts")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                Text("We'll check if anyone you know is already on Sonder. Your contacts are hashed for privacy and never stored on our servers.")
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, SonderSpacing.xl)

            Button {
                Task { await contactsService.requestAccess() }
            } label: {
                Text("Find Friends from Contacts")
            }
            .buttonStyle(WarmButtonStyle(isPrimary: true))
            .padding(.horizontal, SonderSpacing.xxl)

            Button {
                viewMode = .search
            } label: {
                Text("Search by username instead")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Contacts Results

    private var contactsResults: some View {
        Group {
            if contactsService.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Finding friends...")
                        .tint(SonderColors.terracotta)
                    Spacer()
                }
            } else if contactsService.matchedUsers.isEmpty && contactsService.unmatchedContacts.isEmpty {
                noContactsState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Matched users section
                        if !contactsService.matchedUsers.isEmpty {
                            sectionHeader("Friends on Sonder", icon: "person.2.fill")

                            ForEach(contactsService.matchedUsers) { match in
                                OnboardingUserRow(
                                    user: match.user,
                                    subtitle: match.contactName,
                                    isCurrentUser: false,
                                    onFollowChanged: { isNowFollowing in
                                        followedCount += isNowFollowing ? 1 : -1
                                    }
                                )
                                .padding(.horizontal, SonderSpacing.md)
                                .padding(.vertical, SonderSpacing.xs)

                                Divider().padding(.leading, 68)
                            }
                        }

                        // Unmatched contacts section
                        if !contactsService.unmatchedContacts.isEmpty {
                            sectionHeader("Invite Friends", icon: "envelope.fill")

                            ForEach(contactsService.unmatchedContacts) { contact in
                                inviteContactRow(contact)
                                    .padding(.horizontal, SonderSpacing.md)
                                    .padding(.vertical, SonderSpacing.xs)

                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .padding(.bottom, SonderSpacing.lg)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    private var noContactsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Spacer()

            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.inkLight)

            Text("None of your contacts are on Sonder yet")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
                .multilineTextAlignment(.center)

            Button {
                viewMode = .search
            } label: {
                Text("Search by username")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.terracotta)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, SonderSpacing.lg)
    }

    // MARK: - Contacts Denied

    private var contactsDeniedView: some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.inkLight)

            Text("Contacts access is turned off")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Text("Enable contacts access in Settings to find friends on Sonder.")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SonderSpacing.xl)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
            }
            .buttonStyle(WarmButtonStyle(isPrimary: false))
            .padding(.horizontal, SonderSpacing.xxl)

            Button {
                viewMode = .search
            } label: {
                Text("Search by username instead")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Search Content

    private var searchContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(SonderSpacing.md)

            if isSearching {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .padding()
                Spacer()
            } else if searchText.isEmpty {
                VStack(spacing: SonderSpacing.md) {
                    Image(systemName: "person.2")
                        .font(.system(size: 40))
                        .foregroundStyle(SonderColors.inkLight)

                    Text("Search for friends by username")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)

                    Button {
                        viewMode = .contacts
                    } label: {
                        Text("Back to contacts")
                            .font(SonderTypography.subheadline)
                            .foregroundStyle(SonderColors.terracotta)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: SonderSpacing.md) {
                    Text("No users found matching \"\(searchText)\"")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults, id: \.id) { user in
                            OnboardingUserRow(
                                user: user,
                                subtitle: nil,
                                isCurrentUser: user.id == authService.currentUser?.id,
                                onFollowChanged: { isNowFollowing in
                                    followedCount += isNowFollowing ? 1 : -1
                                }
                            )
                            .padding(.horizontal, SonderSpacing.md)
                            .padding(.vertical, SonderSpacing.xs)

                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SonderColors.inkMuted)

            TextField("Search by username", text: $searchText)
                .font(SonderTypography.body)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onSubmit { performSearch() }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if searchText == newValue && !newValue.isEmpty {
                    performSearch()
                }
            }
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: SonderSpacing.md) {
            if followedCount > 0 {
                Text("Following \(followedCount) \(followedCount == 1 ? "person" : "people")")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.sage)
            }

            Button("Start Exploring", action: onComplete)
                .buttonStyle(WarmButtonStyle(isPrimary: true))

            Button(action: onComplete) {
                Text("Skip")
                    .font(SonderTypography.subheadline)
                    .foregroundStyle(SonderColors.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SonderSpacing.xxl)
        .padding(.bottom, SonderSpacing.xxl)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: SonderSpacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }
            Text(title)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.top, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.xs)
    }

    private func inviteContactRow(_ contact: ContactsService.UnmatchedContact) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            // Avatar placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [SonderColors.warmGray, SonderColors.warmGray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
                .overlay {
                    Text(contact.name.prefix(1).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(SonderColors.inkMuted)
                }

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(contact.name)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
            }

            Spacer()

            Button {
                inviteContact = contact
            } label: {
                    Text("Invite")
                        .font(SonderTypography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(SonderColors.terracotta)
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xxs)
                        .background(SonderColors.terracotta.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true

        searchTask?.cancel()
        searchTask = Task {
            do {
                searchResults = try await socialService.searchUsers(query: searchText)
            } catch {
                if !Task.isCancelled { searchResults = [] }
            }
            if !Task.isCancelled { isSearching = false }
        }
    }
}

// MARK: - Onboarding User Row

/// Simplified user row for onboarding — no profile navigation, just follow/unfollow
private struct OnboardingUserRow: View {
    let user: User
    let subtitle: String?
    let isCurrentUser: Bool
    let onFollowChanged: (Bool) -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var isFollowing = false
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Avatar
            if let urlString = user.avatarURL,
               let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) {
                    avatarPlaceholder
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(user.username)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                } else if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Follow button
            if !isCurrentUser {
                Button { toggleFollow() } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(SonderColors.terracotta)
                                .frame(width: 80)
                        } else if isFollowing {
                            Text("Following")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(SonderColors.inkMuted)
                                .padding(.horizontal, SonderSpacing.sm)
                                .padding(.vertical, SonderSpacing.xxs)
                                .background(SonderColors.warmGray)
                                .clipShape(Capsule())
                        } else {
                            Text("Follow")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, SonderSpacing.sm)
                                .padding(.vertical, SonderSpacing.xxs)
                                .background(SonderColors.terracotta)
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .task {
            guard let currentUserID = authService.currentUser?.id else { return }
            isFollowing = await socialService.isFollowingAsync(userID: user.id, currentUserID: currentUserID)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .frame(width: 50, height: 50)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    private func toggleFollow() {
        guard let currentUserID = authService.currentUser?.id else { return }
        isLoading = true

        Task {
            do {
                if isFollowing {
                    try await socialService.unfollowUser(userID: user.id, currentUserID: currentUserID)
                } else {
                    try await socialService.followUser(userID: user.id, currentUserID: currentUserID)
                }
                isFollowing.toggle()
                onFollowChanged(isFollowing)

                SonderHaptics.impact(.light)
            } catch {
                logger.error("Follow error: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}
