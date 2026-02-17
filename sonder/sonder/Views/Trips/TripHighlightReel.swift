//
//  TripHighlightReel.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Must-See only collection — the confident, curated recommendations view.
struct TripHighlightReel: View {
    @Environment(\.dismiss) private var dismiss

    let tripName: String
    let logs: [Log]
    let places: [Place]

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var mustSees: [(log: Log, place: Place)] {
        logs.filter { $0.rating == .mustSee }
            .sorted { $0.visitedAt < $1.visitedAt }
            .compactMap { log in
                guard let place = placesByID[log.placeID] else { return nil }
                return (log: log, place: place)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        Text("THE HIGHLIGHTS")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(4.0)
                            .foregroundColor(SonderColors.inkLight)

                        Text(tripName)
                            .font(.system(size: 32, weight: .light, design: .serif))
                            .foregroundColor(SonderColors.inkDark)
                            .multilineTextAlignment(.center)

                        Text("\(mustSees.count) must-see \(mustSees.count == 1 ? "place" : "places")")
                            .font(.system(size: 14))
                            .foregroundColor(SonderColors.terracotta)
                    }
                    .padding(.vertical, 48)
                    .padding(.horizontal, 24)

                    if mustSees.isEmpty {
                        emptyState
                    } else {
                        // Entries — big, bold, confident
                        LazyVStack(spacing: 64) {
                            ForEach(Array(mustSees.enumerated()), id: \.element.log.id) { index, item in
                                highlightEntry(log: item.log, place: item.place, index: index)
                                    .scrollTransition(.animated(.easeOut(duration: 0.4))) { content, phase in
                                        content
                                            .opacity(phase.isIdentity ? 1 : 0)
                                            .offset(y: phase.isIdentity ? 0 : 30)
                                    }
                            }
                        }

                        // Footer
                        VStack(spacing: 12) {
                            Rectangle()
                                .fill(SonderColors.warmGrayDark.opacity(0.3))
                                .frame(width: 40, height: 1)

                            Text("Only the best.")
                                .font(.system(size: 16, weight: .light, design: .serif))
                                .italic()
                                .foregroundColor(SonderColors.inkMuted)

                            Text("sonder")
                                .font(.system(size: 11, weight: .light, design: .serif))
                                .tracking(3.0)
                                .foregroundColor(SonderColors.inkLight)
                        }
                        .padding(.vertical, 64)
                    }
                }
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
                    }
                }
            }
        }
    }

    // MARK: - Highlight Entry

    private func highlightEntry(log: Log, place: Place, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Full-bleed photo
            entryPhoto(log: log, place: place)
                .aspectRatio(4/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            // Large editorial text
            VStack(alignment: .leading, spacing: 12) {
                // Big place name
                Text(place.name)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .padding(.top, 16)

                // Short address
                let shortAddr = place.address.components(separatedBy: ", ").prefix(2).joined(separator: ", ")
                Text(shortAddr)
                    .font(.system(size: 13))
                    .foregroundColor(SonderColors.inkMuted)

                // The note — given generous space
                if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundColor(SonderColors.inkDark)
                        .lineSpacing(8)
                        .padding(.top, 4)
                }

                // Tags
                if !log.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(log.tags.prefix(5), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11))
                                .foregroundColor(SonderColors.terracotta)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(SonderColors.terracotta.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Photo

    @ViewBuilder
    private func entryPhoto(log: Log, place: Place) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 450)) {
                placeFallbackPhoto(place: place)
            }
        } else {
            placeFallbackPhoto(place: place)
        }
    }

    @ViewBuilder
    private func placeFallbackPhoto(place: Place) -> some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 450)) {
                Rectangle().fill(SonderColors.warmGray)
            }
        } else {
            Rectangle()
                .fill(SonderColors.warmGray)
                .frame(height: 200)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(SonderColors.inkLight)
            Text("No must-sees yet")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundColor(SonderColors.inkMuted)
            Text("Rate a place Must-See to see it here")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)
        }
        .padding(.vertical, 80)
    }
}
