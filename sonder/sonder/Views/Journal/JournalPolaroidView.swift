//
//  JournalPolaroidView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Vertical Polaroid feed — cards scale up as they scroll into focus,
/// connected by a playful dotted curvy line.
struct JournalPolaroidView: View {
    let trips: [Trip]
    let allLogs: [Log]
    let places: [Place]
    let orphanedLogs: [Log]
    @Binding var selectedTrip: Trip?
    @Binding var selectedLog: Log?
    var backgroundStyle: PolaroidBackgroundStyle = .tripPhotos

    @State private var cardCenters: [Int: CGFloat] = [:]  // index → midY in scroll
    @State private var cardProximities: [Int: CGFloat] = [:]  // index → 0 (centered) to 1 (far)
    @State private var viewportHeight: CGFloat = 0
    @State private var trailPhase: CGFloat = 0
    @State private var twinklePhase: CGFloat = 0
    @State private var scrolledID: String?
    /// Random seed created once per view lifetime — different each app launch
    @State private var sessionSeed: UInt64 = .random(in: 0..<UInt64.max)

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    /// Pre-grouped logs by tripID — O(L) once instead of O(T×L) per render
    private var logsByTripID: [String: [Log]] {
        Dictionary(grouping: allLogs.filter { $0.tripID != nil }, by: { $0.tripID! })
    }

    private func logsForTrip(_ trip: Trip) -> [Log] {
        logsByTripID[trip.id] ?? []
    }

    /// Stable slight rotation per card for that "pinned to a board" feel
    private func rotation(for trip: Trip) -> Double {
        let seed = abs(trip.id.hashValue)
        return Double(seed % 5) - 2.0  // -2 to +2 degrees
    }

    /// Trail line color that works on each background
    private var trailLineColor: Color {
        switch backgroundStyle {
        case .tripPhotos:  return Color.white
        case .starryNight: return Color(red: 0.70, green: 0.75, blue: 1.0)
        case .neonCity:    return Color(red: 1.0, green: 0.30, blue: 0.70)
        case .clothesline: return Color(red: 0.95, green: 0.80, blue: 0.55)
        case .underwater:  return Color(red: 0.60, green: 0.90, blue: 0.95)
        case .confetti:    return Color(red: 0.90, green: 0.40, blue: 0.50)
        case .botanical:   return Color(red: 0.75, green: 0.90, blue: 0.65)
        }
    }

    var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                // Background layer
                polaroidBackground(size: outerGeo.size)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            // Curvy dotted trail line (background layer)
                            PolaroidTrailLine(
                                cardCenters: cardCenters,
                                count: trips.count,
                                phase: trailPhase,
                                lineColor: trailLineColor
                            )
                            .allowsHitTesting(false)

