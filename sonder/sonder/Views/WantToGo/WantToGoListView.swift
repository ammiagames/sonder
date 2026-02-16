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
    @State private var grouping: WantToGoGrouping = .recent
    @State private var scrollToCity: String?
    @State private var visibleCitySections: Set<String> = []

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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedDetails) { details in
            PlacePreviewView(details: details) {
                // User wants to log this place - cache it and show rating view
                let place = cacheService.cachePlace(from: details)
                placeIDToRemove = place.id
                placeToLog = place
            }
        }
        .fullScreenCover(item: $placeToLog) { place in
            NavigationStack {
                RatePlaceView(place: place) { _ in
                    let placeID = placeIDToRemove
                    // Pop the preview first (hidden under the cover)
                    selectedDetails = nil
                    placeIDToRemove = nil
                    // Dismiss the cover on next frame so preview is already gone
                    DispatchQueue.main.async {
                        placeToLog = nil
                        if let placeID {
                            removeFromWantToGo(placeID: placeID)
                        }
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SonderSpacing.xl)
    }

    // MARK: - Items List

    private var sortedCities: [String] {
        let groupedByCity = Dictionary(grouping: items) { extractCity(from: $0.place.address) }
        return groupedByCity.keys.sorted()
    }

    /// The topmost visible city section (first in sorted order that's on-screen)
    private var currentVisibleCity: String? {
        sortedCities.first { visibleCitySections.contains($0) }
    }

    private var itemsList: some View {
        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    // Grouping picker as list header
                    Section {
                        groupingPicker
                            .listRowInsets(EdgeInsets(top: SonderSpacing.xs, leading: SonderSpacing.md, bottom: SonderSpacing.xs, trailing: SonderSpacing.md))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    switch grouping {
                    case .recent:
                        recentGroupedList
                    case .city:
                        cityGroupedList
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(SonderColors.cream)
                .onChange(of: scrollToCity) { _, city in
                    if let city {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(city, anchor: .top)
                        }
                        // Clear after a short delay to allow re-selection of the same city
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            scrollToCity = nil
                        }
                    }
                }
            }

            // City section index scroller
            if grouping == .city && sortedCities.count > 1 {
                CitySectionIndex(cities: sortedCities, visibleCity: currentVisibleCity) { city in
                    scrollToCity = city
                }
                .padding(.trailing, 2)
            }
        }
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
        let cities = groupedByCity.keys.sorted()

        return ForEach(cities, id: \.self) { city in
            if let cityItems = groupedByCity[city] {
                Section {
                    ForEach(cityItems.sorted { $0.createdAt > $1.createdAt }, id: \.id) { item in
                        itemRow(item)
                    }
                } header: {
                    HStack(spacing: SonderSpacing.xxs) {
                        Image(systemName: "building.2")
                            .font(.system(size: 12, weight: .semibold))
                        Text(city)
                            .font(SonderTypography.caption)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    .foregroundColor(SonderColors.inkDark)
                    .id(city)
                    .onAppear { visibleCitySections.insert(city) }
                    .onDisappear { visibleCitySections.remove(city) }
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
        .listRowBackground(SonderColors.cream)
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
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) {
                    photoPlaceholder
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

// MARK: - City Section Index

struct CitySectionIndex: View {
    let cities: [String]
    let visibleCity: String?
    let onSelect: (String) -> Void

    @State private var dragCity: String?
    @GestureState private var isDragging = false

    /// Highlighted city: drag selection takes priority, otherwise the visible city
    var highlightedCity: String? {
        Self.resolveHighlightedCity(dragCity: dragCity, visibleCity: visibleCity)
    }

    /// Pure logic for determining which city to highlight — testable.
    static func resolveHighlightedCity(dragCity: String?, visibleCity: String?) -> String? {
        dragCity ?? visibleCity
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(cities, id: \.self) { city in
                let isHighlighted = highlightedCity == city
                Text(Self.abbreviate(city))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isHighlighted ? .white : SonderColors.terracotta)
                    .frame(width: 28, height: max(18, 140 / CGFloat(cities.count)))
                    .background(
                        isHighlighted
                            ? AnyShapeStyle(SonderColors.terracotta)
                            : AnyShapeStyle(.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, SonderSpacing.xs)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                .fill(SonderColors.warmGray.opacity(isDragging ? 0.95 : 0.75))
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    selectCity(at: value.location.y)
                }
                .onEnded { _ in
                    // Clear drag selection after scroll settles; visibleCity takes over
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        dragCity = nil
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: highlightedCity)
    }

    static func abbreviate(_ city: String) -> String {
        if city.count <= 3 { return city }
        return String(city.prefix(3))
    }

    private func selectCity(at y: CGFloat) {
        let rowHeight = max(18, 140 / CGFloat(cities.count))
        let totalPadding = SonderSpacing.xs // top padding
        let adjustedY = y - totalPadding
        let index = Int(adjustedY / rowHeight)

        guard index >= 0 && index < cities.count else { return }
        let city = cities[index]

        if city != dragCity {
            dragCity = city
            onSelect(city)
        }
    }
}

#Preview {
    NavigationStack {
        WantToGoListView()
    }
}
