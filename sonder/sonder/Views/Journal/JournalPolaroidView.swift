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

    @State private var parallaxOffset: CGFloat = 0
    @State private var currentCardIndex: Int = 0
    @State private var sessionSeed: UInt64 = .random(in: 0..<UInt64.max)
    @State private var showOrphanedLogs: Bool = false
    @State private var orphanedVisibleCount: Int = 12
    private let orphanedPageSize = 12

    // Cached groupings — rebuilt when data changes
    @State private var cachedPlacesByID: [String: Place] = [:]
    @State private var cachedLogsByTripID: [String: [Log]] = [:]

    init(
        trips: [Trip],
        allLogs: [Log],
        places: [Place],
        orphanedLogs: [Log],
        selectedTrip: Binding<Trip?>,
        selectedLog: Binding<Log?>
    ) {
        self.trips = trips
        self.allLogs = allLogs
        self.places = places
        self.orphanedLogs = orphanedLogs
        self._selectedTrip = selectedTrip
        self._selectedLog = selectedLog
    }

    private var placesByID: [String: Place] { cachedPlacesByID }

    private func logsForTrip(_ trip: Trip) -> [Log] {
        cachedLogsByTripID[trip.id] ?? []
    }

    private func rebuildJournalCaches() {
        cachedPlacesByID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cachedLogsByTripID = Dictionary(grouping: allLogs.filter { $0.tripID != nil }, by: { $0.tripID ?? "" })
    }

    /// Alternating tilt so adjacent cards lean opposite directions.
    private func edgeRotation(for index: Int, trip: Trip) -> Double {
        let magnitude = 1.2 + Double(abs(trip.id.hashValue) % 5) * 0.3  // 1.2 to 2.4°
        return index.isMultiple(of: 2) ? -magnitude : magnitude
    }

    private var trailLineColor: Color {
        SonderColors.terracotta
    }

    private var visibleOrphanedLogs: [Log] {
        Array(orphanedLogs.prefix(orphanedVisibleCount))
    }

    private var hasMoreOrphanedLogs: Bool {
        orphanedVisibleCount < orphanedLogs.count
    }

    var body: some View {
        GeometryReader { outerGeo in
            let cardHeight: CGFloat = 392
            let pageHeight = outerGeo.size.height

            // Card centers are static in scroll-content space: card i always sits at
            // i * pageHeight + pageHeight/2. Computing here avoids GeometryReader @State
            // updates that would trigger re-renders during the initial tab animation.
            let cardCenters: [Int: CGFloat] = pageHeight > 0
                ? Dictionary(trips.indices.map { i in
                    (i, CGFloat(i) * pageHeight + pageHeight / 2)
                  }, uniquingKeysWith: { first, _ in first })
                : [:]

            ZStack {
                topographicBackground
                    .drawingGroup()  // Cache Canvas as Metal texture; parallax = GPU transform only
                    .scaleEffect(1.3)
                    .offset(y: parallaxOffset)
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

                            LazyVStack(spacing: 0) {
                                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                                    // Each page is full-screen height so .viewAligned snaps
                                    // card centers to screen center with zero post-idle correction.
                                    let isLast = index == trips.count - 1

                                    ZStack {
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

                                            polaroidCard(trip: trip, index: index, proximity: normalizedDistance)
                                                .scaleEffect(scale)
                                                .opacity(opacity)
                                                .offset(y: yShift)
                                                .rotationEffect(.degrees(edgeRotation(for: index, trip: trip)))
                                        }
                                        .frame(height: cardHeight)
                                    }
                                    .frame(height: outerGeo.size.height)
                                    // Loose memories row pinned to the bottom of the last card's page,
                                    // as an overlay so it never displaces the centered polaroid.
                                    .overlay(alignment: .bottom) {
                                        if isLast && !orphanedLogs.isEmpty {
                                            looseMemoriesButton
                                                .padding(.bottom, 60)
                                        }
                                    }
                                    .id(trip.id)
                                }
                            }
                        }
                        if !orphanedLogs.isEmpty && showOrphanedLogs {
                            orphanedContentSection
                        }
                    }
                }
                .scrollTargetBehavior(
                    TripCardSnapBehavior(tripCount: trips.count, pageHeight: outerGeo.size.height)
                )
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newOffset in
                    // Throttled parallax — only trigger body re-render when visible change > 2pt
                    let newParallax = max(-100, min(100, -newOffset * 0.15))
                    if abs(newParallax - parallaxOffset) > 2 {
                        parallaxOffset = newParallax
                    }

                    if pageHeight > 0 && !trips.isEmpty {
                        let idx = max(0, min(trips.count - 1, Int(round(newOffset / pageHeight))))
                        if idx != currentCardIndex {
                            currentCardIndex = idx
                        }
                    }
                }
            }
            .onChange(of: currentCardIndex) { _, _ in
                SonderHaptics.impact(.soft, intensity: 0.32)
            }
            .onAppear {
                rebuildJournalCaches()
                syncOrphanedPagination()
            }
            .onChange(of: allLogs.count) { _, _ in rebuildJournalCaches() }
            .onChange(of: places.count) { _, _ in rebuildJournalCaches() }
            .onChange(of: orphanedLogs.count) { _, _ in
                syncOrphanedPagination()
            }
        }
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
                .foregroundStyle(ink.opacity(0.24))
                .blur(radius: 0.8)
                .offset(x: 0.25, y: 0.7)

            Text(trip.name)
                .font(.custom("Noteworthy-Bold", size: titleSize))
                .foregroundStyle(ink.opacity(0.94))
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

    // MARK: - Per-Session Decoration Decisions

    /// All decoration choices for a single card, reshuffled each app launch.
    private struct TripDecorations {
        let hasTape: Bool
        let tapeSide: TapePlacement
        let hasPostmark: Bool
        let hasDogEar: Bool
        let dogEarIsBottomRight: Bool
        let hasPushPin: Bool
        let paperWarmth: Double  // 0…1
    }

    /// Cheap deterministic-within-session RNG seeded from sessionSeed + trip identity.
    /// Different every app launch, stable during a single session.
    private func decorations(for trip: Trip) -> TripDecorations {
        let tripBits = UInt64(bitPattern: Int64(trip.id.hashValue))
        var rng = SeededRNG(seed: sessionSeed ^ tripBits ^ 0xA3B1C2D4E5F60718)

        let tapeRoll = Int.random(in: 0..<100, using: &rng)
        let hasTape = tapeRoll < 35
        let tapeSide: TapePlacement
        if hasTape {
            switch Int.random(in: 0..<5, using: &rng) {
            case 0: tapeSide = .both
            case 1, 2: tapeSide = .left
            default: tapeSide = .right
            }
        } else {
            tapeSide = .none
        }

        return TripDecorations(
            hasTape: hasTape,
            tapeSide: tapeSide,
            hasPostmark: Int.random(in: 0..<100, using: &rng) < 25,
            hasDogEar: Int.random(in: 0..<100, using: &rng) < 20,
            dogEarIsBottomRight: Bool.random(using: &rng),
            hasPushPin: Int.random(in: 0..<100, using: &rng) < 20,
            paperWarmth: Double.random(in: 0...1, using: &rng)
        )
    }

    /// Paper aging — warmth varies per session.
    private func paperColor(warmth: Double) -> Color {
        let w = warmth * 0.06  // 0 to 0.06
        return Color(
            red: 0.975 - w * 0.4,
            green: 0.964 - w * 1.0,
            blue: 0.947 - w * 2.2
        )
    }

    /// Sharpie-style frame number written on the polaroid's white strip.
    private func sharpieFrameNumber(index: Int) -> some View {
        let ink = Color(red: 0.13, green: 0.12, blue: 0.11)
        let number = trips.count - index  // oldest = 01

        return ZStack {
            // Subtle bleed for marker feel
            Text(String(format: "%02d", number))
                .font(.custom("Marker Felt", size: 14))
                .foregroundStyle(ink.opacity(0.18))
                .blur(radius: 0.6)
                .offset(x: 0.2, y: 0.5)

            Text(String(format: "%02d", number))
                .font(.custom("Marker Felt", size: 14))
                .foregroundStyle(ink.opacity(0.50))
        }
    }

    /// Rubber-stamp date in the corner of the photo (uses startDate or createdAt).
    private func dateStamp(for trip: Trip) -> some View {
        let date = trip.startDate ?? trip.createdAt
        let formatted = date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)).uppercased()
        let stampInk = Color(red: 0.72, green: 0.38, blue: 0.28)

        return Text(formatted)
            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
            .foregroundStyle(stampInk.opacity(0.70))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(stampInk.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            .rotationEffect(.degrees(-8))
            .padding(10)
    }

    /// Circular postmark cancellation stamp — visible on photos.
    private func postmarkOverlay(for trip: Trip) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius: CGFloat = min(size.width, size.height) * 0.38
            let color = Color(red: 0.55, green: 0.30, blue: 0.22).opacity(0.35)

            // Outer circle
            let outerRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: outerRect), with: .color(color), style: StrokeStyle(lineWidth: 2.0))

            // Inner circle
            let innerR = radius * 0.75
            let innerRect = CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)
            context.stroke(Path(ellipseIn: innerRect), with: .color(color), style: StrokeStyle(lineWidth: 1.2))

            // Wavy cancellation lines (wider spread)
            for lineIdx in -3...3 {
                let yOff = CGFloat(lineIdx) * 7
                var linePath = Path()
                linePath.move(to: CGPoint(x: center.x - radius * 1.2, y: center.y + yOff))
                for s in 0...10 {
                    let x = center.x - radius * 1.2 + CGFloat(s) * (radius * 2.4 / 10)
                    let wave = sin(CGFloat(s) * 1.1 + CGFloat(lineIdx) * 0.4) * 3.0
                    linePath.addLine(to: CGPoint(x: x, y: center.y + yOff + wave))
                }
                context.stroke(linePath, with: .color(color), style: StrokeStyle(lineWidth: 0.9))
            }
        }
        .frame(width: 130, height: 130)
        .rotationEffect(.degrees(15))
    }

    /// Folded corner (dog-ear) for a lived-in, tactile feel.
    private func dogEarOverlay(isBottomRight: Bool) -> some View {
        let foldSize: CGFloat = 26
        // Inset from edge so rounded clip doesn't hide the fold
        let inset: CGFloat = 2

        return Canvas { context, size in
            let paperUnder = Color(red: 0.90, green: 0.87, blue: 0.82)
            let shadow = Color.black.opacity(0.18)

            if isBottomRight {
                let corner = CGPoint(x: size.width - inset, y: size.height - inset)
                // Shadow triangle (slightly larger, offset)
                var shadowPath = Path()
                shadowPath.move(to: CGPoint(x: corner.x + 1, y: corner.y - foldSize - 2))
                shadowPath.addLine(to: CGPoint(x: corner.x - foldSize - 2, y: corner.y + 1))
                shadowPath.addLine(to: CGPoint(x: corner.x + 1, y: corner.y + 1))
                shadowPath.closeSubpath()
                context.fill(shadowPath, with: .color(shadow))

                // Paper fold triangle
                var foldPath = Path()
                foldPath.move(to: CGPoint(x: corner.x, y: corner.y - foldSize))
                foldPath.addLine(to: CGPoint(x: corner.x - foldSize, y: corner.y))
                foldPath.addLine(to: corner)
                foldPath.closeSubpath()
                context.fill(foldPath, with: .color(paperUnder))

                // Crease line
                var crease = Path()
                crease.move(to: CGPoint(x: corner.x, y: corner.y - foldSize))
                crease.addLine(to: CGPoint(x: corner.x - foldSize, y: corner.y))
                context.stroke(crease, with: .color(Color.black.opacity(0.12)), style: StrokeStyle(lineWidth: 1.0))
            } else {
                let corner = CGPoint(x: size.width - inset, y: inset)
                var shadowPath = Path()
                shadowPath.move(to: CGPoint(x: corner.x - foldSize - 2, y: corner.y - 1))
                shadowPath.addLine(to: CGPoint(x: corner.x + 1, y: corner.y + foldSize + 2))
                shadowPath.addLine(to: CGPoint(x: corner.x + 1, y: corner.y - 1))
                shadowPath.closeSubpath()
                context.fill(shadowPath, with: .color(shadow))

                var foldPath = Path()
                foldPath.move(to: CGPoint(x: corner.x - foldSize, y: corner.y))
                foldPath.addLine(to: CGPoint(x: corner.x, y: corner.y + foldSize))
                foldPath.addLine(to: corner)
                foldPath.closeSubpath()
                context.fill(foldPath, with: .color(paperUnder))

                var crease = Path()
                crease.move(to: CGPoint(x: corner.x - foldSize, y: corner.y))
                crease.addLine(to: CGPoint(x: corner.x, y: corner.y + foldSize))
                context.stroke(crease, with: .color(Color.black.opacity(0.12)), style: StrokeStyle(lineWidth: 1.0))
            }
        }
        .allowsHitTesting(false)
    }

    /// Push-pin / thumbtack at the top center — prominent enough to see.
    private var pushPinOverlay: some View {
        ZStack {
            // Pin shadow
            Ellipse()
                .fill(Color.black.opacity(0.22))
                .frame(width: 18, height: 10)
                .offset(y: 8)

            // Pin needle (line into card)
            Rectangle()
                .fill(Color.gray.opacity(0.40))
                .frame(width: 1.5, height: 8)
                .offset(y: 6)

            // Pin head — terracotta gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.88, green: 0.45, blue: 0.33),
                            Color(red: 0.65, green: 0.28, blue: 0.20)
                        ],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 18, height: 18)

            // Specular highlight
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 5.5, height: 5.5)
                .offset(x: -3, y: -3)
        }
        .offset(y: -9)
    }

    // MARK: - Polaroid Card

    private func polaroidCard(trip: Trip, index: Int, proximity: CGFloat) -> some View {
        let deco = decorations(for: trip)

        return Button {
            selectedTrip = trip
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    // Photo
                    if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 350, height: 350)) {
                            polaroidPlaceholder(trip: trip)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    } else {
                        polaroidPlaceholder(trip: trip)
                    }

                    // Film mood overlay
                    photoMoodOverlay
                        .opacity(0.75 - Double(proximity) * 0.3)

                    // (film frame number moved to caption strip)

                    // Date stamp (bottom-right)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            dateStamp(for: trip)
                        }
                    }

                    // Postmark (~25% of cards)
                    if deco.hasPostmark {
                        VStack {
                            HStack {
                                Spacer()
                                postmarkOverlay(for: trip)
                                    .padding(.top, -4)
                                    .padding(.trailing, -8)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 300)
                .clipped()
                .padding(.top, frameBorder)
                .padding(.horizontal, frameBorder)

                // Caption area
                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .leading, spacing: 5) {
                        sharpieTitle(for: trip)

                        Text(captionDetails(for: trip))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SonderColors.inkMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, frameBorder + 10)
                    .padding(.top, 11)

                    // Sharpie-style trip number on the polaroid white strip
                    sharpieFrameNumber(index: index)
                        .padding(.trailing, frameBorder + 10)
                        .padding(.bottom, 8)
                }
                .frame(height: frameBottomStrip, alignment: .topLeading)
            }
            .background(paperColor(warmth: deco.paperWarmth))
            .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
            // Paper grain
            .overlay {
                PaperGrainOverlay(seed: paperSeed(for: trip))
                    .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
            // Dog-ear (~20%)
            .overlay {
                if deco.hasDogEar {
                    dogEarOverlay(isBottomRight: deco.dogEarIsBottomRight)
                        .clipShape(RoundedRectangle(cornerRadius: frameRadius, style: .continuous))
                }
            }
            // Washi tape (~35%)
            .overlay(alignment: .topLeading) {
                if deco.tapeSide == .left || deco.tapeSide == .both {
                    tapeSticker(trip: trip, corner: 0)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if deco.tapeSide == .right || deco.tapeSide == .both {
                    tapeSticker(trip: trip, corner: 1)
                        .allowsHitTesting(false)
                }
            }
            // Push-pin (~20%)
            .overlay(alignment: .top) {
                if deco.hasPushPin {
                    pushPinOverlay
                        .allowsHitTesting(false)
                }
            }
            // Border
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            // Layered shadows: tight contact + soft diffuse
            .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.10), radius: 16, y: 10)
            .padding(.horizontal, 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Orphaned Logs

    /// "Loose memories" row, shown at the bottom of the last trip's page.
    private var looseMemoriesButton: some View {
        Button {
            let willExpand = !showOrphanedLogs
            if willExpand { syncOrphanedPagination() }
            SonderHaptics.impact(.soft, intensity: 0.42)
            withAnimation(.easeInOut(duration: 0.25)) {
                showOrphanedLogs.toggle()
            }
        } label: {
            HStack {
                Text("Loose memories")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(SonderColors.inkDark.opacity(0.85))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SonderColors.inkMuted)
                    .rotationEffect(.degrees(showOrphanedLogs ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: showOrphanedLogs)

                Spacer()

                Text("\(orphanedLogs.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonderColors.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.45)).allowsHitTesting(false)
                    )
                    .contentShape(Rectangle())
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.001))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28)
    }

    /// Grid of orphaned logs, shown below the header page when expanded.
    private var orphanedContentSection: some View {
        VStack(spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 16
            ) {
                ForEach(visibleOrphanedLogs, id: \.id) { log in
                    miniPolaroidCard(log: log)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            let parallax = min(abs(phase.value), 1)
                            return content
                                .scaleEffect(1 - parallax * 0.045)
                                .offset(y: parallax * 6)
                                .opacity(1 - Double(parallax) * 0.14)
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            if hasMoreOrphanedLogs {
                Button {
                    loadMoreOrphanedLogs()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Load more memories")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(SonderColors.terracotta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color.white.opacity(0.55))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 100)
    }

    private func miniPolaroidCard(log: Log) -> some View {
        let place = placesByID[log.placeID]
        return Button {
            SonderHaptics.impact(.light, intensity: 0.5)
            selectedLog = log
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if let urlString = log.photoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 180, height: 180)) {
                            miniPolaroidPlaceholder(log: log, place: place)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    } else {
                        miniPolaroidPlaceholder(log: log, place: place)
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
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    Text("\(log.visitedAt.formatted(.dateTime.month(.abbreviated).day())) · \(log.rating.displayName)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 9)
            }
            .frame(height: 185)
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

    private func loadMoreOrphanedLogs() {
        guard hasMoreOrphanedLogs else { return }
        let nextCount = min(orphanedVisibleCount + orphanedPageSize, orphanedLogs.count)
        guard nextCount > orphanedVisibleCount else { return }
        orphanedVisibleCount = nextCount
        SonderHaptics.impact(.medium, intensity: 0.55)
    }

    private func syncOrphanedPagination() {
        let minimumVisible = min(orphanedPageSize, orphanedLogs.count)
        if orphanedVisibleCount < minimumVisible {
            orphanedVisibleCount = minimumVisible
        } else if orphanedVisibleCount > orphanedLogs.count {
            orphanedVisibleCount = orphanedLogs.count
        }
    }

    // MARK: - Orphaned Log Placeholder Styles

    /// Randomly picks one of six placeholder styles per log, stable within a session.
    private func miniPolaroidPlaceholder(log: Log, place: Place? = nil) -> some View {
        let seed = sessionSeed ^ UInt64(bitPattern: Int64(log.id.hashValue)) ^ 0xCAFEBABEDEAD
        var rng = SeededRNG(seed: seed)
        let style = Int.random(in: 0..<6, using: &rng)
        return Group {
            switch style {
            case 0: placeholderChemicalBurn(rating: log.rating, seed: seed)
            case 1: placeholderCategoryDoodle(types: place?.types ?? [], seed: seed)
            case 2: placeholderPassportStamp(date: log.visitedAt, rating: log.rating, seed: seed)
            case 3: placeholderVintageLabel(name: place?.name ?? "Unknown", date: log.visitedAt, seed: seed)
            case 4: placeholderTopoMiniMap(rating: log.rating, seed: seed)
            default: placeholderWatercolorWash(types: place?.types ?? [], seed: seed)
            }
        }
    }

    private func placeholderCategoryIcon(for types: [String]) -> String {
        for type in types {
            if type.contains("restaurant") || type == "food" { return "fork.knife" }
            if type.contains("cafe") || type.contains("coffee") { return "cup.and.saucer.fill" }
            if type.contains("bar") || type.contains("night_club") { return "wineglass.fill" }
            if type.contains("museum") || type.contains("art_gallery") { return "building.columns.fill" }
            if type.contains("park") || type.contains("campground") { return "leaf.fill" }
            if type.contains("store") || type.contains("shopping") { return "bag.fill" }
            if type.contains("lodging") || type.contains("hotel") { return "bed.double.fill" }
            if type.contains("gym") || type.contains("stadium") { return "figure.run" }
            if type.contains("airport") { return "airplane" }
            if type.contains("train") || type.contains("transit") { return "tram.fill" }
            if type.contains("library") { return "books.vertical.fill" }
            if type.contains("movie") || type.contains("theater") { return "film.fill" }
            if type.contains("spa") || type.contains("beauty") { return "sparkles" }
            if type.contains("church") || type.contains("temple") || type.contains("mosque") { return "building.fill" }
            if type.contains("hospital") || type.contains("pharmacy") { return "cross.fill" }
            if type.contains("beach") { return "sun.max.fill" }
        }
        return "mappin.circle.fill"
    }

    /// Style 0 — Undeveloped polaroid with organic color blobs and a light-leak streak.
    private func placeholderChemicalBurn(rating: Rating, seed: UInt64) -> some View {
        Canvas { context, size in
            var rng = SeededRNG(seed: seed ^ 0x111)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.93, green: 0.90, blue: 0.84)))

            let tint: Color
            switch rating {
            case .mustSee: tint = Color(red: 0.85, green: 0.62, blue: 0.35)
            case .great:   tint = Color(red: 0.82, green: 0.68, blue: 0.38)
            case .okay:    tint = Color(red: 0.62, green: 0.76, blue: 0.65)
            case .skip:    tint = Color(red: 0.74, green: 0.72, blue: 0.69)
            }

            for _ in 0..<Int.random(in: 4...7, using: &rng) {
                let cx = CGFloat.random(in: -15...size.width + 15, using: &rng)
                let cy = CGFloat.random(in: -15...size.height + 15, using: &rng)
                let rx = CGFloat.random(in: 25...65, using: &rng)
                let ry = CGFloat.random(in: 20...55, using: &rng)
                context.fill(
                    Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)),
                    with: .color(tint.opacity(Double.random(in: 0.08...0.22, using: &rng))))
            }

            let sy = CGFloat.random(in: size.height * 0.2...size.height * 0.7, using: &rng)
            var streak = Path()
            streak.move(to: CGPoint(x: -10, y: sy))
            streak.addQuadCurve(
                to: CGPoint(x: size.width + 10, y: sy + CGFloat.random(in: -25...25, using: &rng)),
                control: CGPoint(x: size.width * 0.5, y: sy + CGFloat.random(in: -30...30, using: &rng)))
            context.stroke(streak, with: .color(Color.white.opacity(0.18)),
                           style: StrokeStyle(lineWidth: CGFloat.random(in: 18...38, using: &rng), lineCap: .round))
        }
    }

    /// Style 1 — Kraft paper with faint ruled lines and a large category-icon sketch.
    private func placeholderCategoryDoodle(types: [String], seed: UInt64) -> some View {
        let icon = placeholderCategoryIcon(for: types)
        var rng = SeededRNG(seed: seed ^ 0x222)
        let rotation = Double.random(in: -12...12, using: &rng)

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.83, green: 0.77, blue: 0.67), Color(red: 0.79, green: 0.73, blue: 0.63)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            Canvas { context, size in
                var lrng = SeededRNG(seed: seed ^ 0x2222)
                for y in stride(from: CGFloat(8), to: size.height, by: 11) {
                    var line = Path()
                    line.move(to: CGPoint(x: 5, y: y))
                    line.addLine(to: CGPoint(x: size.width - 5, y: y))
                    context.stroke(line,
                                   with: .color(Color.white.opacity(Double.random(in: 0.08...0.14, using: &lrng))),
                                   style: StrokeStyle(lineWidth: 0.5))
                }
            }

            Image(systemName: icon)
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(Color(red: 0.50, green: 0.43, blue: 0.34).opacity(0.45))
                .rotationEffect(.degrees(rotation))
        }
    }

    /// Style 2 — Passport page with ruled lines, a circular entry stamp, and the visit date.
    private func placeholderPassportStamp(date: Date, rating: Rating, seed: UInt64) -> some View {
        var rng = SeededRNG(seed: seed ^ 0x333)
        let stampRotation = Double.random(in: -18...18, using: &rng)
        let stampAlpha = Double.random(in: 0.35...0.55, using: &rng)

        let ink: Color
        switch rating {
        case .mustSee: ink = Color(red: 0.72, green: 0.28, blue: 0.22)
        case .great:   ink = Color(red: 0.65, green: 0.50, blue: 0.20)
        case .okay:    ink = Color(red: 0.22, green: 0.32, blue: 0.58)
        case .skip:    ink = Color(red: 0.50, green: 0.48, blue: 0.45)
        }

        return ZStack {
            Color(red: 0.95, green: 0.93, blue: 0.88)

            Canvas { context, size in
                for y in stride(from: CGFloat(10), to: size.height, by: 14) {
                    var line = Path()
                    line.move(to: CGPoint(x: 5, y: y))
                    line.addLine(to: CGPoint(x: size.width - 5, y: y))
                    context.stroke(line,
                                   with: .color(Color(red: 0.70, green: 0.75, blue: 0.85).opacity(0.15)),
                                   style: StrokeStyle(lineWidth: 0.5))
                }
            }

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let r: CGFloat = min(size.width, size.height) * 0.30
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                    with: .color(ink.opacity(stampAlpha)),
                    style: StrokeStyle(lineWidth: 2.0))
                let ir = r * 0.70
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - ir, y: center.y - ir, width: ir * 2, height: ir * 2)),
                    with: .color(ink.opacity(stampAlpha * 0.8)),
                    style: StrokeStyle(lineWidth: 1.2))
                var h = Path()
                h.move(to: CGPoint(x: center.x - r * 0.85, y: center.y))
                h.addLine(to: CGPoint(x: center.x + r * 0.85, y: center.y))
                context.stroke(h, with: .color(ink.opacity(stampAlpha * 0.6)),
                               style: StrokeStyle(lineWidth: 0.8))
            }
            .rotationEffect(.degrees(stampRotation))

            Text(date.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(ink.opacity(0.40))
                .rotationEffect(.degrees(stampRotation))
        }
    }

    /// Style 3 — Vintage luggage label with the place name in a decorative double border.
    private func placeholderVintageLabel(name: String, date: Date, seed: UInt64) -> some View {
        var rng = SeededRNG(seed: seed ^ 0x444)
        let rotation = Double.random(in: -4...4, using: &rng)
        let borderInk = Color(red: 0.55, green: 0.40, blue: 0.28)

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.92, green: 0.88, blue: 0.80), Color(red: 0.88, green: 0.84, blue: 0.75)],
                startPoint: .top, endPoint: .bottom)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(borderInk.opacity(0.35), lineWidth: 1.5)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(borderInk.opacity(0.20), lineWidth: 0.8)
                        .padding(12)
                )
                .overlay {
                    VStack(spacing: 4) {
                        Text(name.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(borderInk.opacity(0.65))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)

                        Rectangle()
                            .fill(borderInk.opacity(0.20))
                            .frame(width: 40, height: 0.8)

                        Text(date.formatted(.dateTime.year()).uppercased())
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(borderInk.opacity(0.45))
                    }
                    .padding(.horizontal, 18)
                }
                .rotationEffect(.degrees(rotation))
        }
    }

    /// Style 4 — Mini topographic map with contour lines and a center pin.
    private func placeholderTopoMiniMap(rating: Rating, seed: UInt64) -> some View {
        let tint: Color
        switch rating {
        case .mustSee: tint = Color(red: 0.78, green: 0.42, blue: 0.30)
        case .great:   tint = Color(red: 0.72, green: 0.58, blue: 0.30)
        case .okay:    tint = Color(red: 0.45, green: 0.58, blue: 0.48)
        case .skip:    tint = Color(red: 0.58, green: 0.55, blue: 0.52)
        }

        return ZStack {
            Color(red: 0.94, green: 0.91, blue: 0.84)

            Canvas { context, size in
                var rng = SeededRNG(seed: seed ^ 0x555)
                for i in 0..<12 {
                    let baseY = size.height * CGFloat(i) / 10 - size.height * 0.1
                    var points: [CGPoint] = []
                    for s in 0...6 {
                        let x = size.width * CGFloat(s) / 6
                        let wave = sin(CGFloat(s) * 0.8 + CGFloat(i) * 0.5)
                            * CGFloat.random(in: 8...20, using: &rng)
                        points.append(CGPoint(x: x, y: baseY + wave))
                    }
                    var path = Path()
                    path.move(to: points[0])
                    for j in 1..<points.count {
                        let mid = CGPoint(
                            x: (points[j - 1].x + points[j].x) / 2,
                            y: (points[j - 1].y + points[j].y) / 2)
                        path.addQuadCurve(to: mid, control: points[j - 1])
                    }
                    if let last = points.last { path.addLine(to: last) }
                    let isThick = i % 4 == 0
                    context.stroke(path,
                                   with: .color(tint.opacity(isThick ? 0.35 : 0.18)),
                                   style: StrokeStyle(lineWidth: isThick ? 1.4 : 0.7, lineCap: .round))
                }

                let cx = size.width / 2, cy = size.height / 2
                let pr: CGFloat = 5
                context.fill(Path(ellipseIn: CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2)),
                             with: .color(tint.opacity(0.55)))
                context.fill(Path(ellipseIn: CGRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3)),
                             with: .color(Color.white.opacity(0.50)))
            }
        }
    }

    /// Style 5 — Soft overlapping watercolor circles with a category icon.
    private func placeholderWatercolorWash(types: [String], seed: UInt64) -> some View {
        let icon = placeholderCategoryIcon(for: types)

        return ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.90)

            Canvas { context, size in
                var rng = SeededRNG(seed: seed ^ 0x666)
                let palette: [Color] = [
                    Color(red: 0.72, green: 0.82, blue: 0.85),
                    Color(red: 0.85, green: 0.78, blue: 0.70),
                    Color(red: 0.80, green: 0.72, blue: 0.78),
                    Color(red: 0.75, green: 0.83, blue: 0.73),
                    Color(red: 0.88, green: 0.80, blue: 0.68)
                ]
                for _ in 0..<Int.random(in: 5...8, using: &rng) {
                    let cx = CGFloat.random(in: 0...size.width, using: &rng)
                    let cy = CGFloat.random(in: 0...size.height, using: &rng)
                    let r = CGFloat.random(in: 20...55, using: &rng)
                    let color = palette[Int.random(in: 0..<palette.count, using: &rng)]
                    context.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .color(color.opacity(Double.random(in: 0.12...0.28, using: &rng))))
                }
            }

            Image(systemName: icon)
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private func polaroidPlaceholder(trip: Trip) -> some View {
        TripCoverPlaceholderView(seedKey: trip.id, title: trip.name, caption: "No cover photo")
    }
}

