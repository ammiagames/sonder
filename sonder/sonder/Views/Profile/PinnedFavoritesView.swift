//
//  PinnedFavoritesView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI
import SwiftData

// MARK: - Pinned Favorites Display

struct PinnedFavoritesView: View {
    let logs: [Log]
    let places: [Place]
    let pinnedPlaceIDs: [String]
    let onEditTapped: () -> Void

    private var pinnedPlaces: [Place] {
        pinnedPlaceIDs.compactMap { id in places.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            HStack {
                Text("Favorites")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    onEditTapped()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SonderColors.terracotta)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: SonderSpacing.xs), count: 4)

            LazyVGrid(columns: columns, spacing: SonderSpacing.xs) {
                ForEach(0..<4, id: \.self) { index in
                    if index < pinnedPlaces.count {
                        let place = pinnedPlaces[index]
                        let log = logs.first(where: { $0.placeID == place.id })

                        NavigationLink {
                            if let log = log {
                                LogDetailView(log: log, place: place)
                            }
                        } label: {
                            pinnedCard(place: place, log: log)
                        }
                        .buttonStyle(.plain)
                        .disabled(log == nil)
                    } else {
                        Button { onEditTapped() } label: {
                            emptySlot
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Pinned Card

    private func pinnedCard(place: Place, log: Log?) -> some View {
        VStack(spacing: SonderSpacing.xxs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let photoURL = log?.photoURL, let url = URL(string: photoURL) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) {
                            photoFallback
                        }
                        .scaledToFill()
                    } else if let ref = place.photoReference,
                              let url = GooglePlacesService.photoURL(for: ref, maxWidth: 200) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) {
                            photoFallback
                        }
                        .scaledToFill()
                    } else {
                        photoFallback
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            Text(place.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(SonderColors.inkDark)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 26)
        }
    }

    private var photoFallback: some View {
        LinearGradient(
            colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(SonderColors.terracotta.opacity(0.4))
        }
    }

    private var emptySlot: some View {
        VStack(spacing: SonderSpacing.xxs) {
            RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(SonderColors.inkLight.opacity(0.5))
                }

            Text(" ")
                .font(.system(size: 10))
                .frame(height: 26)
        }
    }
}

// MARK: - Pinned Favorites Editor Sheet

struct PinnedFavoritesEditorSheet: View {
    let logs: [Log]
    let places: [Place]

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selectedIDs: [String] = []

    /// Unique places the user has logged, sorted by most recent
    private var loggedPlaces: [Place] {
        let loggedPlaceIDs = Set(logs.map { $0.placeID })
        let uniquePlaces = places.filter { loggedPlaceIDs.contains($0.id) }

        // Sort by most recent log date
        return uniquePlaces.sorted { p1, p2 in
            let date1 = logs.filter { $0.placeID == p1.id }.map(\.createdAt).max() ?? .distantPast
            let date2 = logs.filter { $0.placeID == p2.id }.map(\.createdAt).max() ?? .distantPast
            return date1 > date2
        }
    }

    private var filteredPlaces: [Place] {
        guard !searchText.isEmpty else { return loggedPlaces }
        let search = searchText.lowercased()
        return loggedPlaces.filter {
            $0.name.lowercased().contains(search) || $0.address.lowercased().contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredPlaces, id: \.id) { place in
                    let isSelected = selectedIDs.contains(place.id)
                    let isDisabled = !isSelected && selectedIDs.count >= 4

                    Button {
                        togglePlace(place.id)
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            PlacePhotoView(photoReference: place.photoReference, size: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(SonderColors.inkDark)
                                    .lineLimit(1)
                                Text(place.address)
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.inkMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isSelected {
                                if let idx = selectedIDs.firstIndex(of: place.id) {
                                    Text("\(idx + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 24, height: 24)
                                        .background(SonderColors.terracotta)
                                        .clipShape(Circle())
                                }
                            } else {
                                Circle()
                                    .stroke(SonderColors.inkLight, lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .opacity(isDisabled ? 0.4 : 1.0)
                    }
                    .disabled(isDisabled)
                    .listRowBackground(SonderColors.warmGray)
                }
            }
            .searchable(text: $searchText, prompt: "Search your places")
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .navigationTitle("Edit Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedIDs = authService.currentUser?.pinnedPlaceIDs ?? []
            }
        }
    }

    private func togglePlace(_ id: String) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else if selectedIDs.count < 4 {
            selectedIDs.append(id)
        }
    }

    private func save() {
        guard let user = authService.currentUser else { return }
        user.pinnedPlaceIDs = selectedIDs
        user.updatedAt = Date()
        try? modelContext.save()
    }
}
