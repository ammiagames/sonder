//
//  ExploreFilterSheet.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI

/// Filter sheet for Explore map — Category applies to all pins,
/// friends-specific filters (rating, recency, loved) only apply to friend logs.
struct ExploreFilterSheet: View {
    @Binding var filter: ExploreMapFilter
    var availableTags: [String] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(ExploreMapService.self) private var exploreMapService
    @Environment(SavedListsService.self) private var savedListsService

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Layers
                Section {
                    Toggle(isOn: $filter.showMyPlaces) {
                        Label("My Places", systemImage: "mappin.circle.fill")
                    }
                    .tint(SonderColors.terracotta)

                    Toggle(isOn: $filter.showFriendsPlaces) {
                        Label("Friends' Places", systemImage: "person.2.fill")
                    }
                    .tint(SonderColors.terracotta)
                } header: {
                    Text("Layers")
                }

                // MARK: - Friends Picker
                if filter.showFriendsPlaces, !exploreMapService.allFriends.isEmpty {
                    Section {
                        friendPickerGrid
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: {
                        HStack {
                            Text("Friends")
                            Spacer()
                            if !filter.selectedFriendIDs.isEmpty {
                                Button("Show All") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        filter.selectedFriendIDs = []
                                    }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SonderColors.terracotta)
                            }
                        }
                    }
                }

                // MARK: - Category (applies to all pins)
                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        // "All" button
                        let allSelected = filter.categories.isEmpty
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filter.selectAllCategories()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 20))
                                Text("All")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SonderSpacing.sm)
                            .background(allSelected ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                            .foregroundStyle(allSelected ? SonderColors.terracotta : SonderColors.inkDark)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                            .overlay {
                                if allSelected {
                                    RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                        .stroke(SonderColors.terracotta, lineWidth: 1.5)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Individual categories
                        ForEach(ExploreMapFilter.CategoryFilter.allCases, id: \.self) { cat in
                            let isSelected = filter.categories.contains(cat)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    filter.toggleCategory(cat)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Image(systemName: cat.icon)
                                            .font(.system(size: 20))
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(SonderColors.terracotta)
                                                .transition(.scale.combined(with: .opacity))
                                                .offset(x: 14, y: -10)
                                        }
                                    }
                                    Text(cat.label)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SonderSpacing.sm)
                                .background(isSelected ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                                .foregroundStyle(isSelected ? SonderColors.terracotta : SonderColors.inkDark)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                            .stroke(SonderColors.terracotta, lineWidth: 1.5)
                                            .transition(.opacity)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Category")
                }

                // MARK: - Tags
                if !availableTags.isEmpty {
                    Section {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { filter.selectedTags = [] }
                            } label: {
                                tagChip("All", selected: filter.selectedTags.isEmpty)
                            }
                            .buttonStyle(.plain)

                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { toggleTag(tag) }
                                } label: {
                                    tagChip(tag, selected: filter.selectedTags.contains(tag))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: {
                        HStack {
                            Text("Tags")
                            Spacer()
                            if !filter.selectedTags.isEmpty {
                                Button("Show All") {
                                    withAnimation(.easeInOut(duration: 0.2)) { filter.selectedTags = [] }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SonderColors.terracotta)
                            }
                        }
                    }
                }

                // MARK: - Rating (friends' places)
                Section {
                    ForEach(ExploreMapFilter.RatingFilter.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filter.rating = option
                            }
                        } label: {
                            HStack {
                                ratingIcon(for: option)
                                Text(option.label)
                                    .foregroundStyle(SonderColors.inkDark)
                                Spacer()
                                if filter.rating == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SonderColors.terracotta)
                                        .fontWeight(.semibold)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Rating")
                }

                // MARK: - Time Period (friends' places)
                Section {
                    ForEach(ExploreMapFilter.RecencyFilter.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                filter.recency = option
                            }
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(SonderColors.inkDark)
                                Spacer()
                                if filter.recency == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SonderColors.terracotta)
                                        .fontWeight(.semibold)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Time Period")
                }

                // MARK: - Saved Lists
                Section {
                    Toggle(isOn: $filter.showWantToGo) {
                        Label("Show Saved Places", systemImage: "bookmark")
                    }
                    .tint(SonderColors.terracotta)

                    if filter.showWantToGo {
                        savedListsPickerGrid
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } header: {
                    HStack {
                        Text("Saved Lists")
                        Spacer()
                        if !filter.selectedSavedListIDs.isEmpty {
                            Button("Show All") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    filter.selectedSavedListIDs = []
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SonderColors.terracotta)
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if filter.isActive {
                        Button("Reset") {
                            withAnimation {
                                filter = ExploreMapFilter()
                            }
                        }
                        .foregroundStyle(SonderColors.terracotta)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Friend Picker Grid

    private var friendPickerGrid: some View {
        let friends = exploreMapService.allFriends
        let allSelected = filter.selectedFriendIDs.isEmpty

        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 10) {
            ForEach(friends, id: \.id) { friend in
                let isSelected = allSelected || filter.selectedFriendIDs.contains(friend.id)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleFriend(friend.id)
                    }
                } label: {
                    VStack(spacing: 6) {
                        friendAvatar(friend, size: 36)
                            .opacity(isSelected ? 1.0 : 0.4)

                        Text(friend.username)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(isSelected && !allSelected ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                    .foregroundStyle(isSelected ? SonderColors.inkDark : SonderColors.inkLight)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    .overlay {
                        if isSelected && !allSelected {
                            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                .stroke(SonderColors.terracotta, lineWidth: 1.5)
                                .transition(.opacity)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Saved Lists Picker Grid

    private var savedListsPickerGrid: some View {
        let lists = savedListsService.lists
        let allSelected = filter.selectedSavedListIDs.isEmpty

        return Group {
            if lists.isEmpty {
                Text("No saved lists yet")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ForEach(lists, id: \.id) { list in
                        let isSelected = allSelected || filter.selectedSavedListIDs.contains(list.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                toggleSavedList(list.id)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Text(list.emoji)
                                    .font(.system(size: 20))
                                    .opacity(isSelected ? 1.0 : 0.4)

                                Text(list.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SonderSpacing.sm)
                            .background(isSelected && !allSelected ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                            .foregroundStyle(isSelected ? SonderColors.inkDark : SonderColors.inkLight)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                            .overlay {
                                if isSelected && !allSelected {
                                    RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                        .stroke(SonderColors.terracotta, lineWidth: 1.5)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggleSavedList(_ listID: String) {
        let allListIDs = Set(savedListsService.lists.map(\.id))

        if filter.selectedSavedListIDs.isEmpty {
            // "All" is active → switch to single-deselect
            filter.selectedSavedListIDs = allListIDs
            filter.selectedSavedListIDs.remove(listID)
        } else if filter.selectedSavedListIDs.contains(listID) {
            filter.selectedSavedListIDs.remove(listID)
            // If none left, go back to "All"
        } else {
            filter.selectedSavedListIDs.insert(listID)
            // If all lists are now selected, reset to "All"
            if filter.selectedSavedListIDs == allListIDs {
                filter.selectedSavedListIDs = []
            }
        }
    }

    private func toggleFriend(_ friendID: String) {
        if filter.selectedFriendIDs.isEmpty {
            // "All" is active → switching to single-select this friend
            let allIDs = Set(exploreMapService.allFriends.map(\.id))
            filter.selectedFriendIDs = allIDs
            filter.selectedFriendIDs.remove(friendID)
        } else if filter.selectedFriendIDs.contains(friendID) {
            filter.selectedFriendIDs.remove(friendID)
            // If none left, go back to "All"
            if filter.selectedFriendIDs.isEmpty {
                // Already empty = show all, which is the desired behavior
            }
        } else {
            filter.selectedFriendIDs.insert(friendID)
            // If all friends are now selected, reset to "All"
            if filter.selectedFriendIDs == Set(exploreMapService.allFriends.map(\.id)) {
                filter.selectedFriendIDs = []
            }
        }
    }

    private func tagChip(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SonderSpacing.sm)
            .background(selected ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
            .foregroundStyle(selected ? SonderColors.terracotta : SonderColors.inkDark)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                        .stroke(SonderColors.terracotta, lineWidth: 1.5)
                        .transition(.opacity)
                }
            }
    }

    private func toggleTag(_ tag: String) {
        if filter.selectedTags.isEmpty {
            filter.selectedTags = [tag]
        } else if filter.selectedTags.contains(tag) {
            filter.selectedTags.remove(tag)
        } else {
            filter.selectedTags.insert(tag)
            if filter.selectedTags == Set(availableTags) {
                filter.selectedTags = []
            }
        }
    }

    @ViewBuilder
    private func friendAvatar(_ user: FeedItem.FeedUser, size: CGFloat) -> some View {
        if let urlString = user.avatarURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: size * 2, height: size * 2)) {
                friendAvatarPlaceholder(user, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            friendAvatarPlaceholder(user, size: size)
        }
    }

    private func friendAvatarPlaceholder(_ user: FeedItem.FeedUser, size: CGFloat) -> some View {
        Circle()
            .fill(SonderColors.warmGrayDark)
            .frame(width: size, height: size)
            .overlay {
                Text(user.username.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.inkMuted)
            }
    }

    private func ratingIcon(for option: ExploreMapFilter.RatingFilter) -> some View {
        Group {
            switch option {
            case .all:
                Image(systemName: "star")
                    .foregroundStyle(SonderColors.inkMuted)
            case .okayPlus:
                Text("\u{1F44C}")
            case .greatPlus:
                Text("\u{2B50}")
            case .mustSeeOnly:
                Text("\u{1F525}")
            }
        }
    }
}

// MARK: - Active Filter Count

extension ExploreMapFilter {
    var activeCount: Int {
        var count = 0
        if !showMyPlaces { count += 1 }
        if !showFriendsPlaces { count += 1 }
        if !showWantToGo { count += 1 }
        if rating != .all { count += 1 }
        count += categories.count
        if recency != .allTime { count += 1 }
        if !selectedFriendIDs.isEmpty { count += 1 }
        if !selectedSavedListIDs.isEmpty { count += 1 }
        if !selectedTags.isEmpty { count += 1 }
        return count
    }

    /// Short labels for active filters
    var activeLabels: [(id: String, label: String)] {
        var labels: [(id: String, label: String)] = []
        if !showMyPlaces { labels.append((id: "myPlaces", label: "My Places Off")) }
        if !showFriendsPlaces { labels.append((id: "friendsPlaces", label: "Friends Off")) }
        if !showWantToGo { labels.append((id: "wantToGo", label: "Saved Off")) }
        if rating != .all { labels.append((id: "rating", label: rating.label)) }
        for cat in categories.sorted(by: { $0.label < $1.label }) {
            labels.append((id: "category-\(cat.label)", label: cat.label))
        }
        if recency != .allTime { labels.append((id: "recency", label: recency.label)) }
        if !selectedFriendIDs.isEmpty {
            labels.append((id: "friends", label: "\(selectedFriendIDs.count) friend\(selectedFriendIDs.count == 1 ? "" : "s")"))
        }
        if !selectedSavedListIDs.isEmpty {
            labels.append((id: "savedLists", label: "\(selectedSavedListIDs.count) list\(selectedSavedListIDs.count == 1 ? "" : "s")"))
        }
        if !selectedTags.isEmpty {
            labels.append((id: "tags", label: "\(selectedTags.count) tag\(selectedTags.count == 1 ? "" : "s")"))
        }
        return labels
    }

    /// Remove a specific active filter by id
    mutating func removeFilter(id: String) {
        switch id {
        case "rating": rating = .all
        case "recency": recency = .allTime
        case "myPlaces": showMyPlaces = true
        case "friendsPlaces": showFriendsPlaces = true
        case "wantToGo": showWantToGo = true
        case "friends": selectedFriendIDs = []
        case "savedLists": selectedSavedListIDs = []
        case "tags": selectedTags = []
        default:
            if id.hasPrefix("category-") {
                let label = String(id.dropFirst("category-".count))
                categories = categories.filter { $0.label != label }
            }
        }
    }
}