                            // Polaroid cards
                            LazyVStack(spacing: 60) {
                                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                                    GeometryReader { cardGeo in
                                        let midY = cardGeo.frame(in: .global).midY
                                        let screenMid = outerGeo.size.height / 2
                                        let distance = abs(midY - screenMid)
                                        let maxDistance: CGFloat = outerGeo.size.height * 0.45
                                        let normalizedDistance = min(distance / maxDistance, 1.0)

                                        // Scale: 1.05 at center, 0.78 at edges
                                        let scale = 1.05 - normalizedDistance * 0.27
                                        // Opacity: 1.0 at center, 0.5 at edges
                                        let opacity = 1.0 - normalizedDistance * 0.5

                                        polaroidCard(trip: trip, index: index)
                                            .scaleEffect(scale)
                                            .opacity(opacity)
                                            .rotationEffect(.degrees(rotation(for: trip) * normalizedDistance))
                                            .animation(.easeOut(duration: 0.15), value: scale)
                                            .onAppear {
                                                let localMid = cardGeo.frame(in: .named("polaroidScroll")).midY
                                                cardCenters[index] = localMid
                                                cardProximities[index] = normalizedDistance
                                            }
                                            .onChange(of: midY) { _, _ in
                                                // Only update state when proximity changes enough to matter visually
                                                let oldProximity = cardProximities[index] ?? 1.0
                                                if abs(normalizedDistance - oldProximity) > 0.05 {
                                                    let localMid = cardGeo.frame(in: .named("polaroidScroll")).midY
                                                    cardCenters[index] = localMid
                                                    cardProximities[index] = normalizedDistance
                                                }
                                            }
                                    }
                                    .frame(height: 380)
                                }
                            }
                            .scrollTargetLayout()
                            // Insets so first/last card can reach screen center
                            .padding(.top, (outerGeo.size.height - 380) / 2)
                            .padding(.bottom, trips.isEmpty ? 0 : (outerGeo.size.height - 380) / 2)
                        }
                        .coordinateSpace(name: "polaroidScroll")

                        // Orphaned logs — mini Polaroid cards outside the proximity-scale zone
                        if !orphanedLogs.isEmpty {
                            orphanedLogsSection
                        }
                    }
                }
                .scrollTargetBehavior(GentleCardSnap(cardHeight: 380, spacing: 60))
                .scrollPosition(id: $scrolledID)
            }
            .onAppear {
                viewportHeight = outerGeo.size.height
                if scrolledID == nil {
                    scrolledID = trips.first?.id
                }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    trailPhase = -24
                }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    twinklePhase = 1.0
                }
            }
            .onChange(of: scrolledID) { oldValue, _ in
                // Skip the initial assignment
                guard oldValue != nil else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
            }
        }
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private func polaroidBackground(size: CGSize) -> some View {
        switch backgroundStyle {
        case .tripPhotos:  tripPhotosBackground(size: size)
        case .starryNight: starryNightBackground(size: size)
        case .neonCity:    neonCityBackground(size: size)
        case .clothesline: clotheslineBackground(size: size)
        case .underwater:  underwaterBackground(size: size)
        case .confetti:    confettiBackground(size: size)
        case .botanical:   botanicalBackground(size: size)
        }
    }

    // MARK: Dynamic Trip Photos — a different log photo crossfades per trip

    /// Pick a random photo from the trip's logs that ISN'T the cover photo.
    /// The selection is stable within a session but different each app launch.
    private func backgroundPhotoURL(for trip: Trip) -> URL? {
        let logs = logsForTrip(trip)
        let coverURL = trip.coverPhotoURL

        let allPhotos = logs.flatMap { $0.userPhotoURLs }
        let candidates = allPhotos.filter { $0 != coverURL }
        let pool = candidates.isEmpty ? allPhotos : candidates

        guard !pool.isEmpty else { return nil }

        // Stable random pick: combine session seed with trip identity
        let tripBits = UInt64(bitPattern: Int64(trip.id.hashValue))
        let pick = Int((sessionSeed ^ tripBits) % UInt64(pool.count))
        return URL(string: pool[pick])
    }

    private func tripPhotosBackground(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.08, green: 0.07, blue: 0.06)

            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                let isFocused = trip.id == scrolledID
                let proximity = isFocused ? 0.0 : (cardProximities[index] ?? 1.0)
                let bgOpacity = max(0, 1.0 - proximity * 1.8)

                if bgOpacity > 0.01 {
                    if let url = backgroundPhotoURL(for: trip) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 500, height: 900)) {
                            tripColorFallback(for: trip)
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .opacity(bgOpacity)
                        .animation(.easeOut(duration: 0.4), value: bgOpacity)
                    } else {
                        tripColorFallback(for: trip)
                            .frame(width: size.width, height: size.height)
                            .opacity(bgOpacity)
                            .animation(.easeOut(duration: 0.4), value: bgOpacity)
                    }
                }
            }

            // Gradient overlay so the white Polaroid card reads on any photo
            LinearGradient(
                colors: [
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func tripColorFallback(for trip: Trip) -> some View {
        let hash = abs(trip.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.3, brightness: 0.25)
    }

    // MARK: 1. Starry Night — deep sky with stars, moon, and aurora wisps

    private func starryNightBackground(size: CGSize) -> some View {
        ZStack {
            // Deep sky gradient
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.15),
                    Color(red: 0.06, green: 0.08, blue: 0.22),
                    Color(red: 0.10, green: 0.06, blue: 0.25),
                    Color(red: 0.05, green: 0.03, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Stars + shooting star + moon
            Canvas { context, canvasSize in
                var rng = SeededRNG(seed: 42)

                // Stars — varying sizes and brightness
                for _ in 0..<250 {
                    let x = CGFloat.random(in: 0...canvasSize.width, using: &rng)
                    let y = CGFloat.random(in: 0...canvasSize.height, using: &rng)
                    let r = CGFloat.random(in: 0.5...2.5, using: &rng)
                    let brightness = Double.random(in: 0.3...1.0, using: &rng)

                    // Star colors: white, pale blue, pale yellow
                    let colorChoice = Int.random(in: 0...2, using: &rng)
                    let starColor: Color = switch colorChoice {
                    case 0: Color.white.opacity(brightness)
                    case 1: Color(red: 0.8, green: 0.85, blue: 1.0).opacity(brightness)
                    default: Color(red: 1.0, green: 0.95, blue: 0.8).opacity(brightness)
                    }

                    // Larger stars get a cross-shaped twinkle
                    if r > 1.8 {
                        let spikeLen = r * 2.5
                        var spike = Path()
                        spike.move(to: CGPoint(x: x - spikeLen, y: y))
                        spike.addLine(to: CGPoint(x: x + spikeLen, y: y))
                        spike.move(to: CGPoint(x: x, y: y - spikeLen))
                        spike.addLine(to: CGPoint(x: x, y: y + spikeLen))
                        context.stroke(spike, with: .color(starColor.opacity(0.4)), lineWidth: 0.5)
                    }

                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(starColor))
                }

                // Crescent moon
                let moonCenter = CGPoint(x: canvasSize.width * 0.82, y: canvasSize.height * 0.08)
                let moonR: CGFloat = 22
                let moonRect = CGRect(x: moonCenter.x - moonR, y: moonCenter.y - moonR, width: moonR * 2, height: moonR * 2)
                context.fill(Path(ellipseIn: moonRect), with: .color(Color(red: 0.95, green: 0.92, blue: 0.80).opacity(0.9)))
                // Cut out crescent
                let cutRect = CGRect(x: moonCenter.x - moonR + 10, y: moonCenter.y - moonR - 4, width: moonR * 2, height: moonR * 2)
                context.fill(Path(ellipseIn: cutRect), with: .color(Color(red: 0.04, green: 0.04, blue: 0.15)))
                // Moon glow
                let glowRect = CGRect(x: moonCenter.x - moonR * 2.5, y: moonCenter.y - moonR * 2.5, width: moonR * 5, height: moonR * 5)
                context.fill(
                    Path(ellipseIn: glowRect),
                    with: .color(Color(red: 0.95, green: 0.92, blue: 0.80).opacity(0.04))
                )

                // Shooting star
                var shootingStar = Path()
                shootingStar.move(to: CGPoint(x: canvasSize.width * 0.15, y: canvasSize.height * 0.12))
                shootingStar.addLine(to: CGPoint(x: canvasSize.width * 0.30, y: canvasSize.height * 0.06))
                context.stroke(
                    shootingStar,
                    with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0)]),
                        startPoint: CGPoint(x: canvasSize.width * 0.15, y: canvasSize.height * 0.12),
                        endPoint: CGPoint(x: canvasSize.width * 0.30, y: canvasSize.height * 0.06)
                    ),
                    lineWidth: 1.5
                )
            }

            // Aurora wisps — colorful translucent bands
            Canvas { context, canvasSize in
                let auroraColors: [(Color, CGFloat)] = [
                    (Color(red: 0.2, green: 0.8, blue: 0.5).opacity(0.06), canvasSize.height * 0.25),
                    (Color(red: 0.3, green: 0.5, blue: 0.9).opacity(0.05), canvasSize.height * 0.32),
                    (Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.04), canvasSize.height * 0.38),
                ]
                for (color, baseY) in auroraColors {
                    var path = Path()
                    path.move(to: CGPoint(x: -20, y: baseY))
                    let segments = 10
                    for s in 0...segments {
                        let x = canvasSize.width * CGFloat(s) / CGFloat(segments)
                        let waveY = baseY + sin(CGFloat(s) * 0.8) * 30
                        path.addLine(to: CGPoint(x: x, y: waveY))
                    }
                    path.addLine(to: CGPoint(x: canvasSize.width + 20, y: baseY + 60))
                    path.addLine(to: CGPoint(x: -20, y: baseY + 60))
                    path.closeSubpath()
                    context.fill(path, with: .color(color))
                }
            }
        }
    }

    // MARK: 2. Neon City — dark backdrop with glowing neon signs and reflections

    private func neonCityBackground(size: CGSize) -> some View {
        ZStack {
            // Dark city night
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.05, blue: 0.10),
                    Color(red: 0.08, green: 0.06, blue: 0.14),
                    Color(red: 0.05, green: 0.04, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Neon signs and glow effects
            Canvas { context, canvasSize in
                var rng = SeededRNG(seed: 77)

                // Neon glow circles — scattered ambient light pools
                let neonColors: [Color] = [
                    Color(red: 1.0, green: 0.2, blue: 0.6),   // hot pink
                    Color(red: 0.2, green: 0.8, blue: 1.0),   // cyan
                    Color(red: 0.9, green: 0.3, blue: 1.0),   // purple
                    Color(red: 1.0, green: 0.9, blue: 0.2),   // yellow
                    Color(red: 0.2, green: 1.0, blue: 0.6),   // green
                ]

                // Large ambient glow pools
                for _ in 0..<8 {
                    let x = CGFloat.random(in: -50...canvasSize.width + 50, using: &rng)
                    let y = CGFloat.random(in: 0...canvasSize.height, using: &rng)
                    let r = CGFloat.random(in: 80...200, using: &rng)
                    let colorIdx = Int.random(in: 0..<neonColors.count, using: &rng)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(neonColors[colorIdx].opacity(0.04))
                    )
                }

                // Neon tube lines — horizontal bars like signs
                for _ in 0..<12 {
                    let x = CGFloat.random(in: 20...canvasSize.width - 20, using: &rng)
                    let y = CGFloat.random(in: 20...canvasSize.height - 20, using: &rng)
                    let length = CGFloat.random(in: 40...120, using: &rng)
                    let isHorizontal = Bool.random(using: &rng)
                    let colorIdx = Int.random(in: 0..<neonColors.count, using: &rng)
                    let color = neonColors[colorIdx]

                    let endPoint = isHorizontal
                        ? CGPoint(x: x + length, y: y)
                        : CGPoint(x: x, y: y + length)

                    // Outer glow
                    var glowPath = Path()
                    glowPath.move(to: CGPoint(x: x, y: y))
                    glowPath.addLine(to: endPoint)
                    context.stroke(glowPath, with: .color(color.opacity(0.08)), lineWidth: 12)
                    context.stroke(glowPath, with: .color(color.opacity(0.12)), lineWidth: 6)

                    // Core bright line
                    var corePath = Path()
                    corePath.move(to: CGPoint(x: x, y: y))
                    corePath.addLine(to: endPoint)
                    context.stroke(corePath, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    // Hot center
                    context.stroke(corePath, with: .color(Color.white.opacity(0.3)), lineWidth: 0.8)
                }

                // Neon circles (like a bar sign)
                for _ in 0..<4 {
                    let cx = CGFloat.random(in: 40...canvasSize.width - 40, using: &rng)
                    let cy = CGFloat.random(in: 40...canvasSize.height - 40, using: &rng)
                    let r = CGFloat.random(in: 15...35, using: &rng)
                    let colorIdx = Int.random(in: 0..<neonColors.count, using: &rng)
                    let color = neonColors[colorIdx]

                    let circleRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    let circlePath = Path(ellipseIn: circleRect)
                    // Glow
                    let glowRect = CGRect(x: cx - r - 6, y: cy - r - 6, width: (r + 6) * 2, height: (r + 6) * 2)
                    context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.06)))
                    context.stroke(circlePath, with: .color(color.opacity(0.4)), lineWidth: 2)
                    context.stroke(circlePath, with: .color(Color.white.opacity(0.15)), lineWidth: 0.5)
                }

                // Rain streaks for atmosphere
                for _ in 0..<60 {
                    let x = CGFloat.random(in: 0...canvasSize.width, using: &rng)
                    let y = CGFloat.random(in: 0...canvasSize.height, using: &rng)
                    let length = CGFloat.random(in: 8...25, using: &rng)
                    var rainPath = Path()
                    rainPath.move(to: CGPoint(x: x, y: y))
                    rainPath.addLine(to: CGPoint(x: x - 1, y: y + length))
                    context.stroke(rainPath, with: .color(Color.white.opacity(Double.random(in: 0.03...0.08, using: &rng))), lineWidth: 0.5)
                }
            }

            // Wet ground reflection at bottom
            LinearGradient(
                colors: [.clear, .clear, Color(red: 0.3, green: 0.15, blue: 0.4).opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: 3. Clothesline at Sunset — warm sky with string lights and clotheslines

    private func clotheslineBackground(size: CGSize) -> some View {
        ZStack {
            // Sunset gradient
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.12, blue: 0.30),  // deep purple top
                    Color(red: 0.45, green: 0.20, blue: 0.40),  // purple-pink
                    Color(red: 0.85, green: 0.40, blue: 0.35),  // warm coral
                    Color(red: 0.95, green: 0.65, blue: 0.35),  // golden orange
                    Color(red: 0.98, green: 0.85, blue: 0.60)   // pale gold horizon
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Clotheslines, clothespins, and string lights
            Canvas { context, canvasSize in
                var rng = SeededRNG(seed: 55)
                let lineColor = Color.black.opacity(0.15)

                // Clotheslines — horizontal with slight sag
                let lineYPositions: [CGFloat] = [
                    canvasSize.height * 0.12,
                    canvasSize.height * 0.35,
                    canvasSize.height * 0.58,
                    canvasSize.height * 0.80,
                ]

                for (lineIdx, baseY) in lineYPositions.enumerated() {
                    // Draw sagging line
                    var linePath = Path()
                    linePath.move(to: CGPoint(x: -10, y: baseY))
                    let midSag = baseY + 12  // slight droop in middle
                    linePath.addQuadCurve(
                        to: CGPoint(x: canvasSize.width + 10, y: baseY),
                        control: CGPoint(x: canvasSize.width / 2, y: midSag)
                    )
                    context.stroke(linePath, with: .color(lineColor), lineWidth: 1.2)

                    // String lights along the line
                    let bulbCount = Int.random(in: 8...14, using: &rng)
                    let bulbColors: [Color] = [
                        Color(red: 1.0, green: 0.95, blue: 0.70),  // warm white
                        Color(red: 1.0, green: 0.80, blue: 0.50),  // amber
                        Color(red: 1.0, green: 0.70, blue: 0.65),  // soft red
                        Color(red: 0.80, green: 0.90, blue: 1.0),  // cool white
                    ]

                    for b in 0..<bulbCount {
                        let t = CGFloat(b + 1) / CGFloat(bulbCount + 1)
                        let bulbX = canvasSize.width * t
                        // Position on the sagging curve
                        let bulbY = baseY + 12 * sin(t * .pi) + CGFloat.random(in: -2...2, using: &rng)
                        let wireEndY = bulbY + CGFloat.random(in: 6...14, using: &rng)

                        // Wire to bulb
                        var wirePath = Path()
                        wirePath.move(to: CGPoint(x: bulbX, y: bulbY))
                        wirePath.addLine(to: CGPoint(x: bulbX, y: wireEndY))
                        context.stroke(wirePath, with: .color(lineColor), lineWidth: 0.5)

                        // Bulb glow
                        let glowR: CGFloat = CGFloat.random(in: 10...18, using: &rng)
                        let glowRect = CGRect(x: bulbX - glowR, y: wireEndY - glowR, width: glowR * 2, height: glowR * 2)
                        let colorIdx = Int.random(in: 0..<bulbColors.count, using: &rng)
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(bulbColors[colorIdx].opacity(lineIdx < 2 ? 0.15 : 0.10))
                        )

                        // Bright bulb center
                        let bulbR: CGFloat = 3
                        let bulbRect = CGRect(x: bulbX - bulbR, y: wireEndY - bulbR, width: bulbR * 2, height: bulbR * 2)
                        context.fill(
                            Path(ellipseIn: bulbRect),
                            with: .color(bulbColors[colorIdx].opacity(0.8))
                        )
                    }
                }

                // Silhouette birds in the distance
                let birdPositions: [(CGFloat, CGFloat)] = [
                    (canvasSize.width * 0.25, canvasSize.height * 0.06),
                    (canvasSize.width * 0.30, canvasSize.height * 0.05),
                    (canvasSize.width * 0.70, canvasSize.height * 0.15),
                    (canvasSize.width * 0.73, canvasSize.height * 0.14),
                    (canvasSize.width * 0.76, canvasSize.height * 0.155),
                ]
                for (bx, by) in birdPositions {
                    var bird = Path()
                    bird.move(to: CGPoint(x: bx - 6, y: by + 3))
                    bird.addQuadCurve(to: CGPoint(x: bx, y: by), control: CGPoint(x: bx - 3, y: by - 2))
                    bird.addQuadCurve(to: CGPoint(x: bx + 6, y: by + 3), control: CGPoint(x: bx + 3, y: by - 2))
                    context.stroke(bird, with: .color(Color.black.opacity(0.2)), lineWidth: 1)
                }
            }
        }
    }

    // MARK: 4. Underwater — deep ocean with caustics, bubbles, and kelp

    private func underwaterBackground(size: CGSize) -> some View {
        ZStack {
            // Ocean depth gradient
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.35, blue: 0.55),  // surface light
                    Color(red: 0.06, green: 0.22, blue: 0.42),
                    Color(red: 0.04, green: 0.15, blue: 0.32),
                    Color(red: 0.02, green: 0.08, blue: 0.20)   // deep
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Light caustics from surface
            Canvas { context, canvasSize in
                var rng = SeededRNG(seed: 33)

                // Caustic light rays from top
                for _ in 0..<15 {
                    let topX = CGFloat.random(in: -20...canvasSize.width + 20, using: &rng)
                    let rayWidth = CGFloat.random(in: 20...60, using: &rng)
                    let rayLength = CGFloat.random(in: canvasSize.height * 0.3...canvasSize.height * 0.7, using: &rng)
                    let drift = CGFloat.random(in: -30...30, using: &rng)

                    var rayPath = Path()
                    rayPath.move(to: CGPoint(x: topX - rayWidth / 2, y: 0))
                    rayPath.addLine(to: CGPoint(x: topX + rayWidth / 2, y: 0))
                    rayPath.addLine(to: CGPoint(x: topX + drift + rayWidth / 4, y: rayLength))
                    rayPath.addLine(to: CGPoint(x: topX + drift - rayWidth / 4, y: rayLength))
                    rayPath.closeSubpath()

                    context.fill(
                        rayPath,
                        with: .color(Color(red: 0.4, green: 0.8, blue: 0.9).opacity(Double.random(in: 0.02...0.06, using: &rng)))
                    )
                }

                // Caustic network — wavy bright lines like light through water surface
                for _ in 0..<25 {
                    let startX = CGFloat.random(in: 0...canvasSize.width, using: &rng)
                    let startY = CGFloat.random(in: 0...canvasSize.height * 0.5, using: &rng)
                    var causticPath = Path()
                    causticPath.move(to: CGPoint(x: startX, y: startY))
                    let segments = Int.random(in: 3...6, using: &rng)
                    for _ in 0..<segments {
                        let dx = CGFloat.random(in: -40...40, using: &rng)
                        let dy = CGFloat.random(in: -20...20, using: &rng)
                        let cx = CGFloat.random(in: -25...25, using: &rng)
                        let cy = CGFloat.random(in: -15...15, using: &rng)
                        causticPath.addQuadCurve(
                            to: CGPoint(x: startX + dx, y: startY + dy),
                            control: CGPoint(x: startX + cx, y: startY + cy)
                        )
                    }
                    let opacity = Double.random(in: 0.03...0.08, using: &rng)
                    context.stroke(causticPath, with: .color(Color(red: 0.5, green: 0.9, blue: 1.0).opacity(opacity)), lineWidth: CGFloat.random(in: 1...3, using: &rng))
                }

                // Bubbles — various sizes, lighter toward top
                for _ in 0..<50 {
                    let bx = CGFloat.random(in: 0...canvasSize.width, using: &rng)
                    let by = CGFloat.random(in: 0...canvasSize.height, using: &rng)
                    let br = CGFloat.random(in: 2...10, using: &rng)
                    let depthFactor = 1.0 - Double(by / canvasSize.height) * 0.5
                    let bubbleOpacity = Double.random(in: 0.08...0.20, using: &rng) * depthFactor

                    let bubbleRect = CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)
                    context.stroke(
                        Path(ellipseIn: bubbleRect),
                        with: .color(Color.white.opacity(bubbleOpacity)),
                        lineWidth: 0.8
                    )
                    // Specular highlight
                    let specR = br * 0.3
                    let specRect = CGRect(x: bx - br * 0.3, y: by - br * 0.4, width: specR * 2, height: specR * 2)
                    context.fill(Path(ellipseIn: specRect), with: .color(Color.white.opacity(bubbleOpacity * 0.6)))
                }

                // Kelp / seaweed at bottom
                for i in 0..<6 {
                    let baseX = CGFloat(i) * canvasSize.width / 5.0 + CGFloat.random(in: -20...20, using: &rng)
                    let baseY = canvasSize.height
                    let height = CGFloat.random(in: canvasSize.height * 0.15...canvasSize.height * 0.35, using: &rng)

                    var kelpPath = Path()
                    kelpPath.move(to: CGPoint(x: baseX, y: baseY))
                    let kelpSegments = 6
                    for s in 1...kelpSegments {
                        let progress = CGFloat(s) / CGFloat(kelpSegments)
                        let swayX = sin(progress * .pi * 1.5) * CGFloat.random(in: 10...25, using: &rng)
                        kelpPath.addQuadCurve(
                            to: CGPoint(x: baseX + swayX, y: baseY - height * progress),
                            control: CGPoint(x: baseX + swayX * 1.3, y: baseY - height * (progress - 0.05))
                        )
                    }
                    context.stroke(
                        kelpPath,
                        with: .color(Color(red: 0.1, green: 0.35, blue: 0.2).opacity(Double.random(in: 0.15...0.30, using: &rng))),
                        lineWidth: CGFloat.random(in: 3...6, using: &rng)
                    )
                }
            }
        }
    }

    // MARK: 5. Confetti — bright festive explosion of color

    private func confettiBackground(size: CGSize) -> some View {
        ZStack {
            // Bright warm base
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.90),
                    Color(red: 1.0, green: 0.94, blue: 0.88),
                    Color(red: 0.98, green: 0.92, blue: 0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Confetti pieces — rectangles, circles, squiggles
            Canvas { context, canvasSize in
                var rng = SeededRNG(seed: 99)

                let confettiColors: [Color] = [
                    Color(red: 1.0, green: 0.35, blue: 0.45),   // red
                    Color(red: 1.0, green: 0.65, blue: 0.20),   // orange
                    Color(red: 1.0, green: 0.88, blue: 0.20),   // yellow
                    Color(red: 0.30, green: 0.80, blue: 0.50),   // green
                    Color(red: 0.30, green: 0.60, blue: 1.0),   // blue
                    Color(red: 0.70, green: 0.35, blue: 0.90),   // purple
                    Color(red: 1.0, green: 0.50, blue: 0.70),   // pink
                    Color(red: 0.20, green: 0.85, blue: 0.85),   // teal
                ]

                // Rectangles (paper confetti)
                for _ in 0..<120 {
                    let x = CGFloat.random(in: -10...canvasSize.width + 10, using: &rng)
                    let y = CGFloat.random(in: -10...canvasSize.height + 10, using: &rng)
                    let w = CGFloat.random(in: 4...14, using: &rng)
                    let h = CGFloat.random(in: 8...20, using: &rng)
                    let angle = Double.random(in: 0...360, using: &rng)
                    let colorIdx = Int.random(in: 0..<confettiColors.count, using: &rng)
                    let opacity = Double.random(in: 0.15...0.45, using: &rng)

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: x + w / 2, y: y + h / 2)
                    transform = transform.rotated(by: angle * .pi / 180)
                    transform = transform.translatedBy(x: -(x + w / 2), y: -(y + h / 2))

                    var rectPath = Path(CGRect(x: x, y: y, width: w, height: h))
                    rectPath = rectPath.applying(transform)
                    context.fill(rectPath, with: .color(confettiColors[colorIdx].opacity(opacity)))
                }

                // Circles (dot confetti)
                for _ in 0..<60 {
                    let x = CGFloat.random(in: 0...canvasSize.width, using: &rng)
                    let y = CGFloat.random(in: 0...canvasSize.height, using: &rng)
                    let r = CGFloat.random(in: 2...7, using: &rng)
                    let colorIdx = Int.random(in: 0..<confettiColors.count, using: &rng)
                    let opacity = Double.random(in: 0.15...0.40, using: &rng)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(confettiColors[colorIdx].opacity(opacity)))
                }

                // Squiggles (streamer ribbons)
                for _ in 0..<20 {
                    let startX = CGFloat.random(in: 0...canvasSize.width, using: &rng)
                    let startY = CGFloat.random(in: 0...canvasSize.height, using: &rng)
                    let colorIdx = Int.random(in: 0..<confettiColors.count, using: &rng)
                    let opacity = Double.random(in: 0.12...0.30, using: &rng)

                    var squiggle = Path()
                    squiggle.move(to: CGPoint(x: startX, y: startY))
                    let segs = Int.random(in: 3...5, using: &rng)
                    var curX = startX
                    var curY = startY
                    for _ in 0..<segs {
                        let dx = CGFloat.random(in: -20...20, using: &rng)
                        let dy = CGFloat.random(in: 10...25, using: &rng)
                        squiggle.addQuadCurve(
                            to: CGPoint(x: curX + dx, y: curY + dy),
                            control: CGPoint(x: curX + dx * 2, y: curY + dy / 2)
                        )
                        curX += dx
                        curY += dy
                    }
                    context.stroke(
                        squiggle,
                        with: .color(confettiColors[colorIdx].opacity(opacity)),
                        lineWidth: CGFloat.random(in: 1.5...3.0, using: &rng)
                    )
                }
            }
        }
    }

    // MARK: 6. Botanical — lush dark garden with vines, leaves, and flowers

    private func botanicalBackground(size: CGSize) -> some View {
        ZStack {
            // Deep rich green-black base
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.12, blue: 0.08),
                    Color(red: 0.08, green: 0.15, blue: 0.10),
                    Color(red: 0.05, green: 0.10, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Vines, leaves, flowers
            Canvas { context, canvasSize in
                var rng = SeededRNG(seed: 66)

                let leafGreen = Color(red: 0.20, green: 0.45, blue: 0.22)
                let darkGreen = Color(red: 0.12, green: 0.30, blue: 0.15)
                let vineColor = Color(red: 0.15, green: 0.28, blue: 0.14)

                // Main vines crawling from edges
                let vineStarts: [(CGFloat, CGFloat, Bool)] = [
                    (0, canvasSize.height * 0.1, true),       // left edge, going right
                    (canvasSize.width, canvasSize.height * 0.3, false),  // right edge, going left
                    (0, canvasSize.height * 0.55, true),
                    (canvasSize.width, canvasSize.height * 0.75, false),
                    (canvasSize.width * 0.3, 0, true),        // from top
                    (canvasSize.width * 0.7, canvasSize.height, false), // from bottom
                ]

                for (startX, startY, goesRight) in vineStarts {
                    let vineLength = CGFloat.random(in: canvasSize.width * 0.2...canvasSize.width * 0.45, using: &rng)
                    let segments = 8

                    var vinePath = Path()
                    vinePath.move(to: CGPoint(x: startX, y: startY))
                    var curX = startX
                    var curY = startY

                    for s in 1...segments {
                        let progress = CGFloat(s) / CGFloat(segments)
                        let dx = (goesRight ? 1.0 : -1.0) * vineLength / CGFloat(segments)
                        let dy = CGFloat.random(in: -25...25, using: &rng)
                        let cx = CGFloat.random(in: -15...15, using: &rng)
                        let cy = CGFloat.random(in: -15...15, using: &rng)
                        vinePath.addQuadCurve(
                            to: CGPoint(x: curX + dx, y: curY + dy),
                            control: CGPoint(x: curX + dx / 2 + cx, y: curY + cy)
                        )

                        let leafX = curX + dx
                        let leafY = curY + dy

                        // Leaves along the vine
                        if Int.random(in: 0...2, using: &rng) < 2 {
                            let leafSize = CGFloat.random(in: 8...18, using: &rng)
                            let leafAngle = Double.random(in: -45...45, using: &rng)
                            let side: CGFloat = Bool.random(using: &rng) ? 1 : -1

                            // Leaf shape — pointed ellipse
                            var leafPath = Path()
                            let lx = leafX + side * leafSize * 0.3
                            let ly = leafY
                            leafPath.move(to: CGPoint(x: lx, y: ly))
                            leafPath.addQuadCurve(
                                to: CGPoint(x: lx + side * leafSize, y: ly),
                                control: CGPoint(x: lx + side * leafSize * 0.5, y: ly - leafSize * 0.5)
                            )
                            leafPath.addQuadCurve(
                                to: CGPoint(x: lx, y: ly),
                                control: CGPoint(x: lx + side * leafSize * 0.5, y: ly + leafSize * 0.4)
                            )

                            var transform = CGAffineTransform.identity
                            transform = transform.translatedBy(x: lx + side * leafSize * 0.5, y: ly)
                            transform = transform.rotated(by: leafAngle * .pi / 180)
                            transform = transform.translatedBy(x: -(lx + side * leafSize * 0.5), y: -ly)
                            leafPath = leafPath.applying(transform)

                            let leafOpacity = Double.random(in: 0.15...0.35, using: &rng) * Double(1.0 - progress * 0.3)
                            let isLighter = Bool.random(using: &rng)
                            context.fill(leafPath, with: .color((isLighter ? leafGreen : darkGreen).opacity(leafOpacity)))

                            // Leaf vein
                            var veinPath = Path()
                            veinPath.move(to: CGPoint(x: lx, y: ly))
                            veinPath.addLine(to: CGPoint(x: lx + side * leafSize * 0.8, y: ly))
                            veinPath = veinPath.applying(transform)
                            context.stroke(veinPath, with: .color(leafGreen.opacity(leafOpacity * 0.5)), lineWidth: 0.4)
                        }

                        curX = leafX
                        curY = leafY
                    }

                    let vineOpacity = Double.random(in: 0.20...0.40, using: &rng)
                    context.stroke(vinePath, with: .color(vineColor.opacity(vineOpacity)), lineWidth: CGFloat.random(in: 1.5...3.0, using: &rng))
                }

                // Small flowers scattered
                let flowerColors: [Color] = [
                    Color(red: 0.90, green: 0.60, blue: 0.65),   // dusty pink
                    Color(red: 0.95, green: 0.85, blue: 0.50),   // soft yellow
                    Color(red: 0.70, green: 0.60, blue: 0.85),   // lavender
                    Color(red: 0.95, green: 0.75, blue: 0.55),   // peach
                ]

                for _ in 0..<15 {
                    let fx = CGFloat.random(in: 20...canvasSize.width - 20, using: &rng)
                    let fy = CGFloat.random(in: 20...canvasSize.height - 20, using: &rng)
                    let colorIdx = Int.random(in: 0..<flowerColors.count, using: &rng)
                    let flowerSize = CGFloat.random(in: 3...8, using: &rng)
                    let opacity = Double.random(in: 0.15...0.35, using: &rng)

                    // 5-petal flower
                    for petal in 0..<5 {
                        let angle = Double(petal) * (360.0 / 5.0) * .pi / 180
                        let petalX = fx + cos(angle) * flowerSize
                        let petalY = fy + sin(angle) * flowerSize
                        let petalRect = CGRect(x: petalX - flowerSize * 0.4, y: petalY - flowerSize * 0.4, width: flowerSize * 0.8, height: flowerSize * 0.8)
                        context.fill(Path(ellipseIn: petalRect), with: .color(flowerColors[colorIdx].opacity(opacity)))
                    }
                    // Center
                    let centerRect = CGRect(x: fx - flowerSize * 0.25, y: fy - flowerSize * 0.25, width: flowerSize * 0.5, height: flowerSize * 0.5)
                    context.fill(Path(ellipseIn: centerRect), with: .color(Color(red: 0.95, green: 0.85, blue: 0.50).opacity(opacity * 0.8)))
                }
            }

            // Soft green fog/mist
            RadialGradient(
                colors: [
                    Color(red: 0.15, green: 0.30, blue: 0.15).opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.3, y: 0.5),
                startRadius: 50,
                endRadius: size.width * 0.6
            )
        }
    }

    // MARK: - Polaroid Frame Constants

    /// Real Polaroid proportions: thin border on top/left/right, thick strip at bottom
    private let frameBorder: CGFloat = 10        // top, left, right
    private let frameBottomStrip: CGFloat = 70   // thick bottom — the "writing" area
    private let frameRadius: CGFloat = 3

    /// Stable slight tilt for the handwriting per card
    private func writingTilt(for trip: Trip) -> Double {
        let seed = abs(trip.id.hashValue >> 4)
        return Double(seed % 5) - 2.0  // -2 to +2 degrees
    }

    /// First log photo URL for a trip (used when no cover photo exists)
    private func firstLogPhotoURL(for trip: Trip) -> URL? {
        let photos = logsForTrip(trip).flatMap { $0.userPhotoURLs }
        guard let first = photos.first else { return nil }
        return URL(string: first)
    }

    /// Caption details string: "5 places · Jun 2025"
    private func captionDetails(for trip: Trip) -> String {
        let logs = logsForTrip(trip)
        var parts: [String] = []
        parts.append("\(logs.count) place\(logs.count == 1 ? "" : "s")")
        if let start = trip.startDate {
            parts.append(start.formatted(.dateTime.month(.abbreviated).year()))
        }
        let mustSees = logs.filter { $0.rating == .mustSee }.count
        if mustSees > 0 {
            parts.append("\(mustSees) \(Rating.mustSee.emoji)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Polaroid Card

    private func polaroidCard(trip: Trip, index: Int) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            VStack(spacing: 0) {
                // Photo inset inside the white frame
                ZStack {
                    if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 600, height: 600)) {
                            polaroidPlaceholder(trip: trip)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else if let logPhotoURL = firstLogPhotoURL(for: trip) {
                        DownsampledAsyncImage(url: logPhotoURL, targetSize: CGSize(width: 600, height: 600)) {
                            polaroidPlaceholder(trip: trip)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        polaroidPlaceholder(trip: trip)
                    }
                }
                .frame(height: 280)
                .clipped()
                .padding(.top, frameBorder)
                .padding(.horizontal, frameBorder)

                // Bottom writing strip — Sharpie on matte Polaroid
                ZStack {
                    // Ink bleed layer — blurred duplicate underneath
                    sharpieText(trip: trip)
                        .blur(radius: 0.8)
                        .opacity(0.3)

                    // Crisp ink layer on top
                    sharpieText(trip: trip)
                }
                .rotationEffect(.degrees(writingTilt(for: trip)), anchor: .center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, frameBorder + 8)
                .padding(.top, 10)
                .frame(height: frameBottomStrip)
            }
            // Off-white Polaroid frame with very subtle warm tint
            .background(Color(red: 0.97, green: 0.96, blue: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: frameRadius))
            // Subtle inner shadow feel via border
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .padding(.horizontal, 28)
        }
        .buttonStyle(.plain)
    }

    private func sharpieText(trip: Trip) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(trip.name)
                .font(.custom("Marker Felt Wide", size: 22))
                .foregroundColor(.black.opacity(0.9))
                .lineLimit(1)

            Text(captionDetails(for: trip))
                .font(.custom("Marker Felt Wide", size: 14))
                .foregroundColor(.black.opacity(0.45))
                .lineLimit(1)
        }
    }

    // MARK: - Orphaned Logs Section

    private var orphanedLogsSection: some View {
        VStack(spacing: 16) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13))
                Text("Not in a trip")
                    .font(.custom("Marker Felt Wide", size: 15))
                Text("(\(orphanedLogs.count))")
                    .font(.custom("Marker Felt Wide", size: 13))
                    .opacity(0.5)
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.top, 20)

            // Mini Polaroid cards in a 2-column grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(orphanedLogs, id: \.id) { log in
                    miniPolaroidCard(log: log)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }

    private func miniPolaroidCard(log: Log) -> some View {
        let place = placesByID[log.placeID]
        return Button {
            selectedLog = log
        } label: {
            VStack(spacing: 0) {
                // Photo area
                ZStack {
                    if let urlString = log.photoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 300, height: 300)) {
                            miniPolaroidPlaceholder(log: log)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        miniPolaroidPlaceholder(log: log)
                    }
                }
                .frame(height: 120)
                .clipped()
                .padding(.top, 6)
                .padding(.horizontal, 6)

                // Bottom writing strip
                VStack(alignment: .center, spacing: 2) {
                    Text(place?.name ?? "Unknown Place")
                        .font(.custom("Marker Felt Wide", size: 13))
                        .foregroundColor(.black.opacity(0.85))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(log.rating.emoji)
                            .font(.system(size: 11))
                        Text(log.visitedAt.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.custom("Marker Felt Wide", size: 11))
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .background(Color(red: 0.97, green: 0.96, blue: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: frameRadius))
            .overlay(
                RoundedRectangle(cornerRadius: frameRadius)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
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
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func polaroidPlaceholder(trip: Trip) -> some View {
        // Slightly desaturated warm gradient — mimics an unexposed Polaroid
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.85, blue: 0.80),
                Color(red: 0.82, green: 0.78, blue: 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.5))
                Text(trip.name)
                    .font(.custom("Marker Felt Wide", size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Gentle Card Snap

/// Soft scroll-snap that settles on the nearest card center without
/// restricting fling distance. Feels like a gentle magnetic pull
/// rather than a hard page-lock.
private struct GentleCardSnap: ScrollTargetBehavior {
    let cardHeight: CGFloat
    let spacing: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let stride = cardHeight + spacing
        guard stride > 0 else { return }

        let y = target.rect.minY
        let nearestIndex = max(0, round(y / stride))
        target.rect.origin.y = nearestIndex * stride
    }
}

// MARK: - Seeded RNG for deterministic Canvas patterns

/// Simple seeded random number generator so Canvas backgrounds render consistently.
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

// MARK: - Curvy Trail Line

/// Draws a smooth dotted S-curve connecting Polaroid card centers.
private struct PolaroidTrailLine: View {
    let cardCenters: [Int: CGFloat]  // index → midY
    let count: Int
    let phase: CGFloat
    var lineColor: Color = Color(red: 0.80, green: 0.45, blue: 0.35)

    var body: some View {
        Canvas { context, size in
            let sortedIndices = (0..<count).filter { cardCenters[$0] != nil }.sorted()
            guard sortedIndices.count >= 2 else { return }

            let strokeColor = lineColor.opacity(0.3)
            let dotColor = lineColor.opacity(0.5)
            let dashStyle = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6], dashPhase: phase)

            let midX = size.width / 2

            var points: [CGPoint] = []
            for (i, index) in sortedIndices.enumerated() {
                guard let y = cardCenters[index] else { continue }
                // Zigzag: alternate left and right of center
                let xOffset: CGFloat = i.isMultiple(of: 2) ? -30 : 30
                points.append(CGPoint(x: midX + xOffset, y: y))
            }

            guard points.count >= 2 else { return }

            // Smooth bezier path through points
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

            // Dots at each node
            for (i, point) in points.enumerated() {
                let r: CGFloat = i == 0 ? 5 : 4
                let dotRect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            }
        }
        .allowsHitTesting(false)
    }
}
