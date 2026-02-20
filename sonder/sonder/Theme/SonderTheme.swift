//
//  SonderTheme.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI

/// Sonder's warm journal color palette
enum SonderColors {
    // MARK: - Backgrounds

    /// Warm off-white for primary backgrounds
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.93)

    /// Slightly darker warm tone for cards/sections
    static let warmGray = Color(red: 0.95, green: 0.92, blue: 0.88)

    /// Even warmer for pressed/selected states
    static let warmGrayDark = Color(red: 0.90, green: 0.86, blue: 0.80)

    // MARK: - Text

    /// Warm charcoal for primary text (not pure black)
    static let inkDark = Color(red: 0.20, green: 0.18, blue: 0.16)

    /// Muted warm gray for secondary text
    static let inkMuted = Color(red: 0.50, green: 0.46, blue: 0.42)

    /// Lighter for tertiary/hint text
    static let inkLight = Color(red: 0.68, green: 0.64, blue: 0.58)

    // MARK: - Accent Colors (Earthy)

    /// Terracotta - warm, inviting primary accent
    static let terracotta = Color(red: 0.80, green: 0.45, blue: 0.35)

    /// Sage green - calm, natural
    static let sage = Color(red: 0.55, green: 0.65, blue: 0.52)

    /// Golden ochre - warm highlight
    static let ochre = Color(red: 0.85, green: 0.68, blue: 0.40)

    /// Dusty rose - soft accent
    static let dustyRose = Color(red: 0.78, green: 0.58, blue: 0.58)

    /// Warm blue - trustworthy but not cold
    static let warmBlue = Color(red: 0.45, green: 0.58, blue: 0.68)

    // MARK: - Rating Colors

    /// Skip - muted, neutral stone
    static let ratingSkip = Color(red: 0.62, green: 0.60, blue: 0.56)

    /// Okay - reliable sage green
    static let ratingOkay = Color(red: 0.55, green: 0.65, blue: 0.52)

    /// Great - golden ochre
    static let ratingGreat = Color(red: 0.82, green: 0.68, blue: 0.38)

    /// Must See - exciting terracotta/amber
    static let ratingMustSee = Color(red: 0.85, green: 0.55, blue: 0.35)

    // MARK: - Explore Map Colors

    /// Warm teal for Want to Go bookmark pins (distinct from rating colors)
    static let wantToGoPin = Color(red: 0.30, green: 0.58, blue: 0.62)

    /// Background for multi-friend cluster badges
    static let exploreCluster = Color(red: 0.25, green: 0.25, blue: 0.28)

    /// Map pin colors matching ratings
    static func pinColor(for rating: Rating) -> Color {
        switch rating {
        case .skip: return ratingSkip
        case .okay: return ratingOkay
        case .great: return ratingGreat
        case .mustSee: return ratingMustSee
        }
    }

    // MARK: - UIColor Variants (for UIKit appearance APIs)

    static let creamUI = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1.0)
    static let inkDarkUI = UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 1.0)
    static let terracottaUI = UIColor(red: 0.80, green: 0.45, blue: 0.35, alpha: 1.0)
}

/// Sonder's typography styles
/// Serif titles + rounded UI creates an editorial travel-journal aesthetic
enum SonderTypography {
    // Editorial serif headers — travel magazine feel (New York font)
    static let largeTitle = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    // Warm rounded for interactive elements — buttons, chips, labels
    static let headline = Font.system(.headline, design: .rounded)

    // Clean system defaults for body text — maximum readability
    static let body = Font.system(.body, design: .default)
    static let subheadline = Font.system(.subheadline, design: .default)
    static let caption = Font.system(.caption, design: .default)
}

/// Sonder's spacing and sizing
enum SonderSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    // Corner radii - generous and soft
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20
}

/// Sonder's shadow styles - soft and warm
enum SonderShadows {
    static let softRadius: CGFloat = 8
    static let softOpacity: Double = 0.08
    static let softY: CGFloat = 4
}

// MARK: - View Modifiers

struct WarmButtonStyle: ButtonStyle {
    var isPrimary: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SonderTypography.headline)
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.vertical, SonderSpacing.sm)
            .background(isPrimary ? SonderColors.terracotta : SonderColors.warmGray)
            .foregroundStyle(isPrimary ? .white : SonderColors.inkDark)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Expands the tap target of a toolbar icon to 56×56pt
    /// while keeping the visual icon size unchanged.
    func toolbarIcon() -> some View {
        self
            .frame(width: 56, height: 56)
            .contentShape(Rectangle())
    }
}
