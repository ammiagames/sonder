//
//  TripCollaboratorsView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "TripCollaboratorsView")

/// View for managing trip collaborators
struct TripCollaboratorsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(SocialService.self) private var socialService

    let trip: Trip

    @State private var collaborators: [User] = []
    @State private var pendingInvitees: [User] = []
    @State private var owner: User?
    @State private var isLoading = true
    @State private var showInviteSheet = false
    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var searchDebounceTask: Task<Void, Never>?

    private var isOwner: Bool {
        trip.createdBy == authService.currentUser?.id
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    collaboratorsList
                }
            }
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showInviteSheet = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                inviteSheet
            }
            .task {
                await loadCollaborators()
            }
        }
    }

    // MARK: - Collaborators List

    private var collaboratorsList: some View {
        List {
            // Owner section
            Section("Owner") {
                if let owner = owner {
                    CollaboratorRow(user: owner, isOwner: true, canRemove: false) { }
                }
            }

            // Pending invitations section
            if !pendingInvitees.isEmpty && isOwner {
                Section("Pending Invitations") {
                    ForEach(pendingInvitees, id: \.id) { user in
                        HStack(spacing: 12) {
                            // Avatar
                            pendingAvatarView(for: user)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(SonderTypography.subheadline)
                                    .fontWeight(.medium)

                                Text("Invitation sent")
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.ochre)
                            }

                            Spacer()

                            Image(systemName: "clock")
                                .foregroundStyle(SonderColors.ochre)
                        }
                    }
                }
            }

            // Collaborators section
            if !collaborators.isEmpty {
                Section("Collaborators") {
                    ForEach(collaborators, id: \.id) { user in
                        CollaboratorRow(
                            user: user,
                            isOwner: false,
                            canRemove: isOwner
                        ) {
                            removeCollaborator(user)
                        }
                    }
                }
            }

            // Leave trip (for collaborators)
            if !isOwner {
                Section {
                    Button(role: .destructive) {
                        leaveTrip()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Leave Trip")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SonderColors.cream)
    }

    // MARK: - Invite Sheet

    private var inviteSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SonderColors.inkMuted)

                    TextField("Search by username", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onSubmit {
                            searchUsers()
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SonderColors.inkMuted)
                        }
                    }
                }
                .padding(SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .padding()
                .onChange(of: searchText) { _, newValue in
                    // Debounced search
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        if searchText == newValue && !newValue.isEmpty {
                            searchUsers()
                        }
                    }
                }

                // Results
                if isSearching {
                    ProgressView()
                        .padding()
                    Spacer()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    VStack(spacing: SonderSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(SonderColors.inkLight)
                        Text("No Results")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)
                        Text("No users found")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults, id: \.id) { user in
                        InviteUserRow(
                            user: user,
                            isAlreadyAdded: isAlreadyCollaborator(user),
                            isPending: isAlreadyInvited(user)
                        ) {
                            inviteUser(user)
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle("Invite Collaborator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showInviteSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadCollaborators() async {
        isLoading = true

        do {
            // Load owner
            owner = try await socialService.getUser(id: trip.createdBy)

            // Load collaborators
            var users: [User] = []
            for collaboratorID in trip.collaboratorIDs {
                if let user = try await socialService.getUser(id: collaboratorID) {
                    users.append(user)
                }
            }
            collaborators = users

            // Load pending invitations for this trip
            let pendingInvitations = try await tripService.fetchPendingInvitationsForTrip(trip.id)
            var pendingUsers: [User] = []
            for invitation in pendingInvitations {
                if let user = try await socialService.getUser(id: invitation.inviteeID) {
                    pendingUsers.append(user)
                }
            }
            pendingInvitees = pendingUsers
        } catch {
            logger.error("Error loading collaborators: \(error.localizedDescription)")
        }

        isLoading = false
    }

    @ViewBuilder
    private func pendingAvatarView(for user: User) -> some View {
        if let urlString = user.avatarURL,
           let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) {
                Circle()
                    .fill(SonderColors.ochre.opacity(0.2))
                    .overlay {
                        Text(user.username.prefix(1).uppercased())
                            .font(SonderTypography.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(SonderColors.ochre)
                    }
            }
        } else {
            Circle()
                .fill(SonderColors.ochre.opacity(0.2))
                .overlay {
                    Text(user.username.prefix(1).uppercased())
                        .font(SonderTypography.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(SonderColors.ochre)
                }
        }
    }

    private func searchUsers() {
        guard !searchText.isEmpty else { return }

        isSearching = true

        Task {
            do {
                let results = try await socialService.searchUsers(query: searchText)
                // Filter out owner and existing collaborators
                searchResults = results.filter { user in
                    user.id != trip.createdBy &&
                    !trip.collaboratorIDs.contains(user.id) &&
                    user.id != authService.currentUser?.id
                }
            } catch {
                logger.error("Search error: \(error.localizedDescription)")
            }
            isSearching = false
        }
    }

    private func isAlreadyCollaborator(_ user: User) -> Bool {
        trip.collaboratorIDs.contains(user.id) || user.id == trip.createdBy
    }

    private func isAlreadyInvited(_ user: User) -> Bool {
        pendingInvitees.contains { $0.id == user.id }
    }

    private func inviteUser(_ user: User) {
        guard let inviterID = authService.currentUser?.id else { return }

        Task {
            do {
                try await tripService.sendInvitation(to: user.id, for: trip, from: inviterID)
                pendingInvitees.append(user)
                searchResults.removeAll { $0.id == user.id }

                SonderHaptics.notification(.success)
            } catch {
                logger.error("Error inviting user: \(error.localizedDescription)")
            }
        }
    }

    private func removeCollaborator(_ user: User) {
        Task {
            do {
                try await tripService.removeCollaborator(userID: user.id, from: trip)
                collaborators.removeAll { $0.id == user.id }

                SonderHaptics.notification(.success)
            } catch {
                logger.error("Error removing collaborator: \(error.localizedDescription)")
            }
        }
    }

    private func leaveTrip() {
        guard let userID = authService.currentUser?.id else { return }

        Task {
            do {
                try await tripService.leaveTrip(trip, userID: userID)
                dismiss()
            } catch {
                logger.error("Error leaving trip: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Collaborator Row

struct CollaboratorRow: View {
    let user: User
    let isOwner: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)

                if isOwner {
                    Text("Owner")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.terracotta)
                }
            }

            Spacer()

            // Remove button
            if canRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = user.avatarURL,
           let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) {
                avatarPlaceholder
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(SonderTypography.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(SonderColors.terracotta)
            }
    }
}

// MARK: - Invite User Row

struct InviteUserRow: View {
    let user: User
    let isAlreadyAdded: Bool
    var isPending: Bool = false
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            // Username
            Text(user.username)
                .font(SonderTypography.subheadline)
                .fontWeight(.medium)

            Spacer()

            // Invite button
            if isAlreadyAdded {
                Text("Added")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            } else if isPending {
                Text("Invited")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.ochre)
            } else {
                Button {
                    onInvite()
                } label: {
                    Text("Invite")
                        .font(SonderTypography.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.terracotta)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let urlString = user.avatarURL,
           let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) {
                avatarPlaceholder
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(SonderTypography.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(SonderColors.terracotta)
            }
    }
}

#Preview {
    TripCollaboratorsView(
        trip: Trip(name: "Test Trip", createdBy: "user1")
    )
}
