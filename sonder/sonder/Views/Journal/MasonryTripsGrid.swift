//
//  MasonryTripsGrid.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI

/// Pinterest-style masonry grid of trip cards with a configurable dotted trail line
/// connecting trips in reverse chronological order (most recent at top).
struct MasonryTripsGrid: View {
    @Environment(AuthenticationService.self) private var authService

    let trips: [Trip]       // already sorted most-recent-first
    let allLogs: [Log]
    let places: [Place]
    let filteredLogs: [Log]
    let trailStyle: TrailStyle
    @Binding var selectedTrip: Trip?
    @Binding var selectedLog: Log?
    let deleteLog: (Log) -> Void

    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var unassignedExpanded = false

    // MARK: - Column Assignment

    /// Assign each trip to left (0) or right (1) column, greedily picking the shorter column.
    private var columnAssignments: [(trip: Trip, index: Int, column: Int)] {
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0
        var result: [(Trip, Int, Int)] = []
        let spacing: CGFloat = 10 // matches SonderSpacing.sm

        for (index, trip) in trips.enumerated() {
            let h = estimateCardHeight(for: trip)
            if leftHeight <= rightHeight {
                result.append((trip, index, 0))
                leftHeight += h + spacing
            } else {
                result.append((trip, index, 1))
                rightHeight += h + spacing
            }
        }
        return result
    }

    private var leftColumn: [(trip: Trip, index: Int)] {
        columnAssignments.filter { $0.column == 0 }.map { ($0.trip, $0.index) }
    }

    private var rightColumn: [(trip: Trip, index: Int)] {
        columnAssignments.filter { $0.column == 1 }.map { ($0.trip, $0.index) }
    }

    /// Map from chronological index → column (used by the trail overlay)
    private var columnMap: [Int: Int] {
        Dictionary(uniqueKeysWithValues: columnAssignments.map { ($0.index, $0.column) })
    }

    /// Logs not belonging to any trip
    private var unassignedLogs: [Log] {
        filteredLogs.filter { $0.tripID == nil }
    }

