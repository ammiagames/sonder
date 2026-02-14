//
//  SearchPlaceView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI
import SwiftData
import CoreLocation

/// Screen 1: Search for a place to log
struct SearchPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(LocationService.self) private var locationService
    @Environment(PlacesCacheService.self) private var cacheService

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
            }
            .background(SonderColors.cream)
            .navigationTitle("Log a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(SonderColors.inkMuted)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCustomPlace = true
                    } label: {
                        Image(systemName: "mappin.circle")
                            .foregroundColor(SonderColors.terracotta)
                    }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                if let details = selectedDetails {
                    PlacePreviewView(details: details) {
                        // Cache place and navigate to rating
                        let place = cacheService.cachePlace(from: details)
                        cacheService.addRecentSearch(
                            placeId: place.id,
                            name: place.name,
                            address: place.address
                        )
                        placeToLog = place
                    }
                }
            }
        }
        .onAppear {
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
                RatePlaceView(place: place) {
                    // Pop the preview first (hidden under the cover)
                    showPreview = false
                    searchText = ""
                    // Dismiss the cover on next frame so preview is already gone
                    DispatchQueue.main.async {
                        placeToLog = nil
                    }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SonderColors.inkMuted)

            TextField("Search for a place...", text: $searchText)
                .font(SonderTypography.body)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
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
                        .foregroundColor(SonderColors.inkLight)
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
                            .foregroundColor(SonderColors.inkLight)

                        Text("No Results")
                            .font(SonderTypography.title)
                            .foregroundColor(SonderColors.inkDark)

                        Text("Try a different search term")
                            .font(SonderTypography.body)
                            .foregroundColor(SonderColors.inkMuted)
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
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            } else {
                sectionHeader("Cached Places")
                ForEach(cachedResults, id: \.id) { place in
                    PlaceSearchRow(
                        name: place.name,
                        address: place.address,
                        photoReference: place.photoReference,
                        placeId: place.id,
                        onBookmark: {}
                    )
                    .onTapGesture {
                        selectPlace(place)
                    }
                    Divider().padding(.leading, 68)
                }
            }
        } else {
            ForEach(predictions) { prediction in
                PlaceSearchRow(
                    name: prediction.mainText,
                    address: prediction.secondaryText,
                    placeId: prediction.placeId,
                    onBookmark: {}
                )
                .onTapGesture {
                    selectPrediction(prediction)
                }
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
                PlaceSearchRow(
                    name: place.name,
                    address: place.address,
                    photoReference: place.photoReference,
                    placeId: place.placeId,
                    onBookmark: {}
                )
                .id("nearby-\(place.placeId)")
                .onTapGesture {
                    selectNearbyPlace(place)
                }
                Divider().padding(.leading, 68)
            }
        }
    }

    // MARK: - Location Permission

    private var locationPermissionBanner: some View {
        VStack(spacing: SonderSpacing.sm) {
            Image(systemName: "location.fill")
                .font(.system(size: 32))
                .foregroundColor(SonderColors.terracotta)

            Text("Enable Location")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            Text("See places near you for quick logging")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
                .multilineTextAlignment(.center)

            Button("Enable Location") {
                locationService.requestPermission()
            }
            .font(SonderTypography.headline)
            .foregroundColor(.white)
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
        let recentSearches = Array(cacheService.getRecentSearches().prefix(5))

        if !recentSearches.isEmpty {
            sectionHeader("Recent")

            ForEach(recentSearches, id: \.placeId) { search in
                let cachedPlace = cacheService.getPlace(by: search.placeId)
                RecentSearchRow(
                    name: search.name,
                    address: search.address,
                    photoReference: cachedPlace?.photoReference,
                    placeId: search.placeId
                ) {
                    // Track as removing so it doesn't appear in nearby during animation
                    removingPlaceIds.insert(search.placeId)

                    withAnimation(.easeOut(duration: 0.25)) {
                        cacheService.clearRecentSearch(placeId: search.placeId)
                    }

                    // Remove from tracking after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        removingPlaceIds.remove(search.placeId)
                    }
                }
                .id("recent-\(search.placeId)")
                .onTapGesture {
                    selectRecentSearch(search)
                }
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                Divider().padding(.leading, 68)
            }
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(SonderTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(SonderColors.inkMuted)
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
                .foregroundColor(SonderColors.ochre)
            Text(message)
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkDark)
            Spacer()
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.ochre.opacity(0.1))
    }

    // MARK: - Actions

    private func loadNearbyPlaces() {
        print("[Nearby] isAuthorized: \(locationService.isAuthorized), currentLocation: \(String(describing: locationService.currentLocation))")
        guard locationService.isAuthorized else {
            print("[Nearby] Not authorized — skipping")
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
                print("[Nearby] Waiting for location... attempt \(i + 1)")
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard let location = locationService.currentLocation else {
                print("[Nearby] Location never resolved — giving up")
                isLoadingNearby = false
                return
            }

            print("[Nearby] Got location: \(location.latitude), \(location.longitude)")
            nearbyPlaces = await placesService.nearbySearch(location: location)
            print("[Nearby] Got \(nearbyPlaces.count) nearby places")
            isLoadingNearby = false
        }
    }

    private func selectPrediction(_ prediction: PlacePrediction) {
        Task {
            isLoadingDetails = true
            detailsError = nil

            guard let details = await placesService.getPlaceDetails(placeId: prediction.placeId) else {
                isLoadingDetails = false
                detailsError = placesService.error?.localizedDescription ?? "Failed to load place details"
                return
            }

            isLoadingDetails = false
            selectedDetails = details
            showPreview = true
        }
    }

    private func selectNearbyPlace(_ nearby: NearbyPlace) {
        // Fetch full details for preview (nearby doesn't have rating/price/description)
        Task {
            isLoadingDetails = true
            detailsError = nil

            guard let details = await placesService.getPlaceDetails(placeId: nearby.placeId) else {
                isLoadingDetails = false
                detailsError = placesService.error?.localizedDescription ?? "Failed to load place details"
                return
            }

            isLoadingDetails = false
            selectedDetails = details
            showPreview = true
        }
    }

    private func selectRecentSearch(_ search: RecentSearch) {
        Task {
            isLoadingDetails = true
            detailsError = nil

            guard let details = await placesService.getPlaceDetails(placeId: search.placeId) else {
                isLoadingDetails = false
                detailsError = placesService.error?.localizedDescription ?? "Failed to load place details"
                return
            }

            isLoadingDetails = false
            selectedDetails = details
            showPreview = true
        }
    }

    private func selectPlace(_ place: Place) {
        // Fetch full details for preview
        Task {
            isLoadingDetails = true
            detailsError = nil

            guard let details = await placesService.getPlaceDetails(placeId: place.id) else {
                isLoadingDetails = false
                detailsError = placesService.error?.localizedDescription ?? "Failed to load place details"
                return
            }

            isLoadingDetails = false
            selectedDetails = details
            showPreview = true
        }
    }
}

#Preview {
    SearchPlaceView()
}

#Preview {
    SearchPlaceView()
}
