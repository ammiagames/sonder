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
                .padding()

            Divider()

            // Rating buttons
            ScrollView {
                VStack(spacing: 16) {
                    Text("How was it?")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top)

                    // Rating options
                    VStack(spacing: 12) {
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
                    .padding(.horizontal)
                }
            }

            Divider()

            // Action buttons
            VStack(spacing: 12) {
                // Quick save button
                Button(action: quickSave) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedRating != nil ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedRating == nil || isSaving)

                // Add details button
                Button(action: { showAddDetails = true }) {
                    Text("Add Details")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedRating == nil)
            }
            .padding()
        }
        .navigationTitle("Rate Place")
        .navigationBarTitleDisplayMode(.inline)
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

    private var placeHeader: some View {
        HStack(spacing: 12) {
            // Place icon
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.headline)
                    .lineLimit(2)

                Text(place.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