    private func logCount(for trip: Trip) -> Int {
        allLogs.filter { $0.tripID == trip.id }.count
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.md) {
                if trips.isEmpty {
                    tripsEmptyState
                } else {
                    // Masonry grid with trail
                    masonryGrid
                }

                // "Not in a trip" section
                if !unassignedLogs.isEmpty {
                    notInTripSection
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, SonderSpacing.sm)
        }
    }

    // MARK: - Masonry Grid

    private var masonryGrid: some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            // Left column
            VStack(spacing: SonderSpacing.sm) {
                ForEach(leftColumn, id: \.trip.id) { item in
                    tripCardView(trip: item.trip, index: item.index)
                }
            }

            // Right column
            VStack(spacing: SonderSpacing.sm) {
                ForEach(rightColumn, id: \.trip.id) { item in
                    tripCardView(trip: item.trip, index: item.index)
                }
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .coordinateSpace(name: "trailGrid")
        .onPreferenceChange(CardFramePreference.self) { frames in
            cardFrames = frames
        }
        .background {
            TrailOverlayView(
                cardFrames: cardFrames,
                columnMap: columnMap,
                style: trailStyle,
                totalCards: trips.count
            )
        }
    }

    private func tripCardView(trip: Trip, index: Int) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            TripCard(
                trip: trip,
                logCount: logCount(for: trip),
                isOwner: trip.createdBy == authService.currentUser?.id,
                compact: true
            )
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CardFramePreference.self,
                    value: [index: geo.frame(in: .named("trailGrid"))]
                )
            }
        )
    }

    // MARK: - Not In A Trip

    private var notInTripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    unassignedExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Not in a trip")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text("(\(unassignedLogs.count))")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkLight)

                    Spacer()

                    Image(systemName: unassignedExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SonderColors.inkLight)
                }
                .padding(.horizontal, SonderSpacing.md)
            }
            .buttonStyle(.plain)

            if unassignedExpanded {
                ForEach(unassignedLogs, id: \.id) { log in
                    if let place = places.first(where: { $0.id == log.placeID }) {
                        Button {
                            selectedLog = log
                        } label: {
                            JournalLogRow(log: log, place: place, tripName: nil)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, SonderSpacing.md)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var tripsEmptyState: some View {
        VStack(spacing: SonderSpacing.md) {
            Image(systemName: "suitcase")
                .font(.system(size: 40))
                .foregroundColor(SonderColors.inkLight)
            Text("No trips yet")
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkMuted)
            Text("Create a trip from the toolbar to organize your logs")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SonderSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SonderSpacing.xxl)
    }

    // MARK: - Height Estimation (for column balancing)

    private func estimateCardHeight(for trip: Trip) -> CGFloat {
        var h: CGFloat = 80  // compact cover photo
        h += 24              // info section padding
        h += 22              // name + owner badge
        if let desc = trip.tripDescription, !desc.isEmpty { h += 30 }  // description (2 lines)
        if trip.startDate != nil { h += 18 }                            // date range
        h += 18              // stats row
        return h
    }
}

// MARK: - Trail Overlay

/// Draws the dotted trail line connecting trip cards in chronological order.
/// Renders as a background behind the masonry grid so lines peek out between cards.
struct TrailOverlayView: View {
    let cardFrames: [Int: CGRect]
    let columnMap: [Int: Int]
    let style: TrailStyle
    let totalCards: Int

    var body: some View {
        Canvas { context, size in
            let indices = (0..<totalCards).filter { cardFrames[$0] != nil }.sorted()
            guard indices.count >= 2 else { return }

            let trailColor = Color(red: 0.76, green: 0.45, blue: 0.32).opacity(0.30) // terracotta-ish
            let dotColor = Color(red: 0.76, green: 0.45, blue: 0.32).opacity(0.50)
            let dashStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4])

            switch style {
            case .zigzag:
                drawZigzag(context: &context, indices: indices, color: trailColor, dotColor: dotColor, dashStyle: dashStyle)
            case .spine:
                drawSpine(context: &context, indices: indices, size: size, color: trailColor, dotColor: dotColor, dashStyle: dashStyle)
            case .columns:
                drawColumnLines(context: &context, indices: indices, color: trailColor, dotColor: dotColor, dashStyle: dashStyle)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Option A: Zigzag Path

    private func drawZigzag(context: inout GraphicsContext, indices: [Int], color: Color, dotColor: Color, dashStyle: StrokeStyle) {
        var points: [CGPoint] = []
        for index in indices {
            guard let rect = cardFrames[index] else { continue }
            points.append(CGPoint(x: rect.midX, y: rect.midY))
        }
        guard points.count >= 2 else { return }

        // Smooth curve through card centers
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
        context.stroke(path, with: .color(color), style: dashStyle)

        // Dots at each card center
        for (i, point) in points.enumerated() {
            let r: CGFloat = i == 0 ? 5 : 4
            let dotRect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
        }
    }

    // MARK: - Option B: Center Spine with Branches

    private func drawSpine(context: inout GraphicsContext, indices: [Int], size: CGSize, color: Color, dotColor: Color, dashStyle: StrokeStyle) {
        let centerX = size.width / 2

        // Collect card info
        var entries: [(y: CGFloat, cardEdgeX: CGFloat, index: Int)] = []
        for index in indices {
            guard let rect = cardFrames[index], let col = columnMap[index] else { continue }
            let edgeX: CGFloat = col == 0 ? rect.maxX + 4 : rect.minX - 4
            entries.append((y: rect.midY, cardEdgeX: edgeX, index: index))
        }
        guard entries.count >= 2 else { return }

        // Vertical spine
        let topY = entries.first!.y
        let bottomY = entries.last!.y
        var spinePath = Path()
        spinePath.move(to: CGPoint(x: centerX, y: topY))
        spinePath.addLine(to: CGPoint(x: centerX, y: bottomY))
        context.stroke(spinePath, with: .color(color), style: dashStyle)

        // Branches + numbered circles
        for (i, entry) in entries.enumerated() {
            // Horizontal branch
            var branchPath = Path()
            branchPath.move(to: CGPoint(x: centerX, y: entry.y))
            branchPath.addLine(to: CGPoint(x: entry.cardEdgeX, y: entry.y))
            context.stroke(branchPath, with: .color(color), style: dashStyle)

            // Circle on spine
            let spinePoint = CGPoint(x: centerX, y: entry.y)
            let circleR: CGFloat = 10
            let circleRect = CGRect(x: spinePoint.x - circleR, y: spinePoint.y - circleR, width: circleR * 2, height: circleR * 2)
            context.fill(Path(ellipseIn: circleRect), with: .color(dotColor))

            // Number label
            let text = context.resolve(
                Text("\(i + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            )
            context.draw(text, at: spinePoint, anchor: .center)
        }
    }

    // MARK: - Option C: Column-Local Lines

    private func drawColumnLines(context: inout GraphicsContext, indices: [Int], color: Color, dotColor: Color, dashStyle: StrokeStyle) {
        // Group by column
        var leftEntries: [(y: CGFloat, x: CGFloat, chronoIndex: Int)] = []
        var rightEntries: [(y: CGFloat, x: CGFloat, chronoIndex: Int)] = []

        for index in indices {
            guard let rect = cardFrames[index], let col = columnMap[index] else { continue }
            let entry = (y: rect.midY, x: rect.midX, chronoIndex: index)
            if col == 0 {
                leftEntries.append(entry)
            } else {
                rightEntries.append(entry)
            }
        }

        // Draw each column's line + dots
        for entries in [leftEntries, rightEntries] {
            guard entries.count >= 2 else {
                // Single card — just draw a dot
                if let only = entries.first {
                    drawNumberedDot(context: &context, at: CGPoint(x: only.x, y: only.y), number: only.chronoIndex + 1, dotColor: dotColor)
                }
                continue
            }

            // Vertical line through card centers
            var linePath = Path()
            linePath.move(to: CGPoint(x: entries.first!.x, y: entries.first!.y))
            for entry in entries.dropFirst() {
                linePath.addLine(to: CGPoint(x: entry.x, y: entry.y))
            }
            context.stroke(linePath, with: .color(color), style: dashStyle)

            // Numbered dots
            for entry in entries {
                drawNumberedDot(context: &context, at: CGPoint(x: entry.x, y: entry.y), number: entry.chronoIndex + 1, dotColor: dotColor)
            }
        }
    }

    // MARK: - Helpers

    private func drawNumberedDot(context: inout GraphicsContext, at point: CGPoint, number: Int, dotColor: Color) {
        let r: CGFloat = 10
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: rect), with: .color(dotColor))

        let text = context.resolve(
            Text("\(number)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
        )
        context.draw(text, at: point, anchor: .center)
    }
}
