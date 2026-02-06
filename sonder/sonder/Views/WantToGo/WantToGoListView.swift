//
//  WantToGoListView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

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

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else {
                itemsList
            }
        }
        .navigationTitle("Want to Go")
        .refreshable {
            await loadItems()
        }
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
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
            }
        }
        .task {
            await loadItems()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Saved Places", systemImage: "bookmark")
        } description: {
            Text("Save places from your friends' logs to remember for later")
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        List {
            // Group by source user
            let groupedItems = Dictionary(grouping: items) { $0.sourceUser?.id ?? "self" }

            ForEach(Array(groupedItems.keys.sorted()), id: \.self) { key in
                if let groupItems = groupedItems[key] {
                    Section {
                        ForEach(groupItems, id: \.id) { item in
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
                        }
                    } header: {
                        if let sourceUser = groupItems.first?.sourceUser {
                            Text("From @\(sourceUser.username)")
                        } else {
                            Text("Saved by you")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                items.removeAll { $0.id == item.id }

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
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
        HStack(spacing: 12) {
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                photoPlaceholder
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.place.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(item.place.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Unbookmark button
            Button {
                onUnbookmark()
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            // Chevron to indicate tappable
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
    }
}

#Preview {
    NavigationStack {
        WantToGoListView()
    }
}
