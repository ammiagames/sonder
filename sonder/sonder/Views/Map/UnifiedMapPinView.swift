//
//  UnifiedMapPinView.swift
//  sonder
//
//  Pin views for the unified map: personal, friends, and combined.
//

import SwiftUI

// MARK: - Want to Go Tab

/// Bookmark badge that appears at the top-right corner of a pin when the place
/// is on the Want to Go list. Circular background with a bookmark icon.
struct WantToGoTab: View {
    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 18, height: 18)
            .background(SonderColors.wantToGoPin, in: Circle())
            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
    }
}

// MARK: - Log Pin View

/// Personal log pin — photo circle with terracotta ring.
/// Rating is communicated through pin size, ring thickness, shadow intensity,
/// and photo saturation rather than an explicit emoji badge.
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

    /// Resolve best photo URL: user photo > Google Places > nil (emoji fallback)
    private var resolvedPhotoURL: URL? {
        if let userPhoto = photoURL, let url = URL(string: userPhoto) {
            return url
        }
        if let ref = photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: Int(pinSize * 3)) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let url = resolvedPhotoURL {
                // Photo pin
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: pinSize * 2, height: pinSize * 2)) {
                    emojiFallback
                }
                .frame(width: pinSize, height: pinSize)
                .clipShape(Circle())
                .saturation(saturation)
                .overlay {
                    Circle()
                        .stroke(SonderColors.terracotta, lineWidth: ringWidth)
                }
                .shadow(color: shadowColor, radius: shadowRadius, y: 1)
            } else {
                // Emoji fallback (no photo available)
                emojiFallback
            }

            // Visit count badge at bottom-left
            if visitCount > 1 {
                Text("×\(visitCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
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

    private var emojiFallback: some View {
        Circle()
            .fill(SonderColors.pinColor(for: rating))
            .frame(width: pinSize, height: pinSize)
            .overlay {
                Circle()
                    .stroke(SonderColors.terracotta, lineWidth: ringWidth)
            }
            .overlay {
                Text(rating.emoji)
                    .font(.system(size: pinSize * 0.5))
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: 1)
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

    private var resolvedPhotoURL: URL? {
        if let userPhoto = photoURL, let url = URL(string: userPhoto) {
            return url
        }
        if let ref = photoReference,
           let url = GooglePlacesService.photoURL(for: ref, maxWidth: Int(pinSize * 3)) {
            return url
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let url = resolvedPhotoURL {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: pinSize * 2, height: pinSize * 2)) {
                    emojiFallback
                }
                .frame(width: pinSize, height: pinSize)
                .clipShape(Circle())
                .saturation(saturation)
                .overlay {
                    Circle()
                        .stroke(SonderColors.terracotta, lineWidth: ringWidth)
                }
                .shadow(color: shadowColor, radius: shadowRadius, y: 1)
            } else {
                emojiFallback
            }

            // Friend badge (right side) — person icon + count
            HStack(spacing: 2) {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .bold))
                if friendCount > 1 {
                    Text("\(friendCount)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(SonderColors.exploreCluster)
            .clipShape(Capsule())
            .offset(x: pinSize * 0.55, y: -(pinSize * 0.15))

            // Visit count badge at bottom-left
            if visitCount > 1 {
                Text("×\(visitCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
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
                    .foregroundColor(SonderColors.inkDark)
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

    private var emojiFallback: some View {
        Circle()
            .fill(SonderColors.pinColor(for: rating))
            .frame(width: pinSize, height: pinSize)
            .overlay {
                Circle()
                    .stroke(SonderColors.terracotta, lineWidth: ringWidth)
            }
            .overlay {
                Text(rating.emoji)
                    .font(.system(size: pinSize * 0.5))
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: 1)
    }
}
