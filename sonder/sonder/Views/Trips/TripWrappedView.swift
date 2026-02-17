//
//  TripWrappedView.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Spotify Wrapped-style trip recap with sequential full-screen cards and bold data reveals.
struct TripWrappedView: View {
    @Environment(\.dismiss) private var dismiss

    let tripName: String
    let logs: [Log]
    let places: [Place]
    let coverPhotoURL: String?

    @State private var currentCard = 0
    @State private var showNumber = false
    @State private var animatedCount: Int = 0
    @State private var progressFill: CGFloat = 0

    private var placesByID: [String: Place] {
        Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
    }

    private var sortedLogs: [Log] {
        logs.sorted { $0.visitedAt < $1.visitedAt }
    }

    private var mustSees: [Log] {
        sortedLogs.filter { $0.rating == .mustSee }
    }

    private var topPlace: (log: Log, place: Place)? {
        guard let log = mustSees.first, let place = placesByID[log.placeID] else { return nil }
        return (log, place)
    }

    private var dayCount: Int {
        Set(sortedLogs.map { Calendar.current.startOfDay(for: $0.visitedAt) }).count
    }

    private var topCategory: String? {
        let allTags = sortedLogs.flatMap { $0.tags }
        let counted = Dictionary(grouping: allTags, by: { $0 }).mapValues { $0.count }
        return counted.max(by: { $0.value < $1.value })?.key
    }

