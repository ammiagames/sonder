//
//  ProfileShared.swift
//  sonder
//
//  Shared helpers used by both ProfileView and OtherUserProfileView.
//

import SwiftUI

// MARK: - Trip Display Helpers

enum ProfileShared {

    static let tripDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static func tripDateText(_ trip: Trip) -> String? {
        let formatter = tripDateFormatter
        if let start = trip.startDate, let end = trip.endDate {
            let startText = formatter.string(from: start)
            let endText = formatter.string(from: end)
            return startText == endText ? startText : "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        } else if let start = trip.startDate {
            return formatter.string(from: start)
        } else if let end = trip.endDate {
            return formatter.string(from: end)
        }
        return nil
    }

    static func tripGradient(_ trip: Trip) -> (Color, Color) {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        return gradients[abs(trip.id.hashValue) % gradients.count]
    }

    @ViewBuilder
    static func tripPlaceholderGradient(_ trip: Trip) -> some View {
        let grad = tripGradient(trip)
        LinearGradient(
            colors: [grad.0.opacity(0.7), grad.1.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "airplane")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    static func tripCoverPhoto(_ trip: Trip, size: CGSize, coverURL: URL?) -> some View {
        if let url = coverURL {
            DownsampledAsyncImage(url: url, targetSize: size) {
                tripPlaceholderGradient(trip)
            }
        } else {
            tripPlaceholderGradient(trip)
        }
    }

    // MARK: - Tag Chip

    static func tagChip(tag: String, count: Int, isTop: Bool, maxCount: Int) -> some View {
        let weight = CGFloat(count) / CGFloat(maxCount)
        let fontSize: CGFloat = isTop ? 16 : (12 + 4 * weight)
        let hPad: CGFloat = isTop ? SonderSpacing.md : SonderSpacing.sm
        let vPad: CGFloat = isTop ? SonderSpacing.xs : (SonderSpacing.xxs + 2)
        let bgColor: Color = isTop ? SonderColors.terracotta : SonderColors.terracotta.opacity(0.08 + 0.12 * Double(weight))
        let textColor: Color = isTop ? .white : SonderColors.terracotta
        let countColor: Color = isTop ? .white.opacity(0.8) : SonderColors.terracotta.opacity(0.6)

        return HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: fontSize, weight: isTop ? .bold : .medium))
                .foregroundStyle(textColor)
            Text("\(count)")
                .font(.system(size: fontSize - 2, weight: .regular))
                .foregroundStyle(countColor)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(bgColor)
        .clipShape(Capsule())
    }

    // MARK: - City Photo Fallback

    static func cityPhotoFallback(index: Int) -> some View {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta, SonderColors.ochre),
            (SonderColors.warmBlue, SonderColors.sage),
            (SonderColors.dustyRose, SonderColors.terracotta),
            (SonderColors.sage, SonderColors.warmBlue),
            (SonderColors.ochre, SonderColors.dustyRose),
        ]
        let grad = gradients[index % gradients.count]
        return LinearGradient(
            colors: [grad.0, grad.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Medium Date Formatter (used by Trip cards/details)

    static let mediumDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    /// Medium-format date range text for a trip (e.g. "Feb 20, 2026 – Mar 5, 2026")
    static func tripMediumDateRange(_ trip: Trip) -> String? {
        if let start = trip.startDate, let end = trip.endDate {
            return "\(mediumDateFormatter.string(from: start)) – \(mediumDateFormatter.string(from: end))"
        } else if let start = trip.startDate {
            return "From \(mediumDateFormatter.string(from: start))"
        } else if let end = trip.endDate {
            return "Until \(mediumDateFormatter.string(from: end))"
        }
        return nil
    }

    // MARK: - Trip Date Range (used by CityLogs views)

    static func tripDateRange(start: Date, end: Date?) -> String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        if let end {
            return "\(start.formatted(fmt)) – \(end.formatted(fmt))"
        }
        return start.formatted(fmt)
    }
}
