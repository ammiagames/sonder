//
//  TripCinematicView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Full-screen cinematic playback — auto-advancing photos with Ken Burns, subtitles, and day interstitials.
struct TripCinematicView: View {
    @Environment(\.dismiss) private var dismiss

    let tripName: String
    let logs: [Log]
    let places: [Place]
    let coverPhotoURL: String?

    @State private var currentSlide = -1 // -1 = title card
    @State private var isPlaying = true
    @State private var showSubtitle = false
    @State private var kenBurnsToggle = false
    @State private var timer: Timer?
    @State private var opacity: Double = 1.0

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var sortedLogs: [Log] {
        logs.sorted { $0.visitedAt < $1.visitedAt }
    }

    /// Build a slide deck: title card, then each log, then closing
    private var slides: [CinematicSlide] {
        var result: [CinematicSlide] = []

        // Title slide
        result.append(.title(name: tripName, photoURL: coverPhotoURL ?? sortedLogs.first?.photoURL))

        // Day interstitials + log slides
        var lastDay: Date?
        let calendar = Calendar.current
        for log in sortedLogs {
            let day = calendar.startOfDay(for: log.visitedAt)
            if day != lastDay {
                let dayNumber = result.filter { if case .dayTitle = $0 { return true }; return false }.count + 1
                result.append(.dayTitle(number: dayNumber, date: day))
                lastDay = day
            }
            result.append(.place(log: log, place: placesByID[log.placeID]))
        }

        // Closing
        result.append(.closing(placeCount: sortedLogs.count))
        return result
    }

    private var currentSlideData: CinematicSlide {
        if currentSlide < 0 { return slides[0] }
        if currentSlide >= slides.count { return slides[slides.count - 1] }
        return slides[currentSlide < 0 ? 0 : currentSlide]
    }

    private var slideDuration: TimeInterval {
        switch currentSlideData {
        case .title: return 4.0
        case .dayTitle: return 2.5
        case .place(let log, _):
            return (log.note?.isEmpty == false) ? 5.0 : 3.0
        case .closing: return 5.0
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Current slide content
            slideContent
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.8), value: currentSlide)

            // Subtitle overlay
            subtitleOverlay

            // Controls overlay
            controlsOverlay
        }
        .statusBarHidden()
        .onAppear { startPlayback() }
        .onDisappear { timer?.invalidate() }
        .onTapGesture { togglePlayback() }
    }

    // MARK: - Slide Content

    @ViewBuilder
    private var slideContent: some View {
        switch currentSlideData {
        case .title(let name, let photoURL):
            titleSlide(name: name, photoURL: photoURL)
        case .dayTitle(let number, let date):
            dayTitleSlide(number: number, date: date)
        case .place(let log, let place):
            placeSlide(log: log, place: place)
        case .closing(let placeCount):
            closingSlide(placeCount: placeCount)
        }
    }

    private func titleSlide(name: String, photoURL: String?) -> some View {
        ZStack {
            if let urlString = photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 800, height: 1200)) {
                    Color.black
                }
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 20)
                .saturation(0.7)
                .clipped()
            }

            Color.black.opacity(0.4)

            VStack(spacing: 12) {
                Text(name)
                    .font(.system(size: 42, weight: .light, design: .serif))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 1)

                Text("A TRIP IN PHOTOS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(4.0)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(40)
        }
        .ignoresSafeArea()
    }

    private func dayTitleSlide(number: Int, date: Date) -> some View {
        VStack(spacing: 8) {
            Text(date.formatted(.dateTime.month(.wide).day().year()).uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(3.0)
                .foregroundColor(.white.opacity(0.4))

            Text("Day \(number)")
                .font(.system(size: 36, weight: .light, design: .serif))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func placeSlide(log: Log, place: Place?) -> some View {
        GeometryReader { geo in
            if let urlString = log.photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: geo.size.width * 2, height: geo.size.height * 2)) {
                    placeFallbackPhoto(place: place, size: geo.size)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(kenBurnsToggle ? 1.08 : 1.0)
                .offset(x: kenBurnsToggle ? -8 : 8, y: kenBurnsToggle ? -4 : 4)
                .animation(.easeInOut(duration: 6), value: kenBurnsToggle)
                .clipped()
            } else {
                placeFallbackPhoto(place: place, size: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func placeFallbackPhoto(place: Place?, size: CGSize) -> some View {
        if let photoRef = place?.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: size.width * 2, height: size.height * 2)) {
                Color.black
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            Color(white: 0.1)
        }
    }

    private func closingSlide(placeCount: Int) -> some View {
        VStack(spacing: 24) {
            Text("\(placeCount)")
                .font(.system(size: 72, weight: .bold, design: .serif))
                .foregroundColor(.white)

            Text("places explored".uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(3.0)
                .foregroundColor(.white.opacity(0.5))

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 40, height: 1)
                .padding(.vertical, 8)

            Text(tripName)
                .font(.system(size: 24, weight: .light, design: .serif))
                .foregroundColor(.white.opacity(0.7))

            Text("sonder")
                .font(.system(size: 13, weight: .light, design: .serif))
                .tracking(4.0)
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 20)
        }
    }

    // MARK: - Subtitle

    @ViewBuilder
    private var subtitleOverlay: some View {
        if case .place(let log, let place) = currentSlideData {
            VStack {
                Spacer()

                VStack(spacing: 6) {
                    Text(place?.name ?? "")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundColor(.white)

                    if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty, showSubtitle {
                        Text(note)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    HStack(spacing: 8) {
                        Text(log.rating.emoji)
                        Text(log.rating.displayName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .animation(.easeOut(duration: 0.5), value: showSubtitle)
        }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            HStack {
                // Progress
                Text("\(max(0, currentSlide + 1)) / \(slides.count)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                // Play/pause indicator
                if !isPlaying {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Playback

    private func startPlayback() {
        currentSlide = 0
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        guard isPlaying else { return }

        kenBurnsToggle.toggle()
        showSubtitle = false

        // Show subtitle after a delay for place slides
        if case .place = currentSlideData {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showSubtitle = true
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: slideDuration, repeats: false) { _ in
            advanceSlide()
        }
    }

    private func advanceSlide() {
        if currentSlide < slides.count - 1 {
            withAnimation(.easeInOut(duration: 0.8)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                currentSlide += 1
                withAnimation(.easeInOut(duration: 0.8)) {
                    opacity = 1
                }
                scheduleNext()
            }
        } else {
            // End — hold on closing
            timer?.invalidate()
        }
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            scheduleNext()
        } else {
            timer?.invalidate()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Slide Types

private enum CinematicSlide {
    case title(name: String, photoURL: String?)
    case dayTitle(number: Int, date: Date)
    case place(log: Log, place: Place?)
    case closing(placeCount: Int)
}
