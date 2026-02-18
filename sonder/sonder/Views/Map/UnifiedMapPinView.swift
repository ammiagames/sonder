//
//  UnifiedMapPinView.swift
//  sonder
//
//  Pin views for the unified map: personal, friends, and combined.
//

import SwiftUI

// MARK: - Shared Pin Photo Constants

/// Standard size for all map pin place photos so prefetch and render share cache entries.
/// Uses the largest pin size (48pt combined must-see) so images are sharp at every tier.
enum PinPhotoConstants {
    static let pointSize = CGSize(width: 48, height: 48)
    /// 48 * 3 for @3x displays
    static let maxWidth = 144
}

// MARK: - Want to Go Tab

/// Bookmark badge that appears at the top-right corner of a pin when the place
/// is on the Want to Go list. Circular background with a bookmark icon.
struct WantToGoTab: View {
    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(SonderColors.wantToGoPin, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
    }
}

private struct PinPhotoFallback: View {
    let size: CGFloat
    let seedKey: String

    private var seed: Int {
        abs(seedKey.hashValue)
    }

    private var palette: (Color, Color, Color) {
        let palettes: [(Color, Color, Color)] = [
            (Color(red: 0.91, green: 0.87, blue: 0.82), Color(red: 0.80, green: 0.76, blue: 0.71), Color(red: 0.98, green: 0.95, blue: 0.90)),
            (Color(red: 0.89, green: 0.85, blue: 0.81), Color(red: 0.78, green: 0.73, blue: 0.69), Color(red: 0.96, green: 0.92, blue: 0.87)),
            (Color(red: 0.88, green: 0.86, blue: 0.82), Color(red: 0.76, green: 0.74, blue: 0.70), Color(red: 0.95, green: 0.92, blue: 0.88)),
            (Color(red: 0.90, green: 0.86, blue: 0.80), Color(red: 0.79, green: 0.75, blue: 0.70), Color(red: 0.97, green: 0.93, blue: 0.87))
        ]
        return palettes[seed % palettes.count]
    }

    private var highlightCenter: UnitPoint {
        let options: [UnitPoint] = [
            UnitPoint(x: 0.24, y: 0.22),
            UnitPoint(x: 0.72, y: 0.30),
            UnitPoint(x: 0.36, y: 0.74),
            UnitPoint(x: 0.68, y: 0.70)
        ]
        return options[seed % options.count]
    }

    private var gleamRotation: Double {
        Double((seed % 20) - 10)
    }

    var body: some View {
        let tones = palette

        return Circle()
            .fill(
                LinearGradient(
                    colors: [tones.0, tones.1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tones.2.opacity(0.70), .clear],
                            center: highlightCenter,
                            startRadius: 1,
                            endRadius: size * 0.72
                        )
                    )
            }
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.black.opacity(0.08), .clear],
                            center: UnitPoint(x: 0.82, y: 0.88),
                            startRadius: 1,
                            endRadius: size * 0.85
                        )
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: size * 0.52, height: size * 0.12)
                    .blur(radius: 0.9)
                    .rotationEffect(.degrees(gleamRotation))
                    .offset(x: -(size * 0.10), y: -(size * 0.18))
            }
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            }
    }
}

// MARK: - Log Pin View

/// Personal log pin — photo circle with terracotta ring.
/// Rating is encoded through subtle visual weight (size/ring/shadow/saturation).
struct LogPinView: View {
    let rating: Rating
    var photoURL: String? = nil
    var photoReference: String? = nil
    var visitCount: Int = 1
    var isWantToGo: Bool = false

    private var pinSize: CGFloat {
        switch rating {
        case .mustSee: return 44
        case .solid: return 38
        case .skip: return 32
        }
    }

    private var ringWidth: CGFloat {
        switch rating {
        case .mustSee: return 3.5
        case .solid: return 2.5
        case .skip: return 1.5
        }
    }

    private var shadowRadius: CGFloat {
        switch rating {
        case .mustSee: return 6
        case .solid: return 3
        case .skip: return 1.5
        }
    }

    private var shadowColor: Color {
        switch rating {
        case .mustSee: return SonderColors.ochre.opacity(0.5)
        case .solid: return .black.opacity(0.2)
        case .skip: return .black.opacity(0.12)
        }
    }

    private var saturation: Double {
        switch rating {
        case .mustSee: return 1.0
        case .solid: return 0.85
        case .skip: return 0.5
        }
    }

    private var placeholderSeedKey: String {
        photoURL ?? photoReference ?? "pin-\(rating.rawValue)"
    }

    /// Resolve best photo URL: user photo > Google Places > nil (warm placeholder)
    private var resolvedPhotoURL: URL? {
        if let userPhoto = photoURL, let url = URL(string: userPhoto) {
            return url
        }
        if let ref = photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: PinPhotoConstants.maxWidth) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            pinVisual

            // Visit count badge at bottom-left
            if visitCount > 1 {
                Text("×\(visitCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
                    .offset(x: -(pinSize * 0.44), y: pinSize * 0.39)
            }

            // Bookmark badge at top-right corner
            WantToGoTab()
                .offset(x: pinSize * 0.39, y: -(pinSize * 0.39))
                .opacity(isWantToGo ? 1 : 0)
                .scaleEffect(isWantToGo ? 1 : 0.3)
                .animation(.easeOut(duration: 0.25), value: isWantToGo)
        }
    }

    private var pinVisual: some View {
        Group {
            if let url = resolvedPhotoURL {
                DownsampledAsyncImage(url: url, targetSize: PinPhotoConstants.pointSize) {
                    photoPlaceholder
                }
                .saturation(saturation)
            } else {
                photoPlaceholder
            }
        }
        .frame(width: pinSize, height: pinSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(SonderColors.terracotta, lineWidth: ringWidth)
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }

    private var photoPlaceholder: some View {
        PinPhotoFallback(size: pinSize, seedKey: placeholderSeedKey)
    }
}