// MARK: - Scroll Target Behavior

/// Snaps to trip pages while within the trips zone; leaves the scroll free
/// once the user has scrolled past all trips into the orphaned content section.
private struct TripCardSnapBehavior: ScrollTargetBehavior {
    let tripCount: Int
    let pageHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard tripCount > 0, pageHeight > 0 else { return }

        let maxTripOffset = CGFloat(tripCount - 1) * pageHeight
        let proposedOffset = target.rect.minY

        // Beyond the last trip page by more than half a page → free scroll (orphaned content)
        guard proposedOffset <= maxTripOffset + pageHeight * 0.5 else { return }

        // Within the trips zone → snap to nearest trip page
        let nearestPage = (proposedOffset / pageHeight).rounded()
        let clampedPage = max(0, min(CGFloat(tripCount - 1), nearestPage))
        target.rect.origin.y = clampedPage * pageHeight
    }
}

// MARK: - Seeded RNG

/// Deterministic RNG so decorative textures stay stable.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // xorshift64 requires a non-zero state; fall back to a constant if 0
        state = seed == 0 ? 0x5DEECE66D : seed
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

/// Dotted S-curve connecting card centers with map-pin markers.
private struct PolaroidTrailLine: View {
    let cardCenters: [Int: CGFloat]  // index -> midY
    let count: Int
    let phase: CGFloat
    var lineColor: Color = Color(red: 0.80, green: 0.45, blue: 0.35)

