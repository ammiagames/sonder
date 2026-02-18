//
//  JournalPolaroidView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Vertical Polaroid feed with a calm editorial aesthetic.
struct JournalPolaroidView: View {
    let trips: [Trip]
    let allLogs: [Log]
    let places: [Place]
    let orphanedLogs: [Log]
    @Binding var selectedTrip: Trip?
    @Binding var selectedLog: Log?

    @State private var scrollOffset: CGFloat = 0
    @State private var initialScrollY: CGFloat?
    @State private var cardCenters: [Int: CGFloat] = [:]  // index -> midY in scroll
    @State private var scrolledID: String?
    @State private var sessionSeed: UInt64 = .random(in: 0..<UInt64.max)

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    /// Pre-grouped logs by tripID, built once per render pass.
    private var logsByTripID: [String: [Log]] {
        Dictionary(grouping: allLogs.filter { $0.tripID != nil }, by: { $0.tripID! })
    }

    private func logsForTrip(_ trip: Trip) -> [Log] {
        logsByTripID[trip.id] ?? []
    }

    /// Small deterministic tilt so cards do not feel machine-perfect.
    private func edgeRotation(for trip: Trip) -> Double {
        let seed = abs(trip.id.hashValue)
        return (Double(seed % 5) - 2.0) * 0.18  // -0.36 to +0.36
    }

    private var trailLineColor: Color {
        SonderColors.warmGrayDark
    }

