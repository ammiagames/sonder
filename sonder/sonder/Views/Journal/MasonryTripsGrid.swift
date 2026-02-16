//
//  MasonryTripsGrid.swift
//  sonder
//
//  Created by Michael Song on 2/13/26.
//

import SwiftUI

/// Pinterest-style masonry grid of trip cards with a zigzag dotted trail line
/// connecting trips in reverse chronological order (most recent at top).
struct MasonryTripsGrid: View {
    @Environment(AuthenticationService.self) private var authService

    let trips: [Trip]       // already sorted most-recent-first
    let allLogs: [Log]
    let places: [Place]
    let filteredLogs: [Log]
    @Binding var selectedTrip: Trip?
    @Binding var selectedLog: Log?
    let deleteLog: (Log) -> Void
    var searchText: String = ""

    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var unassignedExpanded = false

    // MARK: - Precomputed Data

    /// O(L) log count dictionary — built once per render instead of O(T*L)
    private var logCountsByTripID: [String: Int] {
        var counts: [String: Int] = [:]
        for log in allLogs {
            if let tripID = log.tripID {
                counts[tripID, default: 0] += 1
            }
        }
        return counts
    }

    /// O(P) place dictionary for O(1) lookups in unassigned logs section
    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    // MARK: - Column Assignment

    /// Computed once; leftColumn and rightColumn are derived from it without re-calling
    private var columnAssignments: [MasonryColumnAssignment] {
        assignMasonryColumns(trips: trips, estimateHeight: estimateCardHeight)
    }

    private var leftColumn: [(trip: Trip, index: Int)] {
        columnAssignments.filter { $0.column == 0 }.map { ($0.trip, $0.index) }
    }

    private var rightColumn: [(trip: Trip, index: Int)] {
        columnAssignments.filter { $0.column == 1 }.map { ($0.trip, $0.index) }
    }

    /// Logs not belonging to any trip
    private var unassignedLogs: [Log] {
        filteredLogs.filter { $0.tripID == nil }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.md) {
                if trips.isEmpty && unassignedLogs.isEmpty {
                    tripsEmptyState
                } else if !trips.isEmpty {
                    masonryGrid
                }

                if !unassignedLogs.isEmpty {
                    notInTripSection
                }

                Spacer().frame(height: 80)
            }
            .padding(.top, SonderSpacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                unassignedExpanded = true
            }
        }
    }

    // MARK: - Masonry Grid

    private var masonryGrid: some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            VStack(spacing: SonderSpacing.sm) {
                ForEach(leftColumn, id: \.trip.id) { item in
                    tripCardView(trip: item.trip, index: item.index)
                }
            }

            VStack(spacing: SonderSpacing.sm) {
                ForEach(rightColumn, id: \.trip.id) { item in
                    tripCardView(trip: item.trip, index: item.index)
                }
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .coordinateSpace(name: "trailGrid")
        .onPreferenceChange(CardFramePreference.self) { frames in
            if frames != cardFrames { cardFrames = frames }
        }
        .background {
            ZigzagTrailView(cardFrames: cardFrames, totalCards: trips.count)
        }
    }

    private func tripCardView(trip: Trip, index: Int) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            TripCard(
                trip: trip,
                logCount: logCountsByTripID[trip.id] ?? 0,
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
                    if let place = placesByID[log.placeID] {
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
        var h: CGFloat = 120  // compact cover photo
        h += 24              // info section padding
        h += 22              // name + owner badge
        if let desc = trip.tripDescription, !desc.isEmpty { h += 30 }
        if trip.startDate != nil { h += 18 }
        h += 18              // stats row
        return h
    }
}

// MARK: - Zigzag Trail

/// Draws a smooth dotted zigzag line through trip card centers in chronological order.
/// Rendered as a background so the line peeks out between staggered cards.
struct ZigzagTrailView: View {
    let cardFrames: [Int: CGRect]
    let totalCards: Int

    var body: some View {
        Canvas { context, size in
            let indices = (0..<totalCards).filter { cardFrames[$0] != nil }.sorted()
            guard indices.count >= 2 else { return }

            let trailColor = Color(red: 0.76, green: 0.45, blue: 0.32).opacity(0.30)
            let dotColor = Color(red: 0.76, green: 0.45, blue: 0.32).opacity(0.50)
            let dashStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4])

            // Collect card center points
            var points: [CGPoint] = []
            for index in indices {
                guard let rect = cardFrames[index] else { continue }
                points.append(CGPoint(x: rect.midX, y: rect.midY))
            }
            guard points.count >= 2 else { return }

            // Smooth bezier curve through card centers
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
            context.stroke(path, with: .color(trailColor), style: dashStyle)

            // Dots at each card center
            for (i, point) in points.enumerated() {
                let r: CGFloat = i == 0 ? 5 : 4
                let dotRect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            }
        }
        .allowsHitTesting(false)
    }
}
