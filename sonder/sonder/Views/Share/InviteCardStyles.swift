//
//  InviteCardStyles.swift
//  sonder
//

import SwiftUI

// MARK: - Data Model

struct InviteCardData {
    let inviterName: String
    let inviterUsername: String
    let photos: [UIImage] // Up to 3 photos for polaroid frames
}

// MARK: - Canvas Constants

private let canvasWidth: CGFloat = 1080
private let canvasHeight: CGFloat = 1350

// MARK: - Dotted Trail Card

struct InviteCardDottedTrail: View {
    let data: InviteCardData

    var body: some View {
        ZStack {
            SonderColors.cream

            // Dotted trail canvas
            Canvas { context, size in
                let trailColor = SonderColors.terracotta

                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.30))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.45, y: size.height * 0.38),
                    control1: CGPoint(x: size.width * 0.25, y: size.height * 0.22),
                    control2: CGPoint(x: size.width * 0.35, y: size.height * 0.42)
                )
                path.addCurve(
                    to: CGPoint(x: size.width * 0.75, y: size.height * 0.50),
                    control1: CGPoint(x: size.width * 0.55, y: size.height * 0.34),
                    control2: CGPoint(x: size.width * 0.65, y: size.height * 0.55)
                )
                path.addCurve(
                    to: CGPoint(x: size.width * 0.88, y: size.height * 0.62),
                    control1: CGPoint(x: size.width * 0.82, y: size.height * 0.46),
                    control2: CGPoint(x: size.width * 0.90, y: size.height * 0.56)
                )

                context.stroke(
                    path,
                    with: .color(trailColor.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 4, dash: [8, 8])
                )
            }

            // Pin drops along the trail
            VStack(spacing: 0) {
                Spacer().frame(height: canvasHeight * 0.24)

                HStack(spacing: 0) {
                    Spacer().frame(width: canvasWidth * 0.10)
                    pinDrop(emoji: "🌮")
                    Spacer()
                }

                Spacer().frame(height: canvasHeight * 0.04)

                HStack(spacing: 0) {
                    Spacer()
                    pinDrop(emoji: "☕")
                        .offset(x: -canvasWidth * 0.08)
                    Spacer()
                }

                Spacer().frame(height: canvasHeight * 0.02)

                HStack(spacing: 0) {
                    Spacer()
                    pinDrop(emoji: "⭐")
                        .offset(x: canvasWidth * 0.10)
                    Spacer()
                }

                Spacer().frame(height: canvasHeight * 0.02)

                HStack(spacing: 0) {
                    Spacer()
                    pinDrop(emoji: "📸")
                    Spacer().frame(width: canvasWidth * 0.08)
                }

                Spacer()
            }

            // Polaroid frames along the trail
            polaroidFrame(index: 0)
                .rotationEffect(.degrees(-8))
                .position(x: canvasWidth * 0.30, y: canvasHeight * 0.32)

            polaroidFrame(index: 1)
                .rotationEffect(.degrees(12))
                .position(x: canvasWidth * 0.62, y: canvasHeight * 0.44)

            polaroidFrame(index: 2)
                .rotationEffect(.degrees(-5))
                .position(x: canvasWidth * 0.80, y: canvasHeight * 0.58)

            // Text content
            VStack(spacing: 20) {
                Spacer()

                Text("Your next spot awaits.")
                    .font(.system(size: 72, weight: .bold, design: .serif))
                    .foregroundStyle(SonderColors.inkDark)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)

                Text("@\(data.inviterUsername) invites you")
                    .font(.system(size: 32))
                    .foregroundStyle(SonderColors.inkMuted)

                Text("apps.apple.com/app/sonder")
                    .font(.system(size: 26))
                    .foregroundStyle(SonderColors.terracotta.opacity(0.6))

                Spacer().frame(height: 60)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }

    private func pinDrop(emoji: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 36))
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(SonderColors.terracotta)
        }
    }

    private func polaroidFrame(index: Int) -> some View {
        let photoSize: CGFloat = 136
        let frameWidth: CGFloat = 160
        let frameHeight: CGFloat = 192

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.white)
                .frame(width: frameWidth, height: frameHeight)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            if index < data.photos.count {
                Image(uiImage: data.photos[index])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photoSize, height: photoSize)
                    .clipped()
                    .offset(y: -16)
            } else {
                // Gradient placeholder when no photo available
                RoundedRectangle(cornerRadius: 2)
                    .fill(placeholderGradient(for: index))
                    .frame(width: photoSize, height: photoSize)
                    .offset(y: -16)
            }
        }
    }

    private func placeholderGradient(for index: Int) -> LinearGradient {
        let gradients: [(Color, Color)] = [
            (SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)),
            (SonderColors.sage.opacity(0.3), SonderColors.warmBlue.opacity(0.2)),
            (SonderColors.dustyRose.opacity(0.3), SonderColors.terracotta.opacity(0.2)),
        ]
        let pair = gradients[index % gradients.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Preview

#Preview {
    InviteCardDottedTrail(data: InviteCardData(
        inviterName: "Michael",
        inviterUsername: "michael",
        photos: []
    ))
    .scaleEffect(0.35)
    .frame(width: 1080 * 0.35, height: 1350 * 0.35)
}