    var body: some View {
        GeometryReader { outerGeo in
            let cardHeight: CGFloat = 392
            let cardSpacing: CGFloat = 64

            ZStack {
                topographicBackground
                    .scaleEffect(1.3)
                    .offset(y: clampedParallax)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            PolaroidTrailLine(
                                cardCenters: cardCenters,
                                count: trips.count,
                                phase: 0,
                                lineColor: trailLineColor
                            )
                            .allowsHitTesting(false)

                            LazyVStack(spacing: cardSpacing) {
                                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                                    GeometryReader { cardGeo in
                                        let midY = cardGeo.frame(in: .global).midY
                                        let screenMid = outerGeo.size.height / 2
                                        let distance = abs(midY - screenMid)
                                        let maxDistance: CGFloat = outerGeo.size.height * 0.44
                                        let normalizedDistance = min(distance / maxDistance, 1.0)

                                        // Centered card is full size; off-center cards shrink + fade
                                        let scale = 1.0 - normalizedDistance * 0.10
                                        let opacity = 1.0 - normalizedDistance * 0.35
                                        let yShift = normalizedDistance * 6

                                        polaroidCard(trip: trip, proximity: normalizedDistance)
                                            .scaleEffect(scale)
                                            .opacity(opacity)
                                            .offset(y: yShift)
                                            .rotationEffect(.degrees(edgeRotation(for: trip) * normalizedDistance))
                                            .animation(.interpolatingSpring(stiffness: 280, damping: 22), value: scale)
                                            .onAppear {
                                                updateCardCenter(index: index, from: cardGeo)
                                            }
                                            .onChange(of: midY) { _, _ in
                                                updateCardCenter(index: index, from: cardGeo)
                                            }
                                    }
                                    .frame(height: cardHeight)
                                    .id(trip.id)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.top, (outerGeo.size.height - cardHeight) / 2)
                            .padding(.bottom, trips.isEmpty ? 0 : (outerGeo.size.height - cardHeight) / 2)
                        }
                        .coordinateSpace(name: "polaroidScroll")

                        if !orphanedLogs.isEmpty {
                            orphanedLogsSection
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .global).minY
                            )
                        }
                    )
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .automatic))
                .scrollPosition(id: $scrolledID, anchor: .center)
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    if initialScrollY == nil { initialScrollY = value }
                    scrollOffset = value - (initialScrollY ?? value)
                }
            }
            .onAppear {
                if scrolledID == nil {
                    scrolledID = trips.first?.id
                }
            }
            .onChange(of: scrolledID) { oldValue, _ in
                guard oldValue != nil else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.32)
            }
        }
    }

    private func updateCardCenter(index: Int, from geometry: GeometryProxy) {
        let localMid = geometry.frame(in: .named("polaroidScroll")).midY
        cardCenters[index] = localMid
    }

    // MARK: - Parallax

    /// Clamped parallax offset so the topo background drifts gently with scroll.
    private var clampedParallax: CGFloat {
        max(-100, min(100, scrollOffset * 0.15))
    }

    // MARK: - Topographic Background

    private var topographicBackground: some View {
        ZStack {
            // Sandy terrain base
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.90, blue: 0.82),
                    Color(red: 0.90, green: 0.85, blue: 0.76),
                    Color(red: 0.92, green: 0.87, blue: 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                var rng = SeededRNG(seed: sessionSeed ^ 0x1111111111111111)

                // Color bands — filled regions between contours for topo map feel
                let bandColors: [Color] = [
                    Color(red: 0.88, green: 0.83, blue: 0.72).opacity(0.35),
                    Color(red: 0.84, green: 0.78, blue: 0.66).opacity(0.25),
                    Color(red: 0.80, green: 0.74, blue: 0.62).opacity(0.30),
                    Color(red: 0.86, green: 0.80, blue: 0.68).opacity(0.20),
                    Color(red: 0.82, green: 0.76, blue: 0.64).opacity(0.28)
                ]
                for (bi, bandColor) in bandColors.enumerated() {
                    let baseY = size.height * CGFloat(bi) / CGFloat(bandColors.count)
                    let bandH = size.height / CGFloat(bandColors.count) * 1.3
                    var bandPath = Path()
                    bandPath.move(to: CGPoint(x: -10, y: baseY))
                    for s in 0...12 {
                        let x = size.width * CGFloat(s) / 12
                        let wave = sin(CGFloat(s) * 0.6 + CGFloat(bi) * 1.8)
                            * CGFloat.random(in: 20...50, using: &rng)
                        bandPath.addLine(to: CGPoint(x: x, y: baseY + wave))
                    }
                    bandPath.addLine(to: CGPoint(x: size.width + 10, y: baseY + bandH))
                    bandPath.addLine(to: CGPoint(x: -10, y: baseY + bandH))
                    bandPath.closeSubpath()
                    context.fill(bandPath, with: .color(bandColor))
                }

                // Dense contour lines
                let lineColor = Color(red: 0.62, green: 0.55, blue: 0.44)
                let indexColor = Color(red: 0.55, green: 0.45, blue: 0.32)
                for i in 0..<35 {
                    let baseY = size.height * (CGFloat(i) - 2) / 30
                    let isIndex = i % 5 == 0

                    var points: [CGPoint] = []
                    for s in 0...10 {
                        let x = size.width * CGFloat(s) / 10
                        let w1 = sin(CGFloat(s) * 0.7 + CGFloat(i) * 0.45)
                            * CGFloat.random(in: 18...45, using: &rng)
                        let w2 = cos(CGFloat(s) * 0.3 + CGFloat(i) * 0.9)
                            * CGFloat.random(in: 8...20, using: &rng)
                        points.append(CGPoint(x: x, y: baseY + w1 + w2))
                    }

                    var path = Path()
                    path.move(to: points[0])
                    for j in 1..<points.count {
                        let mid = CGPoint(
                            x: (points[j - 1].x + points[j].x) / 2,
                            y: (points[j - 1].y + points[j].y) / 2
                        )
                        path.addQuadCurve(to: mid, control: points[j - 1])
                    }
                    if let last = points.last { path.addLine(to: last) }

                    if isIndex {
                        context.stroke(path, with: .color(indexColor.opacity(
                            Double.random(in: 0.45...0.65, using: &rng)
                        )), style: StrokeStyle(lineWidth: CGFloat.random(in: 1.8...2.8, using: &rng), lineCap: .round))
                    } else {
                        context.stroke(path, with: .color(lineColor.opacity(
                            Double.random(in: 0.20...0.38, using: &rng)
                        )), style: StrokeStyle(lineWidth: CGFloat.random(in: 0.6...1.2, using: &rng), lineCap: .round))
                    }
                }
            }

            PaperGrainOverlay(seed: sessionSeed ^ 0xAAAAAAAAAAAAAAAA)
                .opacity(0.30)
        }
    }
    // MARK: - Card Helpers

    private let frameBorder: CGFloat = 11
    private let frameBottomStrip: CGFloat = 82
    private let frameRadius: CGFloat = 4

    /// Slight deterministic wobble so handwriting feels human, not typed.
    private func writingTilt(for trip: Trip) -> Double {
        let seed = abs(trip.id.hashValue >> 3)
        return Double(seed % 5) - 2.0  // -2 to +2 deg
    }

    private func writingYOffset(for trip: Trip) -> CGFloat {
        let seed = abs(trip.id.hashValue >> 7)
        return CGFloat(seed % 3) - 1  // -1 to +1 pt
    }

    private func firstLogPhotoURL(for trip: Trip) -> URL? {
        let photos = logsForTrip(trip).flatMap { $0.userPhotoURLs }
        guard let first = photos.first else { return nil }
        return URL(string: first)
    }

    private func captionDetails(for trip: Trip) -> String {
        let logs = logsForTrip(trip)
        var parts: [String] = []
        parts.append("\(logs.count) place\(logs.count == 1 ? "" : "s")")
        if let start = trip.startDate {
            parts.append(start.formatted(.dateTime.month(.abbreviated).year()))
        }
        let highlights = logs.filter { $0.rating == .mustSee }.count
        if highlights > 0 {
            parts.append("\(highlights) highlight\(highlights == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func paperSeed(for trip: Trip) -> UInt64 {
        let tripBits = UInt64(bitPattern: Int64(trip.id.hashValue))
        return sessionSeed ^ tripBits ^ 0x9E3779B97F4A7C15
    }

    private enum TapePlacement {
        case none
        case left
        case right
        case both
    }

    /// Tape appears on roughly 10% of cards, with varied placement.
    private func tapePlacement(for trip: Trip) -> TapePlacement {
        let hash = abs(trip.id.hashValue)
        guard hash % 10 == 0 else { return .none }
        switch hash % 5 {
        case 0: return .both
        case 1, 2: return .left
        default: return .right
        }
    }

    private func shouldShowTape(for trip: Trip, corner: Int) -> Bool {
        switch tapePlacement(for: trip) {
        case .none:
            return false
        case .left:
            return corner == 0
        case .right:
            return corner == 1
        case .both:
            return true
        }
    }

    private func tapeTint(for trip: Trip, corner: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.92, blue: 0.84),
            Color(red: 0.93, green: 0.89, blue: 0.80),
            Color(red: 0.90, green: 0.92, blue: 0.86),
            Color(red: 0.91, green: 0.90, blue: 0.93)
        ]
        let idx = abs(trip.id.hashValue + corner * 73) % palette.count
        return palette[idx]
    }

    private struct TapeStyle {
        let width: CGFloat
        let height: CGFloat
        let cornerRadius: CGFloat
        let rotation: Double
        let xOffset: CGFloat
        let yOffset: CGFloat
        let opacity: Double
        let hasFoldMark: Bool
    }

    private func tapeStyle(for trip: Trip, corner: Int) -> TapeStyle {
        let baseSeed = paperSeed(for: trip) ^ UInt64(corner + 1) &* 0x517CC1B727220A95
        var rng = SeededRNG(seed: baseSeed)
        let baseRotation = corner == 0 ? -8.0 : 8.0

        return TapeStyle(
            width: CGFloat.random(in: 44...68, using: &rng),
            height: CGFloat.random(in: 11...16, using: &rng),
            cornerRadius: CGFloat.random(in: 1.8...3.0, using: &rng),
            rotation: baseRotation + Double.random(in: -4...4, using: &rng),
            xOffset: CGFloat.random(in: 14...26, using: &rng) * (corner == 0 ? 1 : -1),
            yOffset: CGFloat.random(in: -9 ... -3, using: &rng),
            opacity: Double.random(in: 0.58...0.78, using: &rng),
            hasFoldMark: Int.random(in: 0...2, using: &rng) == 0
        )
    }

    private var photoMoodOverlay: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.04),
                Color.clear,
                Color.black.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.06)],
                center: .center,
                startRadius: 70,
                endRadius: 340
            )
        }
        .blendMode(.softLight)
    }

    private func sharpieTitle(for trip: Trip) -> some View {
        let titleSize: CGFloat = trip.name.count > 14 ? 24 : 27
        let ink = Color(red: 0.13, green: 0.12, blue: 0.11)

        return ZStack {
            // Soft bleed underlayer to emulate marker pressure on paper.
            Text(trip.name)
                .font(.custom("Noteworthy-Bold", size: titleSize))
                .foregroundColor(ink.opacity(0.24))
                .blur(radius: 0.8)
                .offset(x: 0.25, y: 0.7)

            Text(trip.name)
                .font(.custom("Noteworthy-Bold", size: titleSize))
                .foregroundColor(ink.opacity(0.94))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .rotationEffect(.degrees(writingTilt(for: trip)))
        .offset(y: writingYOffset(for: trip))
    }

    private func tapeSticker(trip: Trip, corner: Int) -> some View {
        let style = tapeStyle(for: trip, corner: corner)
        let tint = tapeTint(for: trip, corner: corner)

        return RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(tint.opacity(style.opacity))
            .frame(width: style.width, height: style.height)
            .overlay {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.45)
            }
            .overlay {
                if style.hasFoldMark {
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 0.7)
                        .offset(y: style.height * 0.18)
                }
            }
            .rotationEffect(.degrees(style.rotation))
            .offset(x: style.xOffset, y: style.yOffset)
            .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
    }

    // MARK: - Polaroid Card

    private func polaroidCard(trip: Trip, proximity: CGFloat) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 700, height: 700)) {
                            polaroidPlaceholder(trip: trip)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else if let logPhotoURL = firstLogPhotoURL(for: trip) {
                        DownsampledAsyncImage(url: logPhotoURL, targetSize: CGSize(width: 700, height: 700)) {
                            polaroidPlaceholder(trip: trip)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        polaroidPlaceholder(trip: trip)
                    }

                    photoMoodOverlay
                        .opacity(0.75 - Double(proximity) * 0.3)
                }
                .frame(height: 300)
                .clipped()
                .padding(.top, frameBorder)
                .padding(.horizontal, frameBorder)

                VStack(alignment: .leading, spacing: 5) {
                    sharpieTitle(for: trip)

                    Text(captionDetails(for: trip))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, frameBorder + 10)
                .padding(.top, 11)
                .frame(height: frameBottomStrip, alignment: .topLeading)
            }
            .background(Color(red: 0.975, green: 0.964, blue: 0.947))
            .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
            .overlay {
                PaperGrainOverlay(seed: paperSeed(for: trip))
                    .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if shouldShowTape(for: trip, corner: 0) {
                    tapeSticker(trip: trip, corner: 0)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if shouldShowTape(for: trip, corner: 1) {
                    tapeSticker(trip: trip, corner: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.10), radius: 12, y: 7)
            .padding(.horizontal, 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Orphaned Logs

    private var orphanedLogsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Loose memories")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundColor(SonderColors.inkDark.opacity(0.85))

                Spacer()

                Text("\(orphanedLogs.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(SonderColors.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.45))
                    )
            }
            .padding(.horizontal, 28)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 16
            ) {
                ForEach(orphanedLogs, id: \.id) { log in
                    miniPolaroidCard(log: log)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 28)
        .padding(.bottom, 100)
    }

    private func miniPolaroidCard(log: Log) -> some View {
        let place = placesByID[log.placeID]
        return Button {
            selectedLog = log
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if let urlString = log.photoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 360, height: 360)) {
                            miniPolaroidPlaceholder(log: log)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        miniPolaroidPlaceholder(log: log)
                    }

                    LinearGradient(
                        colors: [Color.white.opacity(0.03), Color.black.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .blendMode(.softLight)
                }
                .frame(height: 126)
                .clipped()
                .padding(.top, 7)
                .padding(.horizontal, 7)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place?.name ?? "Unknown Place")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    Text("\(log.visitedAt.formatted(.dateTime.month(.abbreviated).day())) · \(log.rating.displayName)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(SonderColors.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 9)
            }
            .background(Color(red: 0.975, green: 0.964, blue: 0.947))
            .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func miniPolaroidPlaceholder(log: Log) -> some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.85, blue: 0.80),
                Color(red: 0.82, green: 0.78, blue: 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "mappin.circle")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func polaroidPlaceholder(trip: Trip) -> some View {
        TripCoverPlaceholderView(seedKey: trip.id, title: trip.name, caption: "Loading memories...")
    }
}

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Seeded RNG

