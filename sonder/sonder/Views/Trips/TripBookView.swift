//
//  TripBookView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Horizontal page-turn book experience. Each spread: left page = photo, right page = editorial text.
struct TripBookView: View {
    @Environment(\.dismiss) private var dismiss

    let tripName: String
    let logs: [Log]
    let places: [Place]
    let coverPhotoURL: String?

    @State private var currentPage = 0

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var sortedLogs: [Log] {
        logs.sorted { $0.visitedAt < $1.visitedAt }
    }

    /// Total pages: cover + one per log + back cover
    private var totalPages: Int { sortedLogs.count + 2 }

    var body: some View {
        ZStack {
            SonderColors.cream.ignoresSafeArea()

            TabView(selection: $currentPage) {
                // Cover page
                bookCover.tag(0)

                // Content pages — each log is a spread
                ForEach(Array(sortedLogs.enumerated()), id: \.element.id) { index, log in
                    let place = placesByID[log.placeID]
                    bookSpread(log: log, place: place, pageNumber: index + 1)
                        .tag(index + 1)
                }

                // Back cover
                backCover.tag(sortedLogs.count + 1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Page indicator
            VStack {
                Spacer()
                HStack {
                    if currentPage > 0 {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                            .foregroundColor(SonderColors.inkLight)
                    }

                    Text("\(currentPage + 1) / \(totalPages)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(SonderColors.inkLight)

                    if currentPage < totalPages - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }
                .padding(.bottom, 16)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SonderColors.inkDark)
                            .frame(width: 36, height: 36)
                            .background(SonderColors.warmGray)
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
        .onChange(of: currentPage) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Cover

    private var bookCover: some View {
        GeometryReader { geo in
            ZStack {
                // Warm linen texture background
                SonderColors.warmGray

                VStack(spacing: 20) {
                    Spacer()

                    // Cover photo inset (like a real book cover)
                    if let urlString = coverPhotoURL ?? sortedLogs.first?.photoURL,
                       let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 500, height: 340)) {
                            Rectangle().fill(SonderColors.warmGrayDark)
                        }
                        .frame(width: min(geo.size.width - 80, 300), height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    }

                    // Title
                    Text(tripName)
                        .font(.system(size: 32, weight: .light, design: .serif))
                        .foregroundColor(SonderColors.inkDark)
                        .multilineTextAlignment(.center)

                    // Thin rule
                    Rectangle()
                        .fill(SonderColors.terracotta.opacity(0.4))
                        .frame(width: 32, height: 1)

                    // Subtitle
                    if let first = sortedLogs.first {
                        Text(first.visitedAt.formatted(.dateTime.month(.wide).year()).uppercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(3.0)
                            .foregroundColor(SonderColors.inkLight)
                    }

                    Spacer()

                    // Small sonder mark
                    Text("sonder")
                        .font(.system(size: 11, weight: .light, design: .serif))
                        .tracking(3.0)
                        .foregroundColor(SonderColors.inkLight)
                        .padding(.bottom, 40)
                }
                .padding(40)
            }
        }
    }

    // MARK: - Content Spread

    private func bookSpread(log: Log, place: Place?, pageNumber: Int) -> some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            if isLandscape {
                // Landscape: side-by-side (true book spread)
                HStack(spacing: 0) {
                    // Left page — photo
                    spreadPhoto(log: log, place: place)
                        .frame(width: geo.size.width / 2, height: geo.size.height)
                        .clipped()

                    // Right page — text
                    spreadText(log: log, place: place, pageNumber: pageNumber)
                        .frame(width: geo.size.width / 2, height: geo.size.height)
                }
            } else {
                // Portrait: stacked (photo top, text bottom)
                ScrollView {
                    VStack(spacing: 0) {
                        // Photo
                        spreadPhoto(log: log, place: place)
                            .frame(height: geo.size.height * 0.45)
                            .frame(maxWidth: .infinity)
                            .clipped()

                        // Text
                        spreadText(log: log, place: place, pageNumber: pageNumber)
                            .frame(maxWidth: .infinity)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder
    private func spreadPhoto(log: Log, place: Place?) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 600)) {
                placeFallback(place: place)
            }
            .aspectRatio(contentMode: .fill)
        } else {
            placeFallback(place: place)
        }
    }

    @ViewBuilder
    private func placeFallback(place: Place?) -> some View {
        if let photoRef = place?.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 600)) {
                Rectangle().fill(SonderColors.warmGray)
            }
            .aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(SonderColors.warmGray)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(SonderColors.inkLight)
                }
        }
    }

    private func spreadText(log: Log, place: Place?, pageNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 24)

            // Page number
            Text("— \(pageNumber) —")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(SonderColors.inkLight)
                .frame(maxWidth: .infinity)

            // Place name
            Text(place?.name ?? "Unknown Place")
                .font(.system(size: 26, weight: .light, design: .serif))
                .foregroundColor(SonderColors.inkDark)

            // Rating
            HStack(spacing: 6) {
                Text(log.rating.emoji)
                    .font(.system(size: 16))
                Text(log.rating.displayName)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(SonderColors.pinColor(for: log.rating))
            }

            // Address — simplified
            if let address = place?.address {
                let short = address.components(separatedBy: ", ").prefix(2).joined(separator: ", ")
                Text(short)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }

            // Note — the star of the page
            if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(note)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .lineSpacing(8)
                    .italic()
                    .padding(.top, 8)
            }

            // Tags
            if !log.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(log.tags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11))
                            .foregroundColor(SonderColors.terracotta)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SonderColors.terracotta.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            // Date
            Text(log.visitedAt.formatted(date: .long, time: .omitted))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(SonderColors.inkLight)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 32)
        .background(SonderColors.cream)
    }

    // MARK: - Back Cover

    private var backCover: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("\(sortedLogs.count)")
                .font(.system(size: 72, weight: .bold, design: .serif))
                .foregroundColor(SonderColors.inkDark)

            Text("places explored".uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(2.0)
                .foregroundColor(SonderColors.inkLight)

            Rectangle()
                .fill(SonderColors.terracotta.opacity(0.3))
                .frame(width: 32, height: 1)

            // Rating breakdown
            VStack(spacing: 6) {
                let mustSeeCount = sortedLogs.filter { $0.rating == .mustSee }.count
                let solidCount = sortedLogs.filter { $0.rating == .solid }.count
                let skipCount = sortedLogs.filter { $0.rating == .skip }.count

                if mustSeeCount > 0 {
                    Text("\(Rating.mustSee.emoji) \(mustSeeCount) must-sees")
                        .font(.system(size: 15))
                        .foregroundColor(SonderColors.inkDark)
                }
                if solidCount > 0 {
                    Text("\(Rating.solid.emoji) \(solidCount) solid finds")
                        .font(.system(size: 15))
                        .foregroundColor(SonderColors.inkDark)
                }
                if skipCount > 0 {
                    Text("\(Rating.skip.emoji) \(skipCount) \(skipCount == 1 ? "skip" : "skips")")
                        .font(.system(size: 15))
                        .foregroundColor(SonderColors.inkDark)
                }
            }

            Spacer()

            Text("Until next time.")
                .font(.system(size: 18, weight: .light, design: .serif))
                .italic()
                .foregroundColor(SonderColors.inkMuted)

            Text("sonder")
                .font(.system(size: 13, weight: .light, design: .serif))
                .tracking(4.0)
                .foregroundColor(SonderColors.inkLight)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SonderColors.warmGray)
    }
}
