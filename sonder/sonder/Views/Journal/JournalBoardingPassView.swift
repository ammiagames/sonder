//
//  JournalBoardingPassView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Boarding pass stack — each trip styled as a clean airline boarding pass
/// with the trip cover photo and essential info only.
struct JournalBoardingPassView: View {
    let trips: [Trip]
    let allLogs: [Log]
    let places: [Place]
    let orphanedLogs: [Log]
    @Binding var selectedTrip: Trip?
    @Binding var selectedLog: Log?
    @State private var showOrphanedLogs: Bool = true

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var logsByTripID: [String: [Log]] {
        Dictionary(grouping: allLogs.filter { $0.tripID != nil }, by: { $0.tripID ?? "" })
    }

    private func logsForTrip(_ trip: Trip) -> [Log] {
        logsByTripID[trip.id] ?? []
    }

    /// Derive the destination from the most common city in the trip
    private func destinationCity(for trip: Trip) -> String {
        let logs = logsForTrip(trip)
        let cities = logs.compactMap { placesByID[$0.placeID] }.map { simplifiedCity(from: $0.address) }
        let counts = Dictionary(grouping: cities, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key.uppercased() ?? trip.name.uppercased()
    }

    private func simplifiedCity(from address: String) -> String {
        let parts = address.components(separatedBy: ", ")
        // Try to grab just the city name — skip zip codes and state abbreviations
        for part in parts.reversed() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            // Skip parts that look like zip codes or country codes
            if trimmed.count <= 3 { continue }
            if trimmed.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) { continue }
            // Skip parts that look like "CA", "NY", "NSW" (1-3 uppercase letters)
            if trimmed.count <= 3 && trimmed == trimmed.uppercased() { continue }
            return trimmed
        }
        return address
    }

    /// Date range string like "Jun 12 – 18, 2025"
    private func dateRange(for trip: Trip) -> String? {
        guard let start = trip.startDate else { return nil }
        if let end = trip.endDate, !Calendar.current.isDate(start, inSameDayAs: end) {
            if Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end) {
                return "\(start.formatted(.dateTime.month(.abbreviated))) \(start.formatted(.dateTime.day())) – \(end.formatted(.dateTime.day())), \(start.formatted(.dateTime.year()))"
            }
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day())), \(start.formatted(.dateTime.year()))"
        }
        return start.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        ZStack {
            // Sky background
            boardingPassBackground
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        boardingPass(trip: trip, index: index)
                    }

                    // Orphaned logs — compact boarding pass stubs
                    if !orphanedLogs.isEmpty {
                        orphanedLogsHeader

                        if showOrphanedLogs {
                            ForEach(orphanedLogs, id: \.id) { log in
                                orphanedLogStub(log: log)
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, SonderSpacing.md)
                .padding(.top, SonderSpacing.md)
                .padding(.bottom, showOrphanedLogs ? 100 : 400)
            }
        }
    }

    // MARK: - Background

    private var boardingPassBackground: some View {
        ZStack {
            // Soft sky gradient
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.90, blue: 0.96),
                    Color(red: 0.92, green: 0.94, blue: 0.98),
                    Color(red: 0.96, green: 0.95, blue: 0.93)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Clouds and plane trails
            Canvas { context, size in
                var rng = BoardingPassRNG(seed: 42)

                // Soft cloud puffs
                let cloudColor = Color.white.opacity(0.5)
                for _ in 0..<18 {
                    let cx = CGFloat.random(in: -40...size.width + 40, using: &rng)
                    let cy = CGFloat.random(in: 0...size.height, using: &rng)
                    let puffs = Int.random(in: 3...6, using: &rng)

                    for _ in 0..<puffs {
                        let ox = CGFloat.random(in: -30...30, using: &rng)
                        let oy = CGFloat.random(in: -10...10, using: &rng)
                        let r = CGFloat.random(in: 15...40, using: &rng)
                        let rect = CGRect(x: cx + ox - r, y: cy + oy - r, width: r * 2, height: r * 1.2)
                        context.fill(Path(ellipseIn: rect), with: .color(cloudColor))
                    }
                }

                // Contrails — long curved dashed lines
                let trailColor = Color.white.opacity(0.35)
                let trailStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [12, 8])

                let trails: [(start: CGPoint, end: CGPoint)] = [
                    (CGPoint(x: -20, y: size.height * 0.15), CGPoint(x: size.width + 40, y: size.height * 0.08)),
                    (CGPoint(x: size.width + 20, y: size.height * 0.55), CGPoint(x: -30, y: size.height * 0.48)),
                    (CGPoint(x: -10, y: size.height * 0.82), CGPoint(x: size.width * 0.7, y: size.height * 0.75)),
                ]
                for trail in trails {
                    var path = Path()
                    path.move(to: trail.start)
                    let midX = (trail.start.x + trail.end.x) / 2
                    let midY = (trail.start.y + trail.end.y) / 2 - 20
                    path.addQuadCurve(to: trail.end, control: CGPoint(x: midX, y: midY))
                    context.stroke(path, with: .color(trailColor), style: trailStyle)
                }

                // Tiny plane silhouettes at trail ends
                let planeColor = Color(red: 0.6, green: 0.65, blue: 0.7).opacity(0.3)
                for trail in trails.prefix(2) {
                    let px = trail.end.x.clamped(to: 20...size.width - 20)
                    let py = trail.end.y
                    // Simple plane shape: triangle + tail
                    var plane = Path()
                    plane.move(to: CGPoint(x: px, y: py))
                    plane.addLine(to: CGPoint(x: px - 8, y: py + 4))
                    plane.addLine(to: CGPoint(x: px - 5, y: py))
                    plane.addLine(to: CGPoint(x: px - 8, y: py - 4))
                    plane.closeSubpath()
                    context.fill(plane, with: .color(planeColor))
                }
            }
        }
    }

    // MARK: - Boarding Pass Card

    private func boardingPass(trip: Trip, index: Int) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            VStack(spacing: 0) {
                // Cover photo strip at top
                coverPhotoStrip(trip: trip)

                // Route section: destination + airplane
                routeSection(trip: trip)

                // Perforation tear line
                perforationLine

                // Bottom stub: trip details
                detailsStub(trip: trip, index: index)
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cover Photo Strip

    private func coverPhotoStrip(trip: Trip) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 150)) {
                    coverPlaceholder(trip: trip)
                }
                .aspectRatio(contentMode: .fill)
            } else {
                coverPlaceholder(trip: trip)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            // Gradient fade into the white card below
            LinearGradient(
                colors: [.clear, .white.opacity(0.6), .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }

    private func coverPlaceholder(trip: Trip) -> some View {
        LinearGradient(
            colors: [
                Color(red: 0.82, green: 0.85, blue: 0.90),
                Color(red: 0.75, green: 0.80, blue: 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "airplane.departure")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Route Section

    private func routeSection(trip: Trip) -> some View {
        HStack(alignment: .center) {
            // Trip name as the "from"
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)
            }

            Spacer()

            // Flight path
            HStack(spacing: 6) {
                Circle()
                    .fill(SonderColors.terracotta)
                    .frame(width: 6, height: 6)

                // Dashed line
                Rectangle()
                    .fill(.clear)
                    .frame(width: 40, height: 1)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(SonderColors.inkLight.opacity(0.4))
                    )

                Image(systemName: "airplane")
                    .font(.system(size: 14))
                    .foregroundStyle(SonderColors.terracotta)

                Rectangle()
                    .fill(.clear)
                    .frame(width: 20, height: 1)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(SonderColors.inkLight.opacity(0.4))
                    )

                Circle()
                    .stroke(SonderColors.terracotta, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
            }

            Spacer()

            // Destination city
            VStack(alignment: .trailing, spacing: 2) {
                Text(destinationCity(for: trip))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    // MARK: - Perforation

    private var perforationLine: some View {
        HStack(spacing: 0) {
            // Left notch
            Circle()
                .fill(Color(red: 0.85, green: 0.90, blue: 0.96))
                .frame(width: 16, height: 16)
                .offset(x: -8)

            // Dashed perforation
            Rectangle()
                .fill(.clear)
                .frame(height: 1)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(SonderColors.inkLight.opacity(0.25))
                )
                .padding(.horizontal, 4)

            // Right notch
            Circle()
                .fill(Color(red: 0.85, green: 0.90, blue: 0.96))
                .frame(width: 16, height: 16)
                .offset(x: 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Details Stub

    private func detailsStub(trip: Trip, index: Int) -> some View {
        HStack(alignment: .top) {
            // Left side: date + stops
            VStack(alignment: .leading, spacing: 8) {
                if let date = dateRange(for: trip) {
                    labelValue(label: "DATE", value: date)
                }

                HStack(spacing: 16) {
                    labelValue(label: "STOPS", value: "\(logsForTrip(trip).count)")

                    let mustSees = logsForTrip(trip).filter { $0.rating == .mustSee }.count
                    if mustSees > 0 {
                        labelValue(label: "MUST-SEE", value: "\(mustSees)", accent: true)
                    }
                }
            }

            Spacer()

            // Right side: trip number in a rounded badge
            Text("\(String(format: "%03d", trips.count - index))")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(SonderColors.terracotta.opacity(0.2))
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Orphaned Logs

    private var orphanedLogsHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                showOrphanedLogs.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 13))
                Text("Not in a trip")
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showOrphanedLogs ? 90 : 0))
                Text("(\(orphanedLogs.count))")
                    .font(.system(size: 13))
                    .opacity(0.5)
            }
            .foregroundStyle(Color(red: 0.45, green: 0.50, blue: 0.58))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func orphanedLogStub(log: Log) -> some View {
        let place = placesByID[log.placeID]
        return Button {
            selectedLog = log
        } label: {
            VStack(spacing: 0) {
                // Single-row compact content
                HStack(alignment: .center, spacing: 12) {
                    // Place name as destination
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DESTINATION")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(SonderColors.inkLight)
                        Text((place?.name ?? "Unknown Place").uppercased())
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(SonderColors.inkDark)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer()

                    // Flight path mini
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SonderColors.terracotta)
                            .frame(width: 4, height: 4)
                        Rectangle()
                            .fill(.clear)
                            .frame(width: 20, height: 1)
                            .overlay(
                                Rectangle()
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .foregroundStyle(SonderColors.inkLight.opacity(0.3))
                            )
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                            .foregroundStyle(SonderColors.terracotta)
                    }

                    Spacer()

                    // Rating + date
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(log.rating.emoji)
                            .font(.system(size: 16))
                        Text(log.visitedAt.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(SonderColors.inkLight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Perforation line
                perforationLine
                    .padding(.bottom, 4)
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func labelValue(label: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(SonderColors.inkLight)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(accent ? SonderColors.terracotta : SonderColors.inkDark)
        }
    }
}

// MARK: - Helpers

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct BoardingPassRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
