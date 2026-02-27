//
//  ProfileCardStyle.swift
//  sonder
//
//  Created by Michael Song on 2/27/26.
//

import SwiftUI

// MARK: - Card Style Enum

enum ProfileCardStyle: String, CaseIterable, Identifiable {
    case classic
    case gradientTint
    case glassmorphic
    case accentBorder
    case mixed
    case themedHeader

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:      return "Classic"
        case .gradientTint: return "Tinted"
        case .glassmorphic: return "Glass"
        case .accentBorder: return "Accent"
        case .mixed:        return "Mixed"
        case .themedHeader: return "Themed"
        }
    }
}

// MARK: - Environment Key

private struct ProfileCardStyleKey: EnvironmentKey {
    static let defaultValue: ProfileCardStyle = .classic
}

extension EnvironmentValues {
    var profileCardStyle: ProfileCardStyle {
        get { self[ProfileCardStyleKey.self] }
        set { self[ProfileCardStyleKey.self] = newValue }
    }
}

// MARK: - Section Card Modifier

struct ProfileSectionCardModifier: ViewModifier {
    @Environment(\.profileCardStyle) var style
    let tint: Color
    let isFullBleed: Bool

    func body(content: Content) -> some View {
        switch style {

        // ── A: Current flat warmGray ──────────────────────────
        case .classic:
            content
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))

        // ── B: Subtle gradient tint per section ──────────────
        case .gradientTint:
            content
                .padding(SonderSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.10),
                                    SonderColors.warmGray.opacity(0.7),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))

        // ── C: Frosted glass ─────────────────────────────────
        case .glassmorphic:
            content
                .padding(SonderSpacing.md)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
                .overlay(
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                        .stroke(SonderColors.warmGrayDark.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 4, y: 2)

        // ── D: Colored left accent bar ───────────────────────
        case .accentBorder:
            content
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: SonderSpacing.radiusLg,
                        bottomLeadingRadius: SonderSpacing.radiusLg,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(tint.opacity(0.7))
                    .frame(width: 4)
                }

        // ── E: Mixed — visual sections full-bleed, data in subtle card
        case .mixed:
            if isFullBleed {
                // No card — content floats on the cream background
                content
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xs)
            } else {
                content
                    .padding(SonderSpacing.md)
                    .background(Color.white.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
                    .overlay(
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                            .stroke(SonderColors.warmGrayDark.opacity(0.18), lineWidth: 0.5)
                    )

            }

        // ── F: Themed headers — gradient top edge ────────────
        case .themedHeader:
            content
                .padding(SonderSpacing.md)
                .background(
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                            .fill(SonderColors.warmGray)
                        RoundedRectangle(cornerRadius: SonderSpacing.radiusLg)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.14), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the current profile section card style.
    /// - Parameters:
    ///   - tint: Theme color for this section (used by gradientTint, accentBorder, themedHeader styles)
    ///   - isFullBleed: If true, the "mixed" style renders this section without a card background
    func profileSectionCard(
        tint: Color = SonderColors.terracotta,
        isFullBleed: Bool = false
    ) -> some View {
        modifier(ProfileSectionCardModifier(tint: tint, isFullBleed: isFullBleed))
    }
}

// MARK: - Style Picker

struct ProfileCardStylePicker: View {
    @Binding var style: ProfileCardStyle

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SonderSpacing.xs) {
                ForEach(ProfileCardStyle.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            style = option
                        }
                    } label: {
                        Text(option.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, SonderSpacing.sm)
                            .padding(.vertical, SonderSpacing.xxs)
                            .background(
                                style == option
                                    ? SonderColors.terracotta
                                    : SonderColors.warmGray
                            )
                            .foregroundStyle(
                                style == option
                                    ? .white
                                    : SonderColors.inkDark
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, SonderSpacing.md)
        }
    }
}
