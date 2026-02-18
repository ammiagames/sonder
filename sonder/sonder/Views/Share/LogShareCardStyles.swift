//
//  LogShareCardStyles.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI

// MARK: - Share Card Data

/// All the data needed to render a shareable log card.
struct LogShareCardData {
    let placeName: String
    let cityName: String
    let rating: Rating
    let photo: UIImage?
    let note: String?
    let tags: [String]
    let date: Date
    let username: String
    let placeNumber: Int?      // "Place #47"
    let mustSeeCount: Int?     // "12th must-see"

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    var milestoneText: String? {
        if let n = placeNumber { return "Place #\(n)" }
        return nil
    }
}

// MARK: - Shared Constants

private let canvasWidth: CGFloat = 1080
private let canvasHeight: CGFloat = 1350  // 4:5 ratio

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Style A: The Film Frame
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Analog film print aesthetic — photo with white border, clean serif type below.
struct LogShareFilmFrame: View {
    let data: LogShareCardData

    private let border: CGFloat = 48
    private let bottomStrip: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            // Photo area with film border
            photoArea
                .padding(.horizontal, border)
                .padding(.top, border)

            Spacer(minLength: 0)

            // Info strip
            infoStrip
                .padding(.horizontal, border + 8)
                .padding(.bottom, border)
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .background(.white)
    }

    private var photoArea: some View {
        let photoWidth = canvasWidth - border * 2
        let photoHeight = canvasHeight - bottomStrip - border
        return Group {
            if let image = data.photo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photoWidth, height: photoHeight)
                    .clipped()
            } else {
                photoPlaceholder(width: photoWidth, height: photoHeight)
            }
        }
    }

    private var infoStrip: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            // Place name
            Text(data.placeName)
                .font(.system(size: 52, weight: .semibold, design: .serif))
                .foregroundStyle(Color(red: 0.15, green: 0.13, blue: 0.11))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)

            // City · Date
            HStack(spacing: 12) {
                Text(data.cityName.uppercased())
                    .tracking(2)
                Text("\u{00B7}")
                Text(data.formattedDate.uppercased())
                    .tracking(1)
            }
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(Color(red: 0.5, green: 0.47, blue: 0.43))

            Spacer(minLength: 0)

            // Bottom row: rating + sonder mark
            HStack {
                // Rating
                Text("\(data.rating.emoji) \(data.rating.displayName)")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(SonderColors.pinColor(for: data.rating))

                Spacer()

                Text("sonder")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.5))
            }
        }
        .frame(height: bottomStrip - border)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Style B: The Stamp
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Travel journal stamp aesthetic — photo with dashed border info panel.
struct LogShareStamp: View {
    let data: LogShareCardData

    private let margin: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            // Photo with stamp overlay
            ZStack(alignment: .topTrailing) {
                photoSection

                // Ink stamp rating
                ratingStamp
                    .padding(32)
            }

            Spacer(minLength: 24)

            // Luggage-tag info area
            infoTag
                .padding(.horizontal, margin)

            Spacer(minLength: 24)

