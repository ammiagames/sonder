//
//  SavedListsView.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "SavedListsView")

/// Top-level destination showing all saved lists. Navigating into a list shows its places.
struct SavedListsView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(SavedListsService.self) private var savedListsService
    @Environment(WantToGoService.self) private var wantToGoService

    @State private var showCreateSheet = false
    @State private var newListName = ""
    @State private var newListEmoji = "\u{1F516}"
    @State private var listToDelete: SavedList?
    @State private var listToRename: SavedList?
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var activeDestination: SavedListDestination?

    private var userID: String? { authService.currentUser?.id }

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.sm) {
                // "All Saved Places" row
                Button {
                    activeDestination = .allPlaces
                } label: {
                    allPlacesRow
                }
                .buttonStyle(.plain)

                // Individual lists
                ForEach(savedListsService.lists, id: \.id) { list in
                    Button {
                        activeDestination = .list(id: list.id, name: list.name)
                    } label: {
                        savedListCard(list)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            listToRename = list
                            renameText = list.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            // Cycle emoji
                            Task {
                                let emojis = ["\u{1F516}", "\u{2764}\u{FE0F}", "\u{1F355}", "\u{2615}", "\u{1F378}", "\u{1F3D6}\u{FE0F}", "\u{1F30E}", "\u{1F37D}\u{FE0F}"]
                                let currentIdx = emojis.firstIndex(of: list.emoji) ?? -1
                                let nextEmoji = emojis[((currentIdx) + 1) % emojis.count]
                                await savedListsService.updateEmoji(list, emoji: nextEmoji)
                            }
                        } label: {
                            Label("Change Emoji", systemImage: "face.smiling")
                        }

                        Divider()

                        Button(role: .destructive) {
                            listToDelete = list
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.top, SonderSpacing.sm)
            .padding(.bottom, 80)
        }
        .background(SonderColors.cream)
        .navigationTitle("Saved Lists")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $activeDestination) { dest in
            switch dest {
            case .allPlaces:
                WantToGoListView()
            case .list(let id, let name):
                WantToGoListView(listID: id, listName: name)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Rename List", isPresented: Binding(
            get: { listToRename != nil },
            set: { if !$0 { listToRename = nil } }
        )) {
            TextField("List name", text: $renameText)
            Button("Cancel", role: .cancel) { listToRename = nil }
            Button("Rename") {
                if let list = listToRename {
                    Task { await savedListsService.renameList(list, newName: renameText) }
                }
                listToRename = nil
            }
        }
        .alert("Delete List?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { listToDelete = nil }
            Button("Delete", role: .destructive) {
                if let list = listToDelete, let userID {
                    Task { await savedListsService.deleteList(list, userID: userID) }
                }
                listToDelete = nil
            }
        } message: {
            if let list = listToDelete {
                let count = savedListsService.placeCount(for: list.id, userID: userID ?? "")
                Text("This will delete \"\(list.name)\" and remove \(count) saved place\(count == 1 ? "" : "s").")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createListSheet
        }
        .task {
            if let userID {
                await savedListsService.fetchLists(for: userID)
            }
        }
    }

    // MARK: - All Places Row

    private var allPlacesRow: some View {
        let totalCount = userID.map { uid in Set(wantToGoService.items.filter { $0.userID == uid }.map(\.placeID)).count } ?? 0

        return HStack(spacing: SonderSpacing.sm) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 16))
                .foregroundStyle(SonderColors.terracotta)
                .frame(width: 40, height: 40)
                .background(SonderColors.terracotta.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("All Saved Places")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                Text("\(totalCount) place\(totalCount == 1 ? "" : "s")")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SonderColors.inkLight)
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Saved List Card

    private func savedListCard(_ list: SavedList) -> some View {
        let count = wantToGoService.items.filter { $0.userID == (userID ?? "") && $0.listID == list.id }.count

        return HStack(spacing: SonderSpacing.sm) {
            Text(list.emoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(SonderColors.terracotta.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.inkDark)

                Text("\(count) place\(count == 1 ? "" : "s")")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SonderColors.inkLight)
        }
        .padding(SonderSpacing.md)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Create List Sheet

    private var createListSheet: some View {
        NavigationStack {
            VStack(spacing: SonderSpacing.lg) {
                // Emoji picker
                Button {
                    let emojis = ["\u{1F516}", "\u{2764}\u{FE0F}", "\u{1F355}", "\u{2615}", "\u{1F378}", "\u{1F3D6}\u{FE0F}", "\u{1F30E}", "\u{1F37D}\u{FE0F}"]
                    if let idx = emojis.firstIndex(of: newListEmoji) {
                        newListEmoji = emojis[(idx + 1) % emojis.count]
                    } else {
                        newListEmoji = emojis[0]
                    }
                } label: {
                    Text(newListEmoji)
                        .font(.system(size: 48))
                        .frame(width: 80, height: 80)
                        .background(SonderColors.terracotta.opacity(0.15))
                        .clipShape(Circle())
                }

                Text("Tap to change emoji")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)

                TextField("List name", text: $newListName)
                    .font(SonderTypography.title)
                    .multilineTextAlignment(.center)
                    .padding(SonderSpacing.md)
                    .background(SonderColors.warmGray)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

                Spacer()
            }
            .padding(SonderSpacing.lg)
            .background(SonderColors.cream)
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showCreateSheet = false
                        newListName = ""
                        newListEmoji = "\u{1F516}"
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createList()
                    }
                    .fontWeight(.semibold)
                    .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createList() {
        guard let userID else { return }
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            _ = await savedListsService.createList(name: name, emoji: newListEmoji, userID: userID)
            showCreateSheet = false
            newListName = ""
            newListEmoji = "\u{1F516}"
        }
    }
}

// MARK: - Navigation Destination

enum SavedListDestination: Hashable {
    case allPlaces
    case list(id: String, name: String)
}