    var body: some View {
        Canvas { context, size in
            let sortedIndices = (0..<count).filter { cardCenters[$0] != nil }.sorted()
            guard sortedIndices.count >= 2 else { return }

            let strokeColor = lineColor.opacity(0.40)
            let pinColor = lineColor.opacity(0.55)
            let dashStyle = StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6], dashPhase: phase)
            let midX = size.width / 2

            var points: [CGPoint] = []
            for (i, index) in sortedIndices.enumerated() {
                guard let y = cardCenters[index] else { continue }
                let xOffset: CGFloat = i.isMultiple(of: 2) ? -36 : 36
                points.append(CGPoint(x: midX + xOffset, y: y))
            }
            guard points.count >= 2 else { return }

            // Draw the dashed S-curve
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

            // Draw map-pin markers at each stop
            for point in points {
                // Pin head (circle)
                let r: CGFloat = 5.5
                let dotRect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(pinColor))

                // Pin highlight
                let hr: CGFloat = 2
                let highlightRect = CGRect(x: point.x - r * 0.35, y: point.y - r * 0.35, width: hr, height: hr)
                context.fill(Path(ellipseIn: highlightRect), with: .color(Color.white.opacity(0.40)))

                // Pin point (small triangle below)
                var pin = Path()
                pin.move(to: CGPoint(x: point.x - 3.5, y: point.y + r - 1))
                pin.addLine(to: CGPoint(x: point.x, y: point.y + r + 7))
                pin.addLine(to: CGPoint(x: point.x + 3.5, y: point.y + r - 1))
                pin.closeSubpath()
                context.fill(pin, with: .color(pinColor))
            }
        }
        .allowsHitTesting(false)
    }
}