            // Footer
            footer
                .padding(.horizontal, margin)
                .padding(.bottom, 40)
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .background(SonderColors.cream)
    }

    private var photoSection: some View {
        let w = canvasWidth - margin * 2
        return Group {
            if let image = data.photo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: w, height: 700)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                photoPlaceholder(width: w, height: 700)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding(.horizontal, margin)
        .padding(.top, margin)
    }

    private var ratingStamp: some View {
        ZStack {
            Circle()
                .stroke(SonderColors.terracotta, lineWidth: 5)
                .frame(width: 140, height: 140)

            Circle()
                .stroke(SonderColors.terracotta, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: 120, height: 120)

            VStack(spacing: 2) {
                Text(data.rating.emoji)
                    .font(.system(size: 40))
                Text(data.rating.displayName.uppercased())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(SonderColors.terracotta)
                    .tracking(1)
            }
        }
        .rotationEffect(.degrees(-15))
        .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
    }

    private var infoTag: some View {
        VStack(spacing: 16) {
            Text(data.placeName)
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: "mappin")
                    .font(.system(size: 22))
                Text(data.cityName)
                    .font(.system(size: 28))
            }
            .foregroundStyle(SonderColors.inkMuted)

            // Tags as small stamps
            if !data.tags.isEmpty {
                HStack(spacing: 10) {
                    ForEach(data.tags.prefix(3), id: \.self) { tag in
                        Text(tag.uppercased())
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(SonderColors.terracotta)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(SonderColors.terracotta, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            )
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SonderColors.inkLight, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
    }

    private var footer: some View {
        HStack {
            if let milestone = data.milestoneText {
                Text(milestone)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(SonderColors.inkMuted)
            }
            Spacer()
            Text("sonder")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(SonderColors.terracotta.opacity(0.5))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Style C: The Gradient Overlay
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Full-bleed photo with dark gradient and bold white text. Instagram-story native.
struct LogShareGradient: View {
    let data: LogShareCardData

    var body: some View {
        ZStack {
            // Full-bleed photo
            if let image = data.photo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [SonderColors.terracotta, SonderColors.ochre, Color(red: 0.3, green: 0.25, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Gradient overlay
            VStack {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.4), location: 0.3),
                        .init(color: .black.opacity(0.8), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: canvasHeight * 0.55)
            }

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Top: rating pill
                HStack {
                    Spacer()
                    ratingPill
                }
                .padding(48)

                Spacer()

                // Bottom: text info
                VStack(alignment: .leading, spacing: 16) {
                    Text(data.placeName)
                        .font(.system(size: 64, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)

                    Text(data.cityName)
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.8))

                    if let note = data.note, !note.isEmpty {
                        Text("\"\(note)\"")
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                            .padding(.top, 4)
                    }

                    // Tags
                    if !data.tags.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(data.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 8)
                    }

                    Spacer().frame(height: 24)

                    // Bottom bar
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.white.opacity(0.3))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Text(String(data.username.prefix(1)).uppercased())
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            Text("@\(data.username)")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        Text("sonder")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 56)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }

    private var ratingPill: some View {
        HStack(spacing: 10) {
            Text(data.rating.emoji)
                .font(.system(size: 36))
            Text(data.rating.displayName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(.black.opacity(0.3))
        .clipShape(Capsule())
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Style D: The Split
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Magazine editorial split — photo left, colored info panel right.
struct LogShareSplit: View {
    let data: LogShareCardData

    private let photoWidth: CGFloat = 580
    private var panelWidth: CGFloat { canvasWidth - photoWidth }

    var body: some View {
        HStack(spacing: 0) {
            // Photo side
            if let image = data.photo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photoWidth, height: canvasHeight)
                    .clipped()
            } else {
                photoPlaceholder(width: photoWidth, height: canvasHeight)
            }

            // Info panel
            infoPanel
                .frame(width: panelWidth, height: canvasHeight)
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }

    private var infoPanel: some View {
        ZStack {
            // Background — warm tone derived from rating
            panelBackground

            // Rating emoji watermark
            Text(data.rating.emoji)
                .font(.system(size: 280))
                .opacity(0.06)
                .rotationEffect(.degrees(-15))
                .offset(x: 40, y: -60)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 60)

                // Rating label
                Text(data.rating.displayName.uppercased())
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(SonderColors.terracotta)

                Spacer().frame(height: 24)

                // Place name — large stacked
                Text(data.placeName)
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 20)

                // City
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SonderColors.terracotta)
                    Text(data.cityName)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(SonderColors.inkMuted)
                }

                Spacer().frame(height: 12)

                // Date
                Text(data.formattedDate)
                    .font(.system(size: 24))
                    .foregroundStyle(SonderColors.inkLight)

                Spacer()

                // Tags
                if !data.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(data.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundStyle(SonderColors.terracotta)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(SonderColors.terracotta.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer().frame(height: 24)

                // Milestone + branding
                VStack(alignment: .leading, spacing: 8) {
                    if let milestone = data.milestoneText {
                        Text(milestone)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                    Text("sonder")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(SonderColors.terracotta.opacity(0.5))
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 36)
        }
    }

    private var panelBackground: some View {
        SonderColors.cream
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Style E: The Postcard
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Vintage postcard — landscape-feel with stamp and postmark.
struct LogSharePostcard: View {
    let data: LogShareCardData

    var body: some View {
        ZStack {
            // Background photo
            if let image = data.photo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [SonderColors.ochre.opacity(0.8), SonderColors.terracotta.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Subtle darkening
            Color.black.opacity(0.2)

            // Postcard content area
            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 0) {
                    // Left: info card
                    postcardInfo
                        .frame(width: 660)
                        .padding(.leading, 48)

                    Spacer()

                    // Right: stamp
                    postcardStamp
                        .padding(.trailing, 48)
                        .padding(.bottom, 20)
                }
                .padding(.bottom, 48)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }

    private var postcardInfo: some View {
        VStack(alignment: .leading, spacing: 16) {
            // "Wish you were here" or user note
            if let note = data.note, !note.isEmpty {
                Text("\"\(note)\"")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(SonderColors.inkDark.opacity(0.8))
                    .lineLimit(3)
            }

            // Place name
            Text(data.placeName)
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            // City + date postmark style
            HStack(spacing: 12) {
                Image(systemName: "mappin")
                    .font(.system(size: 20))
                Text(data.cityName)
                    .font(.system(size: 26, weight: .medium))
                Text("\u{00B7}")
                Text(data.formattedDate)
                    .font(.system(size: 24))
            }
            .foregroundStyle(SonderColors.inkMuted)

            // Sonder branding
            HStack {
                Spacer()
                Text("sonder")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.6))
            }
        }
        .padding(32)
        .background(SonderColors.cream.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private var postcardStamp: some View {
        VStack(spacing: 4) {
            // Stamp frame
            VStack(spacing: 8) {
                Text(data.rating.emoji)
                    .font(.system(size: 64))
                Text(data.rating.displayName.uppercased())
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(SonderColors.terracotta)
            }
            .frame(width: 160, height: 180)
            .background(SonderColors.cream)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(SonderColors.inkLight.opacity(0.3), lineWidth: 1)
            )
            // Perforated edge effect
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(SonderColors.cream, style: StrokeStyle(lineWidth: 3, dash: [2, 4]))
                    .padding(-4)
            )
        }
        .rotationEffect(.degrees(3))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Style F: The Minimal Card
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Apple-native clean aesthetic — inset photo, generous whitespace.
struct LogShareMinimal: View {
    let data: LogShareCardData

    private let margin: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: margin)

            // Inset photo
            Group {
                if let image = data.photo {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: canvasWidth - margin * 2,
                            height: 680
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                } else {
                    photoPlaceholder(
                        width: canvasWidth - margin * 2,
                        height: 680
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(.horizontal, margin)

            Spacer(minLength: 32)

            // Info area
            VStack(spacing: 20) {
                // Place name
                Text(data.placeName)
                    .font(.system(size: 52, weight: .semibold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)

                // City · Rating · Date
                HStack(spacing: 16) {
                    Text(data.cityName)
                    Text("\u{00B7}")
                    Text("\(data.rating.emoji) \(data.rating.displayName)")
                    Text("\u{00B7}")
                    Text(data.shortDate)
                }
                .font(.system(size: 26))
                .foregroundStyle(SonderColors.inkMuted)

                // Note
                if let note = data.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 28, weight: .regular, design: .default))
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Tags
                if !data.tags.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(data.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                .foregroundStyle(SonderColors.terracotta)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(SonderColors.terracotta.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, margin)

            Spacer(minLength: 16)

            // Divider
            Rectangle()
                .fill(SonderColors.warmGray)
                .frame(height: 2)
                .padding(.horizontal, margin)

            Spacer(minLength: 16)

            // Footer
            HStack {
                // Milestone
                if let milestone = data.milestoneText {
                    Text(milestone)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(SonderColors.inkLight)
                }

                Spacer()

                Text("sonder")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.4))
            }
            .padding(.horizontal, margin)

            Spacer(minLength: margin)
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .background(.white)
    }
}

// MARK: - Shared Helpers

private func photoPlaceholder(width: CGFloat, height: CGFloat) -> some View {
    LinearGradient(
        colors: [SonderColors.terracotta.opacity(0.15), SonderColors.ochre.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    .frame(width: width, height: height)
    .overlay {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
            Text("Your photo here")
                .font(.system(size: 24))
        }
        .foregroundStyle(SonderColors.terracotta.opacity(0.3))
    }
}

// MARK: - Previews

private let previewData = LogShareCardData(
    placeName: "Tatsu Ramen",
    cityName: "Los Angeles",
    rating: .mustSee,
    photo: nil,
    note: "Best ramen outside of Japan. The secret is the broth.",
    tags: ["ramen", "late night", "hidden gem"],
    date: Date(),
    username: "michaelsong",
    placeNumber: 47,
    mustSeeCount: 12
)

#Preview("A: Film Frame") {
    LogShareFilmFrame(data: previewData)
        .scaleEffect(0.35)
}

#Preview("B: Stamp") {
    LogShareStamp(data: previewData)
        .scaleEffect(0.35)
}

#Preview("C: Gradient") {
    LogShareGradient(data: previewData)
        .scaleEffect(0.35)
}

#Preview("D: Split") {
    LogShareSplit(data: previewData)
        .scaleEffect(0.35)
}

#Preview("E: Postcard") {
    LogSharePostcard(data: previewData)
        .scaleEffect(0.35)
}

#Preview("F: Minimal") {
    LogShareMinimal(data: previewData)
        .scaleEffect(0.35)
}
