//
//  FeedItemCard.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Card showing a friend's log in the feed with save button
struct FeedItemCard: View {
    let feedItem: FeedItem
    let isWantToGo: Bool
    let onUserTap: () -> Void
    let onPlaceTap: () -> Void
    let onWantToGoTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: User info
            userHeader

            // Photo
            photoSection

            // Content: Place name, rating, note
            contentSection

            // Footer: Date and Want to Go button
            footerSection
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    // MARK: - User Header

    private var userHeader: some View {
        Button(action: onUserTap) {
            HStack(spacing: 10) {
                // Avatar
                if let urlString = feedItem.user.avatarURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder
                }

                // Username
                Text(feedItem.user.username)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay {
                Text(feedItem.user.username.prefix(1).uppercased())
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        Button(action: onPlaceTap) {
            ZStack(alignment: .bottomTrailing) {
                // Photo
                if let urlString = feedItem.log.photoURL,
                   let url = URL(string: urlString) {
                    // User's photo
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            placePhoto
                        }
                    }
                } else {
                    placePhoto
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = feedItem.place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
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
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Place name and rating
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feedItem.place.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text(feedItem.place.address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Rating badge
                Text(feedItem.rating.emoji)
                    .font(.title2)
            }

            // Note
            if let note = feedItem.log.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Tags
            if !feedItem.log.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(feedItem.log.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            // Date
            Text(feedItem.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Want to Go button
            Button(action: onWantToGoTap) {
                Image(systemName: isWantToGo ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(isWantToGo ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

#Preview {
    ScrollView {
        FeedItemCard(
            feedItem: FeedItem(
                id: "1",
                log: FeedItem.FeedLog(
                    id: "1",
                    rating: "must_see",
                    photoURL: nil,
                    note: "Amazing coffee! The pour-over was exceptional and the staff was super friendly.",
                    tags: ["coffee", "cafe"],
                    createdAt: Date()
                ),
                user: FeedItem.FeedUser(
                    id: "user1",
                    username: "johndoe",
                    avatarURL: nil,
                    isPublic: true
                ),
                place: FeedItem.FeedPlace(
                    id: "place1",
                    name: "Blue Bottle Coffee",
                    address: "123 Main St, San Francisco, CA",
                    latitude: 37.7749,
                    longitude: -122.4194,
                    photoReference: nil
                )
            ),
            isWantToGo: false,
            onUserTap: {},
            onPlaceTap: {},
            onWantToGoTap: {}
        )
        .padding()
    }
}
