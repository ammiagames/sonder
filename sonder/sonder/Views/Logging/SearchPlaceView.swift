//
//  SearchPlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "SearchPlaceView")

/// Screen 1: Search for a place to log
struct SearchPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(LocationService.self) private var locationService
    @Environment(PlacesCacheService.self) private var cacheService
    @Environment(AuthenticationService.self) private var authService

    var onLogComplete: ((CLLocationCoordinate2D) -> Void)?

    @State private var loggedPlaceIDs: Set<String> = []
    @State private var searchText = ""
    @State private var predictions: [PlacePrediction] = []
    @State private var nearbyPlaces: [NearbyPlace] = []
    @State private var selectedDetails: PlaceDetails?
    @State private var showPreview = false
    @State private var placeToLog: Place?
    @State private var showCustomPlace = false
    @State private var isLoadingNearby = false
    @State private var isLoadingDetails = false
    @State private var detailsError: String?
    @State private var removingPlaceIds: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Error messages
                        if let error = detailsError {
                            errorBanner(message: error)
                        } else if let error = placesService.error, predictions.isEmpty, !searchText.isEmpty {
                            errorBanner(message: error.localizedDescription)
                        }

                        // Search results
                        if !searchText.isEmpty {
                            searchResultsSection
                        } else {
                            // Recent searches first (max 5)
                            recentSearchesSection

                            // Then nearby places (excluding recents)
                            if locationService.isAuthorized {
                                nearbySection
                            } else if cacheService.getRecentSearches().isEmpty {
                                // Only show location prompt if no recents
                                locationPermissionBanner
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .background(SonderColors.cream)
            .navigationTitle("Log a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCustomPlace = true
                    } label: {
                        Image(systemName: "mappin.circle")
                            .foregroundStyle(SonderColors.terracotta)
                    }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                if let details = selectedDetails {
                    PlacePreviewView(details: details) {
                        // Place is already cached from selectPlace(byID:)
                        if let place = cacheService.getPlace(by: details.placeId) {
                            placeToLog = place
                        } else {
                            // Fallback: cache now (shouldn't normally happen)
                            placeToLog = cacheService.cachePlace(from: details)
                        }
                    }
                }
            }
        }
        .task {
            // Fetch logged place IDs with a targeted query instead of
            // @Query over ALL logs (which blocks the main thread on init).
            if let userID = authService.currentUser?.id {
                let descriptor = FetchDescriptor<Log>(
                    predicate: #Predicate { $0.userID == userID }
                )
                if let logs = try? modelContext.fetch(descriptor) {
                    loggedPlaceIDs = Set(logs.map(\.placeID))
                }
            }
            loadNearbyPlaces()
        }
        .sheet(isPresented: $showCustomPlace) {
            CreateCustomPlaceView { place in
                showCustomPlace = false
                // Present rating after sheet dismisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    placeToLog = place
                }
            }
        }
        .fullScreenCover(item: $placeToLog) { place in
            NavigationStack {
                RatePlaceView(place: place) { coord in
                    // Pop the preview first (hidden under the cover)
                    showPreview = false
                    searchText = ""
                    // Dismiss the cover on next frame so preview is already gone
                    DispatchQueue.main.async {
                        placeToLog = nil
                    }
                    onLogComplete?(coord)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SonderColors.inkMuted)

            AutoFocusTextField(
                text: $searchText,
                placeholder: "Search for a place..."
            )
            .frame(height: 22)
            .onChange(of: searchText) { _, newValue in
                Task {
                    predictions = await placesService.autocomplete(
                        query: newValue,
                        location: locationService.currentLocation
                    )
                }
            }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .padding(SonderSpacing.md)
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if placesService.isLoading {
            ProgressView()
                .tint(SonderColors.terracotta)
                .padding()
        } else if predictions.isEmpty && !searchText.isEmpty {
            let cachedResults = cacheService.searchCachedPlaces(query: searchText)
            if cachedResults.isEmpty {
                // No results - show option to add own spot
                VStack(spacing: SonderSpacing.lg) {
                    VStack(spacing: SonderSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(SonderColors.inkLight)

                        Text("No Results")
                            .font(SonderTypography.title)
                            .foregroundStyle(SonderColors.inkDark)

                        Text("Try a different search term")
                            .font(SonderTypography.body)
                            .foregroundStyle(SonderColors.inkMuted)
                    }

                    Button {
                        showCustomPlace = true
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                            Text("Add Your Own Spot")
                                .font(SonderTypography.headline)
                        }
                        .padding(.horizontal, SonderSpacing.lg)
                        .padding(.vertical, SonderSpacing.sm)
                        .background(SonderColors.terracotta)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
            } else {
                sectionHeader("Cached Places")
                ForEach(cachedResults, id: \.id) { place in
                    Button {
                        selectPlace(byID: place.id)
                    } label: {
                        PlaceSearchRow(
                            name: place.name,
                            address: place.address,
                            photoReference: place.photoReference,
                            placeId: place.id,
                            onBookmark: {}
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, SonderSpacing.md)
                }
            }
        } else {
            ForEach(predictions) { prediction in
                Button {
                    selectPlace(byID: prediction.placeId)
                } label: {
                    PlaceSearchRow(
                        name: prediction.mainText,
                        address: prediction.secondaryText,
                        placeId: prediction.placeId,
                        distanceText: formatDistance(meters: prediction.distanceMeters),
                        onBookmark: {}
                    )
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 68)
            }
        }
    }

    // MARK: - Nearby Section

    @ViewBuilder
    private var nearbySection: some View {
        // Filter out places already shown in recents AND places being removed (to avoid duplicate during animation)
        let filteredNearby = nearbyPlaces.filter {
            !recentPlaceIds.contains($0.placeId) && !removingPlaceIds.contains($0.placeId)
        }

        if isLoadingNearby {
            sectionHeader("Nearby")
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding()
        } else if filteredNearby.isEmpty {
            // Don't show section if no nearby places after filtering
            EmptyView()
        } else {
            sectionHeader("Nearby")
            ForEach(filteredNearby) { place in
                Button {
                    selectPlace(byID: place.placeId)
                } label: {
                    PlaceSearchRow(
                        name: place.name,
                        address: place.address,
                        photoReference: place.photoReference,
                        placeId: place.placeId,
                        distanceText: distanceToNearby(place),
                        onBookmark: {}
                    )
                }
                .buttonStyle(.plain)
                .id("nearby-\(place.placeId)")
                Divider().padding(.leading, 68)
            }
        }
    }

    // MARK: - Location Permission

    private var locationPermissionBanner: some View {
        VStack(spacing: SonderSpacing.sm) {
            Image(systemName: "location.fill")
                .font(.system(size: 32))
                .foregroundStyle(SonderColors.terracotta)

            Text("Enable Location")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Text("See places near you for quick logging")
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkMuted)
                .multilineTextAlignment(.center)

            Button("Enable Location") {
                locationService.requestPermission()
            }
            .font(SonderTypography.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.vertical, SonderSpacing.sm)
            .background(SonderColors.terracotta)
            .clipShape(Capsule())
        }
        .padding(SonderSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .padding(SonderSpacing.md)
    }

    // MARK: - Recent Searches

    /// IDs of recent searches (for filtering nearby)
    private var recentPlaceIds: Set<String> {
        Set(cacheService.getRecentSearches().prefix(5).map { $0.placeId })
    }

    @ViewBuilder
    private var recentSearchesSection: some View {
        // Depend on version to trigger re-render when searches change
        let _ = cacheService.recentSearchesVersion
        let recentSearches = Array(
            cacheService.getRecentSearches()
                .filter { !loggedPlaceIDs.contains($0.placeId) }
                .prefix(5)
        )

        if !recentSearches.isEmpty {
            sectionHeader("Recent")

            ForEach(recentSearches, id: \.placeId) { search in
                let cachedPlace = cacheService.getPlace(by: search.placeId)
                let isRemoving = removingPlaceIds.contains(search.placeId)

                VStack(spacing: 0) {
                    Button {
                        selectPlace(byID: search.placeId)
                    } label: {
                        RecentSearchRow(
                            name: search.name,
                            address: search.address,
                            photoReference: cachedPlace?.photoReference,
                            placeId: search.placeId
                        ) {
                            // Step 1: Animate the row out
                            _ = withAnimation(.easeOut(duration: 0.25)) {
                                removingPlaceIds.insert(search.placeId)
                            }

                            // Step 2: Delete data after animation completes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                cacheService.clearRecentSearch(placeId: search.placeId)
                                removingPlaceIds.remove(search.placeId)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, SonderSpacing.md)
                }
                .offset(x: isRemoving ? 400 : 0)
                .opacity(isRemoving ? 0 : 1)
                .frame(height: isRemoving ? 0 : nil, alignment: .top)
                .clipped()
                .animation(.easeOut(duration: 0.25), value: isRemoving)
                .id("recent-\(search.placeId)")
            }
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.top, SonderSpacing.md)
        .padding(.bottom, SonderSpacing.xs)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SonderColors.ochre)
            Text(message)
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkDark)
            Spacer()
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.ochre.opacity(0.1))
    }

    // MARK: - Actions

    private func loadNearbyPlaces() {
        logger.debug("[Nearby] isAuthorized: \(locationService.isAuthorized), currentLocation: \(String(describing: locationService.currentLocation))")
        guard locationService.isAuthorized else {
            logger.debug("[Nearby] Not authorized — skipping")
            return
        }

        isLoadingNearby = true

        // Request location if not available
        if locationService.currentLocation == nil {
            locationService.requestLocation()
        }

        // Load nearby when location is available
        Task {
            // Wait for location (max 5 seconds)
            for i in 0..<10 {
                if locationService.currentLocation != nil { break }
                logger.debug("[Nearby] Waiting for location... attempt \(i + 1)")
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard let location = locationService.currentLocation else {
                logger.warning("[Nearby] Location never resolved — giving up")
                isLoadingNearby = false
                return
            }

            logger.debug("[Nearby] Got location: \(location.latitude), \(location.longitude)")

            // Check cache first to avoid redundant API calls
            if let cached = cacheService.getCachedNearby(for: location) {
                logger.debug("[Nearby] Using cached results (\(cached.count) places)")
                nearbyPlaces = cached
                isLoadingNearby = false
                return
            }

            nearbyPlaces = await placesService.nearbySearch(location: location)
            cacheService.cacheNearbyResults(nearbyPlaces, location: location)
            logger.debug("[Nearby] Got \(nearbyPlaces.count) nearby places")
            isLoadingNearby = false
        }
    }

    /// Fetches full place details by ID and navigates to the preview screen.
    /// Uses cached data when offline so recent searches still work without network.
    private func selectPlace(byID placeId: String) {
        Task {
            isLoadingDetails = true
            detailsError = nil

            // Try network first
            if let details = await placesService.getPlaceDetails(placeId: placeId) {
                // Cache place locally (enables instant map pin if bookmarked)
                // and add to recent searches immediately on tap
                let place = cacheService.cachePlace(from: details)
                cacheService.addRecentSearch(
                    placeId: place.id,
                    name: place.name,
                    address: place.address
                )

                isLoadingDetails = false
                selectedDetails = details
                showPreview = true
                return
            }

            // Offline fallback: use cached Place from SwiftData
            if let cachedPlace = cacheService.getPlace(by: placeId) {
                let offlineDetails = PlaceDetails(
                    placeId: cachedPlace.id,
                    name: cachedPlace.name,
                    formattedAddress: cachedPlace.address,
                    latitude: cachedPlace.latitude,
                    longitude: cachedPlace.longitude,
                    types: cachedPlace.types,
                    photoReference: cachedPlace.photoReference,
                    rating: nil,
                    userRatingCount: nil,
                    priceLevel: nil,
                    editorialSummary: nil
                )

                isLoadingDetails = false
                selectedDetails = offlineDetails
                showPreview = true
                return
            }

            // Neither network nor cache available
            isLoadingDetails = false
            detailsError = placesService.error?.localizedDescription ?? "Failed to load place details"
        }
    }

    // MARK: - Distance Formatting

    private func formatDistance(meters: Int?) -> String? {
        guard let meters else { return nil }
        let miles = Double(meters) / 1609.34
        if miles < 0.1 {
            let feet = Int(Double(meters) * 3.281)
            return "\(feet) ft"
        } else if miles < 10 {
            return String(format: "%.1f mi", miles)
        } else {
            return "\(Int(miles)) mi"
        }
    }

    private func distanceToNearby(_ place: NearbyPlace) -> String? {
        guard let userLocation = locationService.currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let meters = Int(userCLLocation.distance(from: placeLocation))
        return formatDistance(meters: meters)
    }
}

#Preview {
    SearchPlaceView()
}

#Preview {
    SearchPlaceView()
}
