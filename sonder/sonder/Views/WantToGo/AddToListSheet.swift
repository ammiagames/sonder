//
//  AddToListSheet.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "AddToListSheet")

/// Half-sheet for adding/removing a place to/from saved lists.
/// Tap toggles membership immediately (no "Save" button).
struct AddToListSheet: View {
    let placeID: String
    let placeName: String?
    let placeAddress: String?
    let photoReference: String?
    let sourceLogID: String?

    @Environment(AuthenticationService.self) private var authService
    @Environment(WantToGoService.self) private var wantToGoService
    @Environment(SavedListsService.self) private var savedListsService
    @Environment(\.dismiss) private var dismiss

    @State private var isCreatingList = false
    @State private var newListName = ""
    @State private var newListEmoji = "\u{2B50}\u{FE0F}"
    @FocusState private var isNewListFocused: Bool

    private var userID: String? { authService.currentUser?.id }

    private var isSaved: Bool {
        guard let userID else { return false }
        return wantToGoService.isInWantToGo(placeID: placeID, userID: userID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.sm) {
                    // List rows
                    ForEach(savedListsService.lists, id: \.id) { list in
                        listRow(list)
                    }

                    // New list creation
                    if isCreatingList {
                        newListRow
                    } else {
                        createListButton
                    }

                    // Remove from saved
                    if isSaved {
                        Button(role: .destructive) {
                            unsaveCompletely()
                        } label: {
                            HStack(spacing: SonderSpacing.sm) {
                                Image(systemName: "bookmark.slash.fill")
                                    .font(.system(size: 16))
                                Text("Remove from Saved")
                                    .font(SonderTypography.headline)
                            }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(SonderSpacing.sm)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, SonderSpacing.xs)
                    }
                }
                .padding(.horizontal, SonderSpacing.md)
                .padding(.top, SonderSpacing.sm)
                .padding(.bottom, 80)
            }
            .background(SonderColors.cream)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Save to...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - List Row

    private func listRow(_ list: SavedList) -> some View {
        let isInList = wantToGoService.isInList(placeID: placeID, userID: userID ?? "", listID: list.id)

        return Button {
            toggleMembership(list: list, isCurrentlyIn: isInList)
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Emoji circle
                Text(list.emoji)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(Circle())

                // Name + count
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(SonderTypography.headline)
                        .foregroundStyle(SonderColors.inkDark)

                    let count = savedListsService.placeCount(for: list.id, userID: userID ?? "")
                    Text("\(count) place\(count == 1 ? "" : "s")")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                }

                Spacer()

                // Checkmark
                if isInList {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SonderColors.terracotta)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .stroke(SonderColors.inkLight, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create List

    private var createListButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCreatingList = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                isNewListFocused = true
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(SonderColors.terracotta)

                Text("New List")
                    .font(SonderTypography.headline)
                    .foregroundStyle(SonderColors.terracotta)

                Spacer()
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.terracotta.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
        .buttonStyle(.plain)
    }

    private var newListRow: some View {
        HStack(spacing: SonderSpacing.sm) {
            // Emoji picker button
            Button {
                // Cycle through common emojis
                let emojis = ["\u{2B50}\u{FE0F}", "\u{2764}\u{FE0F}", "\u{1F355}", "\u{2615}", "\u{1F3D6}\u{FE0F}", "\u{1F389}", "\u{1F30E}", "\u{1F37D}\u{FE0F}"]
                if let idx = emojis.firstIndex(of: newListEmoji) {
                    newListEmoji = emojis[(idx + 1) % emojis.count]
                } else {
                    newListEmoji = emojis[0]
                }
            } label: {
                Text(newListEmoji)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(SonderColors.terracotta.opacity(0.15))
                    .clipShape(Circle())
            }

            TextField("List name", text: $newListName)
                .font(SonderTypography.headline)
                .focused($isNewListFocused)
                .onSubmit { createNewList() }

            Spacer()

            if !newListName.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    createNewList()
                } label: {
                    Text("Add")
                        .font(SonderTypography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.terracotta)
                        .clipShape(Capsule())
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCreatingList = false
                    newListName = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
    }

    // MARK: - Actions

    private func toggleMembership(list: SavedList, isCurrentlyIn: Bool) {
        guard let userID else { return }

        Task {
            do {
                if isCurrentlyIn {
                    try await wantToGoService.removeFromWantToGo(placeID: placeID, userID: userID, listID: list.id)
                } else {
                    try await wantToGoService.addToWantToGo(
                        placeID: placeID,
                        userID: userID,
                        placeName: placeName,
                        placeAddress: placeAddress,
                        photoReference: photoReference,
                        sourceLogID: sourceLogID,
                        listID: list.id
                    )
                }
                SonderHaptics.impact(.light)
            } catch {
                logger.error("Error toggling list membership: \(error.localizedDescription)")
            }
        }
    }

    private func unsaveCompletely() {
        guard let userID else { return }

        Task {
            do {
                try await wantToGoService.removeFromWantToGo(placeID: placeID, userID: userID)
                SonderHaptics.notification(.success)
                dismiss()
            } catch {
                logger.error("Error unsaving place: \(error.localizedDescription)")
            }
        }
    }

    private func createNewList() {
        guard let userID else { return }
        let name = newListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        Task {
            if let newList = await savedListsService.createList(name: name, emoji: newListEmoji, userID: userID) {
                // Auto-add place to the new list
                try? await wantToGoService.addToWantToGo(
                    placeID: placeID,
                    userID: userID,
                    placeName: placeName,
                    placeAddress: placeAddress,
                    photoReference: photoReference,
                    sourceLogID: sourceLogID,
                    listID: newList.id
                )
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                isCreatingList = false
                newListName = ""
                newListEmoji = "\u{2B50}\u{FE0F}"
            }

            SonderHaptics.notification(.success)
        }
    }
}
