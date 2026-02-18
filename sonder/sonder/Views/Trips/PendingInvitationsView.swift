//
//  PendingInvitationsView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "PendingInvitationsView")

/// View showing pending trip invitations for the current user
struct PendingInvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(SocialService.self) private var socialService

    @State private var invitations: [TripInvitationWithDetails] = []
    @State private var isLoading = true
    @State private var processingIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if invitations.isEmpty {
                    VStack(spacing: SonderSpacing.md) {
                        Image(systemName: "envelope.open")
                            .font(.system(size: 48))
                            .foregroundStyle(SonderColors.inkLight)
                        Text("No Invitations")
                            .font(SonderTypography.title)
                            .foregroundStyle(SonderColors.inkDark)
                        Text("You don't have any pending trip invitations")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    invitationsList
                }
            }
            .navigationTitle("Trip Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadInvitations()
            }
        }
    }

    // MARK: - Invitations List

    private var invitationsList: some View {
        List {
            ForEach(invitations) { item in
                InvitationCard(
                    item: item,
                    isProcessing: processingIDs.contains(item.id),
                    onAccept: { acceptInvitation(item) },
                    onDecline: { declineInvitation(item) }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func loadInvitations() async {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true
        do {
            invitations = try await tripService.fetchPendingInvitationsWithDetails(
                for: userID,
                socialService: socialService
            )
        } catch {
            logger.error("Error loading invitations: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func acceptInvitation(_ item: TripInvitationWithDetails) {
        processingIDs.insert(item.id)

        Task {
            do {
                try await tripService.acceptInvitation(item.invitation)

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Remove from list with animation
                withAnimation {
                    invitations.removeAll { $0.id == item.id }
                }
            } catch {
                logger.error("Error accepting invitation: \(error.localizedDescription)")
            }
            processingIDs.remove(item.id)
        }
    }

    private func declineInvitation(_ item: TripInvitationWithDetails) {
        processingIDs.insert(item.id)

        Task {
            do {
                try await tripService.declineInvitation(item.invitation)

                // Remove from list with animation
                withAnimation {
                    invitations.removeAll { $0.id == item.id }
                }
            } catch {
                logger.error("Error declining invitation: \(error.localizedDescription)")
            }
            processingIDs.remove(item.id)
        }
    }
}

// MARK: - Invitation Card

struct InvitationCard: View {
    let item: TripInvitationWithDetails
    let isProcessing: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Trip info
            HStack(spacing: 12) {
                // Trip cover or placeholder
                tripCover
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.trip.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    // Inviter info
                    HStack(spacing: 4) {
                        Text("from")
                            .foregroundStyle(SonderColors.inkMuted)
                        Text("@\(item.inviter.username)")
                            .foregroundStyle(SonderColors.terracotta)
                    }
                    .font(SonderTypography.subheadline)

                    // Date
                    Text(item.invitation.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkLight)
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: SonderSpacing.sm) {
                Button {
                    onDecline()
                } label: {
                    Text("Decline")
                        .font(SonderTypography.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SonderColors.warmGray)
                        .foregroundStyle(SonderColors.inkDark)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Button {
                    onAccept()
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Join Trip")
                            .font(SonderTypography.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SonderColors.terracotta)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    @ViewBuilder
    private var tripCover: some View {
        if let urlString = item.trip.coverPhotoURL,
           let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                tripPlaceholder
            }
        } else {
            tripPlaceholder
        }
    }

    private var tripPlaceholder: some View {
        TripCoverPlaceholderView(seedKey: item.trip.id)
    }
}

#Preview {
    PendingInvitationsView()
}