// MARK: - Unified Map Pin View

/// Renders the appropriate pin style based on UnifiedMapPin type
struct UnifiedMapPinView: View {
    let pin: UnifiedMapPin
    var isWantToGo: Bool = false

    var body: some View {
        switch pin {
        case .personal(let logs, let place):
            LogPinView(
                rating: logs.first?.rating ?? .solid,
                photoURL: logs.first(where: { $0.photoURL != nil })?.photoURL,
                photoReference: place.photoReference,
                visitCount: logs.count,
                isWantToGo: isWantToGo
            )
        case .friends(let place):
            ExploreMapPinView(place: place, isWantToGo: isWantToGo)
        case .combined(let logs, let place, let friendPlace):
            CombinedMapPinView(
                rating: logs.first?.rating ?? .solid,
                photoURL: logs.first(where: { $0.photoURL != nil })?.photoURL,
                photoReference: place.photoReference,
                friendCount: friendPlace.friendCount,
                isFriendsLoved: friendPlace.isFriendsLoved,
                hasNote: friendPlace.hasNote,
                visitCount: logs.count,
                isWantToGo: isWantToGo
            )
        }
    }
}

// MARK: - Combined Map Pin View

/// Pin for places logged by both the user and friends.
/// Terracotta ring = "yours", person badge = "friends also logged this".
/// Photo + compound rating signals (size, ring, glow, saturation).
struct CombinedMapPinView: View {
    let rating: Rating
    var photoURL: String? = nil
    var photoReference: String? = nil
    let friendCount: Int
    let isFriendsLoved: Bool
    var hasNote: Bool = false
    var visitCount: Int = 1
    var isWantToGo: Bool = false

    // Combined pins are slightly larger than personal pins at each tier
    private var pinSize: CGFloat {
        switch rating {
        case .mustSee: return 48
        case .solid: return 42
        case .skip: return 36
        }
    }

    private var ringWidth: CGFloat {
        switch rating {
        case .mustSee: return 3.5
        case .solid: return 2.5
        case .skip: return 1.5
        }
    }

    private var shadowRadius: CGFloat {
        switch rating {
        case .mustSee: return 6
        case .solid: return 3
        case .skip: return 1.5
        }
    }

    private var shadowColor: Color {
        switch rating {
        case .mustSee: return SonderColors.ochre.opacity(0.5)
        case .solid: return .black.opacity(0.2)
        case .skip: return .black.opacity(0.12)
        }
    }

    private var saturation: Double {
        switch rating {
        case .mustSee: return 1.0
        case .solid: return 0.85
        case .skip: return 0.5
        }
    }

    private var placeholderSeedKey: String {
        photoURL ?? photoReference ?? "combined-\(rating.rawValue)"
    }

    private var resolvedPhotoURL: URL? {
        if let userPhoto = photoURL, let url = URL(string: userPhoto) {
            return url
        }
        if let ref = photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: PinPhotoConstants.maxWidth) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            pinVisual

            // Friend badge (right side) — person icon + count
            HStack(spacing: 2) {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .bold))
                if friendCount > 1 {
                    Text("\(friendCount)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(SonderColors.exploreCluster)
            .clipShape(Capsule())
            .offset(x: pinSize * 0.55, y: -(pinSize * 0.15))

            // Visit count badge at bottom-left
            if visitCount > 1 {
                Text("×\(visitCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(SonderColors.terracotta)
                    .clipShape(Capsule())
                    .offset(x: -(pinSize * 0.44), y: pinSize * 0.35)
            }

            // Fire badge if friends loved
            if isFriendsLoved {
                Text("\u{1F525}")
                    .font(.system(size: 10))
                    .padding(2)
                    .background(SonderColors.cream)
                    .clipShape(Circle())
                    .offset(x: pinSize * 0.55, y: pinSize * 0.2)
            }

            // Note badge at bottom-right
            if hasNote {
                Image(systemName: "text.quote")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SonderColors.inkDark)
                    .frame(width: 16, height: 16)
                    .background(SonderColors.cream, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    .offset(x: -(pinSize * 0.44), y: pinSize * 0.35)
            }

            // Bookmark badge at top-right corner
            WantToGoTab()
                .offset(x: pinSize * 0.39, y: -(pinSize * 0.39))
                .opacity(isWantToGo ? 1 : 0)
                .scaleEffect(isWantToGo ? 1 : 0.3)
                .animation(.easeOut(duration: 0.25), value: isWantToGo)
        }
    }

    private var pinVisual: some View {
        Group {
            if let url = resolvedPhotoURL {
                DownsampledAsyncImage(url: url, targetSize: PinPhotoConstants.pointSize) {
                    photoPlaceholder
                }
                .saturation(saturation)
            } else {
                photoPlaceholder
            }
        }
        .frame(width: pinSize, height: pinSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(SonderColors.terracotta, lineWidth: ringWidth)
        }
        .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }

    private var photoPlaceholder: some View {
        PinPhotoFallback(size: pinSize, seedKey: placeholderSeedKey)
    }
}
