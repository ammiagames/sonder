//
//  UserSearchView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "UserSearchView")

/// Search for users by username, with a Contacts tab for contact-based discovery
struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService
    @Environment(ContactsService.self) private var contactsService

    enum SearchTab: String, CaseIterable {
        case username = "Username"
        case contacts = "Contacts"
    }

    @State private var selectedTab: SearchTab = .username
    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var selectedUserID: String?
    @State private var inviteContact: ContactsService.UnmatchedContact?
    @State private var contactsLoaded = false
    @State private var contactsSearchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab switcher
                tabSwitcher
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.top, SonderSpacing.sm)

                // Tab content
                switch selectedTab {
                case .username:
                    searchTabContent
                case .contacts:
                    contactsTabContent
                }
            }
            .background(SonderColors.cream)
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }
            }
            .navigationDestination(item: $selectedUserID) { userID in
                OtherUserProfileView(userID: userID)
            }
            .sheet(item: $inviteContact) { contact in
                SMSInviteView(
                    phoneNumber: contact.phoneNumber,
                    inviteURL: URL(string: "https://apps.apple.com/app/sonder")!
                ) {
                    inviteContact = nil
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .contacts && !contactsLoaded {
                    loadContacts()
                }
                if newTab == .username {
                    contactsSearchText = ""
                }
            }
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: SonderSpacing.xs) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(SonderTypography.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? .white : SonderColors.inkMuted)
                        .padding(.horizontal, SonderSpacing.md)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(selectedTab == tab ? SonderColors.terracotta : SonderColors.warmGray)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Search Tab

    private var searchTabContent: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(SonderSpacing.md)

            // Results
            if isSearching {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .padding()
                Spacer()
            } else if searchText.isEmpty {
                emptySearchState
            } else if searchResults.isEmpty {
                noResultsState
            } else {
                resultsList
            }
        }
    }

    // MARK: - Contacts Tab

    private var contactsTabContent: some View {
        Group {
            switch contactsService.authorizationStatus {
            case .notDetermined:
                contactsPermissionPrompt
            case .authorized:
                if contactsService.isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Finding friends...")
                            .tint(SonderColors.terracotta)
                        Spacer()
                    }
                } else if contactsService.matchedUsers.isEmpty && contactsService.unmatchedContacts.isEmpty {
                    VStack(spacing: SonderSpacing.md) {
                        Spacer()
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(SonderColors.inkLight)
                        Text("None of your contacts are on Sonder yet")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, SonderSpacing.lg)
                } else {
                    contactsList
                }
            case .denied:
                contactsDeniedState
            }
        }
    }

    private var contactsPermissionPrompt: some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()

            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.terracotta)

            Text("Find friends from your contacts")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Text("We'll check if anyone you know is already on Sonder.")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SonderSpacing.xl)

            Button {
                Task {
                    let granted = await contactsService.requestAccess()
                    if granted { loadContacts() }
                }
            } label: {
                Text("Allow Access")
            }
            .buttonStyle(WarmButtonStyle(isPrimary: true))
            .padding(.horizontal, SonderSpacing.xxl)

            Spacer()
        }
    }

    private var contactsDeniedState: some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.inkLight)

            Text("Contacts access is turned off")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Text("Enable contacts access in Settings to find friends.")
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

            Spacer()
        }
    }

    private var filteredMatchedUsers: [ContactsService.ContactMatch] {
        guard !contactsSearchText.isEmpty else { return contactsService.matchedUsers }
        return contactsService.matchedUsers.filter { match in
            match.contactName.localizedCaseInsensitiveContains(contactsSearchText) ||
            match.user.username.localizedCaseInsensitiveContains(contactsSearchText)
        }
    }

    private var filteredUnmatchedContacts: [ContactsService.UnmatchedContact] {
        guard !contactsSearchText.isEmpty else { return contactsService.unmatchedContacts }
        return contactsService.unmatchedContacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(contactsSearchText)
        }
    }

    private var contactsSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SonderColors.inkMuted)

            TextField("Search contacts", text: $contactsSearchText)
                .font(SonderTypography.body)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            if !contactsSearchText.isEmpty {
                Button {
                    contactsSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    private var contactsList: some View {
        VStack(spacing: 0) {
            contactsSearchBar
                .padding(.horizontal, SonderSpacing.md)
                .padding(.top, SonderSpacing.md)
                .padding(.bottom, SonderSpacing.xs)

            if filteredMatchedUsers.isEmpty && filteredUnmatchedContacts.isEmpty && !contactsSearchText.isEmpty {
                VStack(spacing: SonderSpacing.md) {
                    Spacer()
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(SonderColors.inkLight)
                    Text("No contacts matching \"\(contactsSearchText)\"")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, SonderSpacing.lg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredMatchedUsers) { match in
                            UserSearchRow(
                                user: match.user,
                                isCurrentUser: match.user.id == authService.currentUser?.id,
                                subtitle: match.contactName
                            ) {
                                selectedUserID = match.user.id
                            }
                            .padding(.horizontal, SonderSpacing.md)
                            .padding(.vertical, SonderSpacing.xs)

                            Divider().padding(.leading, 68)
                        }

                        ForEach(filteredUnmatchedContacts) { contact in
                            InviteContactRow(contact: contact) {
                                inviteContact = contact
                            }
                            .padding(.horizontal, SonderSpacing.md)
                            .padding(.vertical, SonderSpacing.xs)

                            Divider().padding(.leading, 68)
                        }
                    }
                    .padding(.bottom, 80)
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
                .onSubmit {
                    performSearch()
                }

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
            // Debounced search
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if searchText == newValue && !newValue.isEmpty {
                    performSearch()
                }
            }
        }
    }

    // MARK: - States

    private var emptySearchState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.inkLight)

            Text("Search Users")
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            Text("Enter a username to find friends")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.inkLight)

            Text("No Results")
                .font(SonderTypography.title)
                .foregroundStyle(SonderColors.inkDark)

            Text("No users found matching \"\(searchText)\"")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(searchResults, id: \.id) { user in
                UserSearchRow(
                    user: user,
                    isCurrentUser: user.id == authService.currentUser?.id
                ) {
                    selectedUserID = user.id
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .background(SonderColors.cream)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true

        Task {
            do {
                searchResults = try await socialService.searchUsers(query: searchText)
            } catch {
                logger.error("Search error: \(error.localizedDescription)")
                searchResults = []
            }
            isSearching = false
        }
    }

    private func loadContacts() {
        guard let userID = authService.currentUser?.id else { return }
        contactsLoaded = true
        Task {
            await contactsService.findContactsOnSonder(excludeUserID: userID)
        }
    }
}

// MARK: - User Search Row

struct UserSearchRow: View {
    let user: User
    let isCurrentUser: Bool
    var subtitle: String? = nil
    let onTap: () -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SocialService.self) private var socialService

    @State private var isFollowing = false
    @State private var isLoading = false

    var body: some View {
        Button(action: onTap) {
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

                // User info
                VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                    Text(user.username)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    } else {
                        Text("Exploring since \(user.createdAt.formatted(.dateTime.month(.wide).year()))")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }

                Spacer()

                // Follow button (not shown for current user)
                if !isCurrentUser {
                    followButton
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            await checkFollowStatus()
        }
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
            .frame(width: 50, height: 50)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
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

    private func checkFollowStatus() async {
        guard let currentUserID = authService.currentUser?.id else { return }
        isFollowing = await socialService.isFollowingAsync(userID: user.id, currentUserID: currentUserID)
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

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } catch {
                logger.error("Follow error: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

// MARK: - Invite Contact Row

struct InviteContactRow: View {
    let contact: ContactsService.UnmatchedContact
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
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

            Text(contact.name)
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Spacer()

            if SMSInviteView.canSendText {
                Button(action: onInvite) {
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
    }
}

#Preview {
    UserSearchView()
        .environment(AuthenticationService())
}
