//
//  TripPostcardStack.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// A stack of postcards — swipe to throw, tap to flip between photo and note.
struct TripPostcardStack: View {
    @Environment(\.dismiss) private var dismiss

    let tripName: String
    let logs: [Log]
    let places: [Place]

    @State private var currentIndex = 0
    @State private var flipped: Set<Int> = []
    @State private var dragOffset: CGSize = .zero
    @State private var dragRotation: Double = 0

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var sortedLogs: [Log] {
        logs.sorted { $0.visitedAt < $1.visitedAt }
    }

    var body: some View {
        ZStack {
            SonderColors.cream.ignoresSafeArea()

            // Stack indicator
            VStack {
                Spacer()
                Text("\(currentIndex + 1) of \(sortedLogs.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(SonderColors.inkLight)
                    .padding(.bottom, 40)
            }

            // Card stack — show current + next 2 underneath
            ForEach(Array(sortedLogs.enumerated().reversed()), id: \.element.id) { index, log in
                if index >= currentIndex && index < currentIndex + 3 {
                    let place = placesByID[log.placeID]
                    let isTop = index == currentIndex
                    let depth = index - currentIndex
                    let isFlipped = flipped.contains(index)

                    postcardView(log: log, place: place, index: index, isFlipped: isFlipped)
                        .frame(width: 320, height: 440)
                        .rotation3DEffect(
                            .degrees(isFlipped ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.5
                        )
                        .scaleEffect(isTop ? 1.0 : 1.0 - Double(depth) * 0.04)
                        .offset(y: isTop ? 0 : CGFloat(depth) * 8)
                        .rotationEffect(.degrees(isTop ? seedRotation(for: index) + dragRotation : seedRotation(for: index)))
                        .offset(isTop ? dragOffset : .zero)
                        .zIndex(Double(sortedLogs.count - index))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentIndex)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isFlipped)
                        .gesture(isTop ? dragGesture(index: index) : nil)
                        .onTapGesture {
                            guard isTop else { return }
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                if flipped.contains(index) {
                                    flipped.remove(index)
                                } else {
                                    flipped.insert(index)
                                }
                            }
                        }
                }
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
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }

    // MARK: - Postcard View

    @ViewBuilder
    private func postcardView(log: Log, place: Place?, index: Int, isFlipped: Bool) -> some View {
        if isFlipped {
            postcardBack(log: log, place: place, index: index)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        } else {
            postcardFront(log: log, place: place)
        }
    }

    private func postcardFront(log: Log, place: Place?) -> some View {
        ZStack(alignment: .bottom) {
            // Photo
            if let urlString = log.photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 640, height: 880)) {
                    placeholderPhoto(place: place)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 320, height: 440)
                .clipped()
            } else {
                placeholderPhoto(place: place)
            }

            // Subtle bottom gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.4)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Place name at bottom
            VStack(alignment: .leading, spacing: 4) {
                Text(place?.name ?? "Unknown Place")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
                Text(log.rating.emoji + " " + log.rating.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            Text("TAP TO FLIP")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(12)
        }
    }

    private func postcardBack(log: Log, place: Place?, index: Int) -> some View {
        VStack(spacing: 0) {
            // Postmark area
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place?.name ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SonderColors.inkMuted)
                    if let place {
                        Text(simplifiedAddress(place.address))
                            .font(.system(size: 10))
                            .foregroundColor(SonderColors.inkLight)
                    }
                }
                Spacer()
                // Faux postmark stamp
                dateStamp(for: log.visitedAt)
            }
            .padding(20)

            Divider()
                .background(SonderColors.warmGrayDark.opacity(0.3))

            // Note content
            VStack(alignment: .leading, spacing: 16) {
                if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundColor(SonderColors.inkDark)
                        .lineSpacing(8)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No note for this stop.")
                        .font(.system(size: 15, design: .serif))
                        .foregroundColor(SonderColors.inkLight)
                        .italic()
                }

                Spacer()

                // Rating
                HStack(spacing: 6) {
                    Text(log.rating.emoji)
                        .font(.system(size: 20))
                    Text(log.rating.displayName)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(SonderColors.pinColor(for: log.rating))
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
            }
            .padding(20)

            Spacer(minLength: 0)

            // Bottom branding
            Text("sonder")
                .font(.system(size: 11, weight: .light, design: .serif))
                .tracking(3.0)
                .foregroundColor(SonderColors.inkLight)
                .padding(.bottom, 16)
        }
        .frame(width: 320, height: 440)
        .background(SonderColors.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    // MARK: - Date Stamp

    private func dateStamp(for date: Date) -> some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
            Text(date.formatted(.dateTime.month(.abbreviated).year()).uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.0)
        }
        .foregroundColor(SonderColors.terracotta)
        .padding(10)
        .overlay {
            Circle()
                .stroke(SonderColors.terracotta.opacity(0.3), lineWidth: 1.5)
                .frame(width: 56, height: 56)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func placeholderPhoto(place: Place?) -> some View {
        if let photoRef = place?.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 600) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 640, height: 880)) {
                gradientPlaceholder
            }
        } else {
            gradientPlaceholder
        }
    }

    private var gradientPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.4), SonderColors.ochre.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.4))
            }
    }

    private func seedRotation(for index: Int) -> Double {
        let seed = Double(index * 7 + 3)
        return sin(seed) * 2.5
    }

    private func simplifiedAddress(_ address: String) -> String {
        let parts = address.components(separatedBy: ", ")
        return parts.prefix(2).joined(separator: ", ")
    }

    private func dragGesture(index: Int) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                dragRotation = Double(value.translation.width) / 20
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if abs(value.translation.width) > threshold {
                    // Throw card off screen
                    let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: direction * 500, height: value.translation.height)
                        dragRotation = Double(direction) * 15
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dragOffset = .zero
                        dragRotation = 0
                        if currentIndex < sortedLogs.count - 1 {
                            currentIndex += 1
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = .zero
                        dragRotation = 0
                    }
                }
            }
    }
}