/// Deterministic RNG so decorative textures stay stable.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Paper Grain Overlay

private struct PaperGrainOverlay: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: seed)

            for _ in 0..<320 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let w = CGFloat.random(in: 0.4...1.6, using: &rng)
                let h = CGFloat.random(in: 0.4...1.6, using: &rng)
                let isDark = Bool.random(using: &rng)
                let alpha = Double.random(in: 0.02...0.07, using: &rng)

                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)),
                    with: .color(isDark ? Color.black.opacity(alpha) : Color.white.opacity(alpha))
                )
            }
        }
        .blendMode(.softLight)
        .opacity(0.55)
    }
}

// MARK: - Curvy Trail Line

/// Dotted S-curve connecting card centers.
private struct PolaroidTrailLine: View {
    let cardCenters: [Int: CGFloat]  // index -> midY
    let count: Int
    let phase: CGFloat
    var lineColor: Color = Color(red: 0.80, green: 0.45, blue: 0.35)

    var body: some View {
        Canvas { context, size in
            let sortedIndices = (0..<count).filter { cardCenters[$0] != nil }.sorted()
            guard sortedIndices.count >= 2 else { return }

            let strokeColor = lineColor.opacity(0.26)
            let dotColor = lineColor.opacity(0.40)
            let dashStyle = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6], dashPhase: phase)
            let midX = size.width / 2

            var points: [CGPoint] = []
            for (i, index) in sortedIndices.enumerated() {
                guard let y = cardCenters[index] else { continue }
                let xOffset: CGFloat = i.isMultiple(of: 2) ? -28 : 28
                points.append(CGPoint(x: midX + xOffset, y: y))
            }
            guard points.count >= 2 else { return }

            var path = Path()
            path.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                let midY = (prev.y + curr.y) / 2
                path.addCurve(
                    to: curr,
                    control1: CGPoint(x: prev.x, y: midY),
                    control2: CGPoint(x: curr.x, y: midY)
                )
            }
            context.stroke(path, with: .color(strokeColor), style: dashStyle)

            for point in points {
                let r: CGFloat = 4
                let dotRect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            }
        }
        .allowsHitTesting(false)
    }
}
