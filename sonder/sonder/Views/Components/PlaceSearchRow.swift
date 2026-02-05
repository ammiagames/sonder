//
//  PlaceSearchRow.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Row component for displaying a place search result
struct PlaceSearchRow: View {
    let name: String
    let address: String
    let photoReference: String?
    let icon: String?

    init(name: String, address: String, photoReference: String? = nil, icon: String? = nil) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            // Photo or icon
            if photoReference != nil {
                PlacePhotoView(photoReference: photoReference, size: 44, cornerRadius: 8)
            } else {
                Image(systemName: icon ?? "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Place info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !address.isEmpty {
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

/// Row for recent search with delete action
struct RecentSearchRow: View {
    let name: String
    let address: String
    let photoReference: String?
    let onDelete: () -> Void

    init(name: String, address: String, photoReference: String? = nil, onDelete: @escaping () -> Void) {
        self.name = name
        self.address = address
        self.photoReference = photoReference
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(spacing: 12) {
            // Photo with clock badge
            ZStack(alignment: .bottomTrailing) {
                PlacePhotoView(photoReference: photoReference, size: 44, cornerRadius: 8)

                // Clock badge overlay
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.secondary)
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }

            // Place info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !address.isEmpty {
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

#Preview("Search Result") {
    VStack(spacing: 0) {
        PlaceSearchRow(
            name: "Blue Bottle Coffee",
            address: "123 Main St, San Francisco, CA"
        )
        Divider().padding(.leading, 68)
        PlaceSearchRow(
            name: "Tartine Bakery",
            address: "600 Guerrero St, San Francisco, CA",
            icon: "fork.knife"
        )
    }
    .background(Color(.systemBackground))
}

#Preview("Recent Search") {
    RecentSearchRow(
        name: "Philz Coffee",
        address: "748 Van Ness Ave"
    ) {
        print("Delete tapped")
    }
    .background(Color(.systemBackground))
}
