//
//  RatePlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation

/// Screen 2: Rate the selected place
struct RatePlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(WantToGoService.self) private var wantToGoService

    let place: Place
    let onLogComplete: (CLLocationCoordinate2D) -> Void

    @State private var selectedRating: Rating?
    @State private var selectedTrip: Trip?
    @State private var showAddDetails = false
    @State private var showConfirmation = false
    @State private var showNewTripSheet = false
    @State private var newTripName = ""
    @State private var newTripCoverImage: UIImage?
    @State private var isSaving = false
    @State private var coverNudgeTrip: Trip?
    @State private var showCoverImagePicker = false

    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]

    /// Trips the user can add logs to (owned + collaborating),
    /// sorted by most recently used (latest log added), then by creation date.
    private var availableTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        let accessible = allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
        // Build a map of trip ID → latest log date
        let latestLogByTrip: [String: Date] = allLogs.reduce(into: [:]) { map, log in
            guard let tripID = log.tripID else { return }
            if map[tripID] == nil || log.createdAt > map[tripID]! {
                map[tripID] = log.createdAt
            }
        }
        return accessible.sorted { a, b in
            let aDate = latestLogByTrip[a.id] ?? a.createdAt
            let bDate = latestLogByTrip[b.id] ?? b.createdAt
            return aDate > bDate
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Place header
                placeHeader
                    .padding(SonderSpacing.md)

                sectionDivider

                // Rating section
                VStack(spacing: SonderSpacing.lg) {
                    Text("How was it?")
                        .font(SonderTypography.title)
                        .foregroundColor(SonderColors.inkDark)
                        .padding(.top, SonderSpacing.lg)

                    // Rating circles
                    HStack(spacing: SonderSpacing.lg) {
                        ForEach(Rating.allCases, id: \.self) { rating in
                            ratingCircle(rating)
                        }
                    }
                    .padding(.horizontal, SonderSpacing.md)
                }

                // Trip section
                tripSection
                    .padding(.top, SonderSpacing.xl)
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
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
            .background(SonderColors.cream)
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
                AddDetailsView(
                    place: place,
                    rating: rating,
                    initialTrip: selectedTrip,
                    onLogComplete: onLogComplete
                )
            }
        }
        .fullScreenCover(isPresented: $showConfirmation) {
            LogConfirmationView(
                onDismiss: {
                    showConfirmation = false
                    onLogComplete(place.coordinate)
                },
                tripName: coverNudgeTrip?.name,
                onAddCover: {
                    showConfirmation = false
                    showCoverImagePicker = true
                }
            )
        }
        .sheet(isPresented: $showNewTripSheet) {
            newTripSheet
        }
        .sheet(isPresented: $showCoverImagePicker) {
            EditableImagePicker { image in
                showCoverImagePicker = false
                if let trip = coverNudgeTrip, let userId = authService.currentUser?.id {
                    Task {
                        if let url = await photoService.uploadPhoto(image, for: userId) {
                            trip.coverPhotoURL = url
                            trip.updatedAt = Date()
                            try? modelContext.save()
                        }
                    }
                }
                coverNudgeTrip = nil
                onLogComplete(place.coordinate)
            } onCancel: {
                showCoverImagePicker = false
                coverNudgeTrip = nil
                onLogComplete(place.coordinate)
            }
            .ignoresSafeArea()
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

    // MARK: - Rating Circle

    private func ratingCircle(_ rating: Rating) -> some View {
        let isSelected = selectedRating == rating
        let color: Color = switch rating {
        case .skip: SonderColors.ratingSkip
        case .solid: SonderColors.ratingSolid
        case .mustSee: SonderColors.ratingMustSee
        }

        return VStack(spacing: SonderSpacing.xs) {
            Text(rating.emoji)
                .font(.system(size: 32))
                .frame(width: 72, height: 72)
                .background(isSelected ? color.opacity(0.2) : SonderColors.warmGray)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isSelected ? color : .clear, lineWidth: 2)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedRating)

            Text(rating.displayName)
                .font(SonderTypography.caption)
                .fontWeight(.medium)
                .foregroundColor(SonderColors.inkDark)
        }
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedRating = rating
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Add to a trip?")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)
                .padding(.horizontal, SonderSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    // Most recently used trips
                    ForEach(availableTrips.prefix(3), id: \.id) { trip in
                        tripChip(trip)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // New trip button
                    Button {
                        newTripName = ""
                        newTripCoverImage = nil
                        showNewTripSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("New Trip")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.warmGray)
                        .foregroundColor(SonderColors.inkDark)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SonderSpacing.md)
            }

            // Selected trip indicator
            if let trip = selectedTrip {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(SonderColors.terracotta)
                    Text("Saving to \(trip.name)")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
                .padding(.horizontal, SonderSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: allTrips.count)
        .animation(.easeInOut(duration: 0.25), value: selectedTrip?.id)
    }

    private func tripChip(_ trip: Trip) -> some View {
        let isSelected = selectedTrip?.id == trip.id

        return HStack(spacing: 4) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 10))
            Text(trip.name)
                .font(SonderTypography.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(isSelected ? SonderColors.terracotta : SonderColors.warmGray)
        .foregroundColor(isSelected ? .white : SonderColors.inkDark)
        .clipShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTrip = isSelected ? nil : trip
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - New Trip Sheet

    @ViewBuilder
    private var newTripSheet: some View {
        NewTripSheetView(
            tripName: $newTripName,
            coverImage: $newTripCoverImage,
            onCancel: { showNewTripSheet = false },
            onCreate: {
                createNewTrip()
                showNewTripSheet = false
            }
        )
    }

    // MARK: - Trip Creation

    private func createNewTrip() {
        guard let userId = authService.currentUser?.id else { return }
        let trimmedName = newTripName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let trip = Trip(
            name: trimmedName,
            createdBy: userId
        )

        // Use Google Places photo as immediate fallback if no user photo picked
        if newTripCoverImage == nil, let ref = place.photoReference,
           let url = GooglePlacesService.photoURL(for: ref) {
            trip.coverPhotoURL = url.absoluteString
        }

        modelContext.insert(trip)
        try? modelContext.save()

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTrip = trip
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Upload user-picked cover photo in background
        if let coverImage = newTripCoverImage {
            Task {
                if let url = await photoService.uploadPhoto(coverImage, for: userId) {
                    trip.coverPhotoURL = url
                    trip.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Actions

    private func quickSave() {
        guard let rating = selectedRating,
              let userId = authService.currentUser?.id else { return }

        isSaving = true

        let log = Log(
            userID: userId,
            placeID: place.id,
            rating: rating,
            tripID: selectedTrip?.id,
            syncStatus: .pending
        )

        modelContext.insert(log)

        do {
            try modelContext.save()

            // Auto-assign Google Places photo if trip has no cover
            if let trip = selectedTrip, trip.coverPhotoURL == nil,
               let ref = place.photoReference,
               let url = GooglePlacesService.photoURL(for: ref) {
                trip.coverPhotoURL = url.absoluteString
                trip.updatedAt = Date()
                try? modelContext.save()
                // Show nudge since it's only a Google photo placeholder
                coverNudgeTrip = trip
            }

            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)

            Task {
                // Remove from Want to Go if bookmarked
                await wantToGoService.removeBookmarkIfLoggedPlace(placeID: place.id, userID: userId)
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
        ) { _ in
            print("Log complete")
        }
    }
}
