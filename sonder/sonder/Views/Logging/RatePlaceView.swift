//
//  RatePlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData

/// Screen 2: Rate the selected place
struct RatePlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(SyncEngine.self) private var syncEngine

    let place: Place
    let onLogComplete: () -> Void

    @State private var selectedRating: Rating?
    @State private var showAddDetails = false
    @State private var showConfirmation = false
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            // Place header
            placeHeader
                .padding(SonderSpacing.md)

            sectionDivider

            // Rating buttons
            ScrollView {
                VStack(spacing: SonderSpacing.md) {
                    Text("How was it?")
                        .font(SonderTypography.title)
                        .foregroundColor(SonderColors.inkDark)
                        .padding(.top, SonderSpacing.md)

                    // Rating options
                    VStack(spacing: SonderSpacing.sm) {
                        RatingButton(rating: .skip, isSelected: selectedRating == .skip) {
                            selectedRating = .skip
                        }

                        RatingButton(rating: .solid, isSelected: selectedRating == .solid) {
                            selectedRating = .solid
                        }

                        RatingButton(rating: .mustSee, isSelected: selectedRating == .mustSee) {
                            selectedRating = .mustSee
                        }
                    }
                    .padding(.horizontal, SonderSpacing.md)
                }
            }

            sectionDivider

            // Action buttons
            VStack(spacing: SonderSpacing.sm) {
                // Quick save button
                Button(action: quickSave) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .font(SonderTypography.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SonderSpacing.md)
                    .background(selectedRating != nil ? SonderColors.terracotta : SonderColors.inkLight)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }
                .disabled(selectedRating == nil || isSaving)

                // Add details button
                Button(action: { showAddDetails = true }) {
                    Text("Add Details")
                        .font(SonderTypography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(SonderSpacing.md)
                        .background(SonderColors.warmGray)
                        .foregroundColor(SonderColors.inkDark)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                }
                .disabled(selectedRating == nil)
            }
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .navigationTitle("Rate Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(SonderColors.inkMuted)
            }
        }
        .navigationDestination(isPresented: $showAddDetails) {
            if let rating = selectedRating {
                AddDetailsView(place: place, rating: rating, onLogComplete: onLogComplete)
            }
        }
        .fullScreenCover(isPresented: $showConfirmation) {
            LogConfirmationView {
                showConfirmation = false
                onLogComplete()
            }
        }
    }

    // MARK: - Place Header

    private var sectionDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGray)
            .frame(height: 1)
    }

    private var placeHeader: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Place icon
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(SonderColors.terracotta)

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(2)

                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func quickSave() {
        guard let rating = selectedRating,
              let userId = authService.currentUser?.id else { return }

        isSaving = true

        // Create log with pending sync status
        let log = Log(
            userID: userId,
            placeID: place.id,
            rating: rating,
            syncStatus: .pending
        )

        modelContext.insert(log)

        do {
            try modelContext.save()

            // Haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            // Trigger immediate sync
            Task {
                await syncEngine.syncNow()
            }

            showConfirmation = true
        } catch {
            print("Failed to save log: \(error)")
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        RatePlaceView(
            place: Place(
                id: "test_place_id",
                name: "Blue Bottle Coffee",
                address: "123 Main St, San Francisco, CA",
                latitude: 37.7749,
                longitude: -122.4194
            )
        ) {
            print("Log complete")
        }
    }
}
