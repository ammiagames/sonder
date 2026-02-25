//
//  TripExportItinerary.swift
//  sonder
//
//  Practical itinerary card — numbered stop list with addresses,
//  notes, and rating summary. Designed to be useful, not just pretty.
//

import SwiftUI

struct TripExportItinerary: View {
    let data: TripExportData
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }

    private var maxItems: Int {
        switch canvasSize.height {
        case 1920: return 12
        case 1350: return 8
        default: return 6
        }
    }

    var body: some View {
        ZStack {
            theme.background

            VStack(spacing: 0) {
                Spacer().frame(height: 80 * s)

                header
                spacer(32)
                accentDivider
                spacer(32)

                if data.stops.isEmpty {
                    emptyState
                } else {
                    stopList
                }

                Spacer(minLength: 20 * s)

                ratingSummary
                spacer(24)
                footer
                spacer(48)
            }
            .padding(.horizontal, 72 * s)

            FilmGrainOverlay(opacity: 0.015, seed: data.tripName.hashValue &+ 7)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Text(data.tripName)
                .font(.system(size: 64 * s, weight: .bold, design: .serif))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            HStack(spacing: 16 * s) {
                if let dateText = data.dateRangeText {
                    Text(dateText)
                        .font(.system(size: 26 * s))
                        .foregroundStyle(theme.textSecondary)
                }

                Text("\(data.placeCount) stops")
                    .font(.system(size: 26 * s, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Accent Divider

    private var accentDivider: some View {
        Rectangle()
            .fill(theme.accent)
            .frame(height: 3 * s)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16 * s) {
            Spacer()
            Text("No stops yet")
                .font(.system(size: 32 * s, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            Text("Add places to your trip to build an itinerary")
                .font(.system(size: 24 * s))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Stop List

    private var stopList: some View {
        let displayStops = Array(data.stops.prefix(maxItems))
        let remaining = data.stops.count - displayStops.count

        return VStack(alignment: .leading, spacing: 24 * s) {
            ForEach(Array(displayStops.enumerated()), id: \.offset) { index, stop in
                stopRow(number: index + 1, stop: stop)
            }

            if remaining > 0 {
                Text("+\(remaining) more stops")
                    .font(.system(size: 24 * s, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, 52 * s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stopRow(number: Int, stop: ExportStop) -> some View {
        HStack(alignment: .top, spacing: 14 * s) {
            // Number + rating emoji
            Text("\(number).")
                .font(.system(size: 28 * s, weight: .bold, design: .rounded))
                .foregroundStyle(theme.accent)
                .frame(width: 38 * s, alignment: .trailing)

            VStack(alignment: .leading, spacing: 5 * s) {
                // Place name + rating
                HStack(spacing: 8 * s) {
                    Text(stop.rating.emoji)
                        .font(.system(size: 26 * s))
                    Text(stop.placeName)
                        .font(.system(size: 28 * s, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }

                // Address (truncated)
                if !stop.address.isEmpty {
                    Text(stop.address)
                        .font(.system(size: 22 * s))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                // Note excerpt (italic)
                if let note = stop.note, !note.isEmpty {
                    let excerpt = String(note.prefix(50))
                    Text("\u{201C}\(excerpt)\u{201D}")
                        .font(.system(size: 22 * s, design: .serif))
                        .italic()
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Rating Summary

    private var ratingSummary: some View {
        HStack(spacing: 24 * s) {
            if data.ratingCounts.mustSee > 0 {
                ratingPill(emoji: Rating.mustSee.emoji, count: data.ratingCounts.mustSee)
            }
            if data.ratingCounts.great > 0 {
                ratingPill(emoji: Rating.great.emoji, count: data.ratingCounts.great)
            }
            if data.ratingCounts.okay > 0 {
                ratingPill(emoji: Rating.okay.emoji, count: data.ratingCounts.okay)
            }
            if data.ratingCounts.skip > 0 {
                ratingPill(emoji: Rating.skip.emoji, count: data.ratingCounts.skip)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ratingPill(emoji: String, count: Int) -> some View {
        HStack(spacing: 6 * s) {
            Text(emoji)
                .font(.system(size: 26 * s))
            Text("\(count)")
                .font(.system(size: 24 * s, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 16 * s)
        .padding(.vertical, 8 * s)
        .background(theme.backgroundSecondary)
        .clipShape(Capsule())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10 * s) {
            if let caption = data.customCaption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 24 * s, design: .serif))
                    .italic()
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Text("\(Text("sonder").font(.system(size: 22 * s, weight: .semibold, design: .rounded)))  \u{00B7}  your travel story")
                .font(.system(size: 22 * s))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func spacer(_ pts: CGFloat) -> some View {
        Spacer().frame(height: pts * s)
    }
}
