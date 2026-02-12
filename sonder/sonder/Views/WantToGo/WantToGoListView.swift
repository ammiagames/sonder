//
//  WantToGoListView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Grouping mode for Want to Go list
enum WantToGoGrouping: String, CaseIterable {
    case recent = "Recent"
    case city = "City"
}

/// List of places saved to Want to Go
struct WantToGoListView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(GooglePlacesService.self) private var placesService
    @Environment(PlacesCacheService.self) private var cacheService

    @State private var items: [WantToGoWithPlace] = []
    @State private var isLoading = true
    @State private var isLoadingDetails = false
    @State private var selectedDetails: PlaceDetails?
    @State private var placeToLog: Place?
    @State private var placeIDToRemove: String?
    @State private var showPreview = false
    @State private var grouping: WantToGoGrouping = .recent

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(SonderColors.terracotta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .background(SonderColors.cream)
        .navigationTitle("Want to Go")
        .navigationDestination(isPresented: $showPreview) {
            if let details = selectedDetails {
                PlacePreviewView(details: details) {
                    // User wants to log this place - cache it and show rating view
                    let place = cacheService.cachePlace(from: details)
                    placeIDToRemove = place.id
                    placeToLog = place
                }
            }
        }
        .fullScreenCover(item: $placeToLog) { place in
            NavigationStack {
                RatePlaceView(place: place) {
                    // Logging complete - dismiss and go back to list
                    let placeID = placeIDToRemove
                    placeToLog = nil
                    showPreview = false
                    if let placeID = placeID {
                        removeFromWantToGo(placeID: placeID)
                    }
                    placeIDToRemove = nil
                }
            }
        }
        .overlay {
            if isLoadingDetails {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView("Loading place...")
                            .tint(SonderColors.terracotta)
                            .padding(SonderSpacing.lg)
                            .background(SonderColors.warmGray)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
            }
        }
        .task {
            await loadItems()
        }
    }

    // MARK: - Grouping Picker

    private var groupingPicker: some View {
        HStack(spacing: SonderSpacing.xs) {
            ForEach(WantToGoGrouping.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        grouping = mode
                    }
                } label: {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: mode == .recent ? "clock" : "building.2")
                            .font(.caption)
                        Text(mode.rawValue)
                            .font(SonderTypography.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xs)
                    .background(grouping == mode ? SonderColors.terracotta : SonderColors.warmGray)
                    .foregroundColor(grouping == mode ? .white : SonderColors.inkDark)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, SonderSpacing.xxs)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundColor(SonderColors.inkLight)

            Text("No Saved Places")
                .font(SonderTypography.title)
                .foregroundColor(SonderColors.inkDark)

            Text("Save places from your friends' logs to remember for later")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SonderSpacing.xl)
    }

    // MARK: - Items List

    private var itemsList: some View {
        List {
            // Grouping picker as list header
            Section {
                groupingPicker
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            switch grouping {
            case .recent:
                recentGroupedList
            case .city:
                cityGroupedList
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SonderColors.cream)
    }

    // MARK: - Recent (Reverse Chronological) List

    private var recentGroupedList: some View {
        ForEach(items.sorted { $0.createdAt > $1.createdAt }, id: \.id) { item in
            itemRow(item)
        }
    }

    // MARK: - City Grouped List

    private var cityGroupedList: some View {
        let groupedByCity = Dictionary(grouping: items) { extractCity(from: $0.place.address) }
        let sortedCities = groupedByCity.keys.sorted()

        return ForEach(sortedCities, id: \.self) { city in
            if let cityItems = groupedByCity[city] {
                Section {
                    ForEach(cityItems.sorted { $0.createdAt > $1.createdAt }, id: \.id) { item in
                        itemRow(item)
                    }
                } header: {
                    HStack {
                        Image(systemName: "building.2")
                            .font(.caption)
                        Text(city)
                    }
                }
            }
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: WantToGoWithPlace) -> some View {
        WantToGoRow(item: item) {
            removeItem(item)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectPlace(item)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                removeItem(item)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    // MARK: - City Extraction

    private func extractCity(from address: String) -> String {
        let components = address.components(separatedBy: ", ")

        // Try to extract city from address format like:
        // "123 Main St, City, State ZIP, Country" or "City, Country"
        guard components.count >= 2 else {
            return "Unknown"
        }

        // For US addresses: "Street, City, State ZIP, Country" - city is index 1
        // For international: "Street, City, Country" - city is index 1
        // If only 2 components, first is likely the city
        if components.count == 2 {
            return components[0].trimmingCharacters(in: .whitespaces)
        }

        // Get second-to-last component that isn't a state/zip pattern
        let potentialCity = components[components.count - 3]
        let trimmed = potentialCity.trimmingCharacters(in: .whitespaces)

        // If it looks like a state abbreviation (2 chars) or contains numbers, try previous
        if trimmed.count <= 2 || trimmed.contains(where: { $0.isNumber }) {
            if components.count >= 4 {
                return components[components.count - 4].trimmingCharacters(in: .whitespaces)
            }
        }

        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    // MARK: - Actions

    private func selectPlace(_ item: WantToGoWithPlace) {
        Task {
            isLoadingDetails = true

            if let details = await placesService.getPlaceDetails(placeId: item.place.id) {
                selectedDetails = details
                showPreview = true
            }

            isLoadingDetails = false
        }
    }

    // MARK: - Data Loading

    private func loadItems() async {
        guard let userID = authService.currentUser?.id else { return }

        isLoading = true
        do {
            items = try await wantToGoService.fetchWantToGoWithPlaces(for: userID)
        } catch {
            print("Error loading want to go: \(error)")
        }
        isLoading = false
    }

    private func removeItem(_ item: WantToGoWithPlace) {
        guard let userID = authService.currentUser?.id else { return }

        Task {
            do {
                try await wantToGoService.removeFromWantToGo(placeID: item.place.id, userID: userID)

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Animate removal
                withAnimation(.easeOut(duration: 0.25)) {
                    items.removeAll { $0.id == item.id }
                }
            } catch {
                print("Error removing item: \(error)")
            }
        }
    }

    private func removeFromWantToGo(placeID: String) {
        guard let userID = authService.currentUser?.id else { return }

        Task {
            do {
                try await wantToGoService.removeFromWantToGo(placeID: placeID, userID: userID)
                items.removeAll { $0.place.id == placeID }
            } catch {
                print("Error removing from want to go: \(error)")
            }
        }
    }
}

// MARK: - Want to Go Row

struct WantToGoRow: View {
    let item: WantToGoWithPlace
    let onUnbookmark: () -> Void

    var body: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo
            if let photoRef = item.place.photoReference,
               let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        photoPlaceholder
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            } else {
                photoPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(item.place.name)
                    .font(SonderTypography.headline)
                    .lineLimit(1)
                    .foregroundColor(SonderColors.inkDark)

                Text(item.place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .lineLimit(1)

                // Source info
                HStack(spacing: SonderSpacing.xxs) {
                    if let sourceUser = item.sourceUser {
                        Text("from @\(sourceUser.username)")
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.terracotta)
                    }
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(SonderColors.inkLight)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundColor(SonderColors.inkLight)
                }
            }

            Spacer()

            // Unbookmark button
            Button {
                onUnbookmark()
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18))
                    .foregroundColor(SonderColors.terracotta)
            }
            .buttonStyle(.plain)

            // Chevron to indicate tappable
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SonderColors.inkLight)
        }
        .padding(.vertical, SonderSpacing.xxs)
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(SonderColors.terracotta.opacity(0.5))
            }
    }
}

#Preview {
    NavigationStack {
        WantToGoListView()
    }
}
