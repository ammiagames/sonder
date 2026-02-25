//
//  RatePlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "RatePlaceView")

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
    @State private var newLogForDetails: Log?
    @State private var showNewTripSheet = false
    @State private var newTripName = ""
    @State private var newTripCoverImage: UIImage?
    @State private var visitedAt = Date()
    @State private var isSaving = false
    @State private var coverNudgeTrip: Trip?
    @State private var showCoverImagePicker = false
    @State private var tripSaveError: String?

    @State private var userTrips: [Trip] = []
    @State private var userLogs: [Log] = []
    @State private var cachedAvailableTrips: [Trip] = []

    private var availableTrips: [Trip] { cachedAvailableTrips }

    private func refreshData() {
        guard let userID = authService.currentUser?.id else { return }
        let logDescriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.userID == userID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        userLogs = (try? modelContext.fetch(logDescriptor)) ?? []

        let tripDescriptor = FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allTrips = (try? modelContext.fetch(tripDescriptor)) ?? []
        userTrips = allTrips.filter { $0.isAccessible(by: userID) }

        // Cache sorted available trips
        let latestLogByTrip: [String: Date] = userLogs.reduce(into: [:]) { map, log in
            guard let tripID = log.tripID else { return }
            if let existing = map[tripID] {
                if log.createdAt > existing { map[tripID] = log.createdAt }
            } else {
                map[tripID] = log.createdAt
            }
        }
        cachedAvailableTrips = userTrips.sorted { a, b in
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
                        .foregroundStyle(SonderColors.inkDark)
                        .padding(.top, SonderSpacing.lg)

                    // Rating circles
                    HStack(spacing: SonderSpacing.md) {
                        ForEach(Rating.allCases, id: \.self) { rating in
                            ratingCircle(rating)
                        }
                    }
                    .padding(.horizontal, SonderSpacing.md)
                }

                // Trip section
                tripSection
                    .padding(.top, SonderSpacing.xl)

                // When
                dateSection
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.top, SonderSpacing.lg)
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
                    .foregroundStyle(.white)
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
                        .foregroundStyle(SonderColors.inkDark)
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
        .toolbar(showConfirmation ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(SonderColors.inkMuted)
            }
        }
        .navigationDestination(isPresented: $showAddDetails) {
            if let log = newLogForDetails {
                LogViewScreen(
                    log: log,
                    place: place,
                    isNewLog: true,
                    onLogComplete: onLogComplete
                )
            }
        }
        .task { refreshData() }
        .onChange(of: showAddDetails) { _, isShowing in
            if isShowing && newLogForDetails == nil {
                newLogForDetails = createNewLog()
            }
            if !isShowing {
                newLogForDetails = nil
            }
        }
        .overlay {
            if showConfirmation {
                LogConfirmationView(
                    onDismiss: {
                        showConfirmation = false
                        onLogComplete(place.coordinate)
                    },
                    tripName: coverNudgeTrip?.name,
                    onAddCover: {
                        showConfirmation = false
                        showCoverImagePicker = true
                    },
                    placeName: place.name,
                    ratingEmoji: selectedRating?.emoji
                )
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showNewTripSheet) {
            newTripSheet
        }
        .sheet(isPresented: $showCoverImagePicker) {
            EditableImagePicker { image in
                showCoverImagePicker = false
                if let trip = coverNudgeTrip, let userId = authService.currentUser?.id {
                    let tripID = trip.id
                    let engine = syncEngine
                    Task {
                        if let url = await photoService.uploadPhoto(image, for: userId) {
                            engine.updateTripCoverPhoto(tripID: tripID, url: url)
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
        .alert("Couldn't Save Trip", isPresented: Binding(
            get: { tripSaveError != nil },
            set: { if !$0 { tripSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { tripSaveError = nil }
        } message: {
            Text(tripSaveError ?? "An unknown error occurred.")
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
                .foregroundStyle(SonderColors.terracotta)

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(place.name)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(2)

                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    // MARK: - Rating Circle

    private func ratingCircle(_ rating: Rating) -> some View {
        let isSelected = selectedRating == rating
        let color = SonderColors.pinColor(for: rating)

        return Button {
            SonderHaptics.impact(.medium)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedRating = rating
            }
        } label: {
            VStack(spacing: SonderSpacing.xs) {
                Text(rating.emoji)
                    .font(.system(size: 32))
                    .frame(width: 62, height: 62)
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
                    .foregroundStyle(SonderColors.inkDark)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Section

    private var dateSection: some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(SonderColors.inkMuted)

            DatePicker("", selection: $visitedAt)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(SonderColors.terracotta)
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Add to a trip?")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)
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
                        .foregroundStyle(SonderColors.inkDark)
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
                        .foregroundStyle(SonderColors.terracotta)
                    Text("Saving to \(trip.name)")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }
                .padding(.horizontal, SonderSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userTrips.count)
        .animation(.easeInOut(duration: 0.25), value: selectedTrip?.id)
    }

    private func tripChip(_ trip: Trip) -> some View {
        let isSelected = selectedTrip?.id == trip.id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTrip = isSelected ? nil : trip
            }
            SonderHaptics.impact(.light)
        } label: {
            HStack(spacing: 4) {
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
            .foregroundStyle(isSelected ? .white : SonderColors.inkDark)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

        modelContext.insert(trip)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(trip)
            tripSaveError = error.localizedDescription
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTrip = trip
        }
        SonderHaptics.impact(.light)

        // Upload user-picked cover photo in background
        if let coverImage = newTripCoverImage {
            let tripID = trip.id
            let engine = syncEngine
            Task {
                if let url = await photoService.uploadPhoto(coverImage, for: userId) {
                    engine.updateTripCoverPhoto(tripID: tripID, url: url)
                }
            }
        }
    }

    // MARK: - Actions

    private func createNewLog() -> Log? {
        guard let rating = selectedRating,
              let userId = authService.currentUser?.id else { return nil }
        let log = Log(
            userID: userId,
            placeID: place.id,
            rating: rating,
            tripID: selectedTrip?.id,
            visitedAt: visitedAt,
            syncStatus: .pending
        )
        modelContext.insert(log)
        try? modelContext.save()
        return log
    }

    private func quickSave() {
        guard let rating = selectedRating,
              let userId = authService.currentUser?.id else { return }

        isSaving = true

        let log = Log(
            userID: userId,
            placeID: place.id,
            rating: rating,
            tripID: selectedTrip?.id,
            visitedAt: visitedAt,
            syncStatus: .pending
        )

        modelContext.insert(log)

        do {
            try modelContext.save()

            SonderHaptics.notification(.success)

            Task {
                // Remove from Want to Go if bookmarked
                await wantToGoService.removeBookmarkIfLoggedPlace(placeID: place.id, userID: userId)
                await syncEngine.syncNow()
            }

            showConfirmation = true
        } catch {
            logger.error("Failed to save log: \(error.localizedDescription)")
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
            logger.debug("Log complete")
        }
    }
}