    /// The longest note with its place — for the pull quote card
    private var bestQuote: (note: String, placeName: String)? {
        var best: (note: String, placeName: String)?
        for log in mustSees {
            if let note = log.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                if let b = best {
                    if note.count > b.note.count {
                        best = (note, placesByID[log.placeID]?.name ?? "")
                    }
                } else {
                    best = (note, placesByID[log.placeID]?.name ?? "")
                }
            }
        }
        return best
    }

    private var totalCards: Int { 7 }

    var body: some View {
        ZStack {
            // Background — shifts color per card
            cardBackground
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: currentCard)

            // Card content
            TabView(selection: $currentCard) {
                card0_intro.tag(0)
                card1_placeCount.tag(1)
                card2_topRated.tag(2)
                card3_mustSeeRatio.tag(3)
                card4_topCategory.tag(4)
                card5_pullQuote.tag(5)
                card6_summary.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    // Progress dots
                    HStack(spacing: 4) {
                        ForEach(0..<totalCards, id: \.self) { i in
                            Capsule()
                                .fill(i <= currentCard ? .white : .white.opacity(0.3))
                                .frame(height: 3)
                        }
                    }
                    .frame(maxWidth: 200)

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
            }
        }
        .statusBarHidden()
        .onChange(of: currentCard) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            triggerCardAnimations()
        }
        .onAppear { triggerCardAnimations() }
    }

    // MARK: - Background

    private var cardBackground: some View {
        let colors: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),             // intro
            (Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.25, green: 0.20, blue: 0.22)),  // place count
            (SonderColors.terracotta.opacity(0.9), Color(red: 0.6, green: 0.3, blue: 0.25)),          // top rated
            (Color(red: 0.20, green: 0.22, blue: 0.25), Color(red: 0.15, green: 0.18, blue: 0.22)),  // ratio
            (SonderColors.sage, Color(red: 0.35, green: 0.45, blue: 0.35)),                            // category
            (SonderColors.cream, SonderColors.warmGray),                                                // quote
            (Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.20, green: 0.18, blue: 0.16)),  // summary
        ]
        let pair = colors[min(currentCard, colors.count - 1)]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Cards

    private var card0_intro: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(tripName)
                .font(.system(size: 42, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 40, height: 1)

            Text("LET'S LOOK BACK")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(4.0)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(40)
    }

    private var card1_placeCount: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("You explored")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundColor(.white.opacity(0.6))

            Text("\(showNumber ? sortedLogs.count : 0)")
                .font(.system(size: 96, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: showNumber)

            Text("places in \(dayCount) \(dayCount == 1 ? "day" : "days")")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(40)
    }

    private var card2_topRated: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("YOUR TOP SPOT")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(4.0)
                .foregroundColor(.white.opacity(0.5))

            if let top = topPlace {
                // Photo
                if let urlString = top.log.photoURL, let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 300)) {
                        Rectangle().fill(.white.opacity(0.1))
                    }
                    .frame(width: 260, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                }

                Text(top.place.name)
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("\(top.log.rating.emoji) Must-See")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("No must-sees yet!")
                    .font(.system(size: 20, weight: .light, design: .serif))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(40)
    }

    private var card3_mustSeeRatio: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("\(mustSees.count) of \(sortedLogs.count)")
                .font(.system(size: 64, weight: .bold, design: .serif))
                .foregroundColor(.white)

            Text("places were Must-See")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundColor(.white.opacity(0.6))

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 8)

                    Capsule()
                        .fill(SonderColors.terracotta)
                        .frame(width: geo.size.width * progressFill, height: 8)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7), value: progressFill)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 40)

            if sortedLogs.count > 0 {
                Text("You have great taste.")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundColor(.white.opacity(0.5))
                    .italic()
            }

            Spacer()
        }
        .padding(40)
    }

    private var card4_topCategory: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("YOUR VIBE")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(4.0)
                .foregroundColor(.white.opacity(0.5))

            if let category = topCategory {
                Text(category)
                    .font(.system(size: 48, weight: .bold, design: .serif))
                    .foregroundColor(.white)
            }

            Text("was your most-tagged category")
                .font(.system(size: 16, weight: .light, design: .serif))
                .foregroundColor(.white.opacity(0.6))

            Spacer()
        }
        .padding(40)
    }

    private var card5_pullQuote: some View {
        VStack(spacing: 24) {
            Spacer()

            if let quote = bestQuote {
                Text("\"\(quote.note)\"")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)

                Text("— \(quote.placeName)")
                    .font(.system(size: 14))
                    .foregroundColor(SonderColors.inkMuted)
            } else {
                Text("Your words, your memories.")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .italic()
            }

            Spacer()
        }
        .padding(48)
    }

    private var card6_summary: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(tripName)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(.white)

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 40, height: 1)

            // Stats grid
            HStack(spacing: 32) {
                wrappedStat(value: "\(sortedLogs.count)", label: "places")
                wrappedStat(value: "\(dayCount)", label: "days")
                wrappedStat(value: "\(mustSees.count)", label: "must-sees")
            }

            // Rating breakdown
            HStack(spacing: 16) {
                if mustSees.count > 0 {
                    Text("\(Rating.mustSee.emoji) \(mustSees.count)")
                        .foregroundColor(.white.opacity(0.7))
                }
                let solidCount = sortedLogs.filter { $0.rating == .solid }.count
                if solidCount > 0 {
                    Text("\(Rating.solid.emoji) \(solidCount)")
                        .foregroundColor(.white.opacity(0.7))
                }
                let skipCount = sortedLogs.filter { $0.rating == .skip }.count
                if skipCount > 0 {
                    Text("\(Rating.skip.emoji) \(skipCount)")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .font(.system(size: 15, weight: .medium))

            Spacer()

            Text("sonder")
                .font(.system(size: 13, weight: .light, design: .serif))
                .tracking(4.0)
                .foregroundColor(.white.opacity(0.25))
                .padding(.bottom, 40)
        }
        .padding(40)
    }

    private func wrappedStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundColor(.white)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(2.0)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Animations

    private func triggerCardAnimations() {
        showNumber = false
        progressFill = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                showNumber = true
            }
            if sortedLogs.count > 0 {
                progressFill = CGFloat(mustSees.count) / CGFloat(sortedLogs.count)
            }
        }
    }
}
