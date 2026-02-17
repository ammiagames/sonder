//
//  TripExportConfig.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

// MARK: - Export Aspect Ratio

enum ExportAspectRatio: String, CaseIterable, Identifiable {
    case stories, feed, square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stories: return "Stories 9:16"
        case .feed: return "Feed 4:5"
        case .square: return "Square 1:1"
        }
    }

    var icon: String {
        switch self {
        case .stories: return "rectangle.portrait"
        case .feed: return "rectangle.portrait.arrowtriangle.2.outward"
        case .square: return "square"
        }
    }

    var width: CGFloat { 1080 }

    var height: CGFloat {
        switch self {
        case .stories: return 1920
        case .feed: return 1350
        case .square: return 1080
        }
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

// MARK: - Export Color Theme

struct ExportColorTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let previewColors: [Color] // 3 dots for picker swatch
    let background: Color
    let backgroundSecondary: Color
    let accent: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let overlayGradient: [Gradient.Stop]

    static func == (lhs: ExportColorTheme, rhs: ExportColorTheme) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Predefined Themes

    static let classic = ExportColorTheme(
        id: "classic",
        name: "Classic",
        previewColors: [
            Color(red: 0.10, green: 0.09, blue: 0.08),
            Color(red: 0.80, green: 0.45, blue: 0.35),
            .white
        ],
        background: Color(red: 0.10, green: 0.09, blue: 0.08),
        backgroundSecondary: Color(red: 0.14, green: 0.13, blue: 0.12),
        accent: SonderColors.terracotta,
        textPrimary: .white,
        textSecondary: .white.opacity(0.8),
        textTertiary: .white.opacity(0.5),
        overlayGradient: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(0.3), location: 0.25),
            .init(color: .black.opacity(0.65), location: 0.55),
            .init(color: .black.opacity(0.85), location: 1.0),
        ]
    )

    static let warmSand = ExportColorTheme(
        id: "warmSand",
        name: "Warm Sand",
        previewColors: [
            Color(red: 0.98, green: 0.95, blue: 0.92),
            Color(red: 0.85, green: 0.68, blue: 0.40),
            Color(red: 0.20, green: 0.18, blue: 0.16)
        ],
        background: Color(red: 0.98, green: 0.95, blue: 0.92),
        backgroundSecondary: Color(red: 0.94, green: 0.90, blue: 0.85),
        accent: Color(red: 0.85, green: 0.68, blue: 0.40),
        textPrimary: Color(red: 0.20, green: 0.18, blue: 0.16),
        textSecondary: Color(red: 0.35, green: 0.32, blue: 0.28),
        textTertiary: Color(red: 0.50, green: 0.46, blue: 0.42),
        overlayGradient: [
            .init(color: .clear, location: 0),
            .init(color: Color(red: 0.98, green: 0.95, blue: 0.92).opacity(0.3), location: 0.25),
            .init(color: Color(red: 0.98, green: 0.95, blue: 0.92).opacity(0.7), location: 0.55),
            .init(color: Color(red: 0.98, green: 0.95, blue: 0.92).opacity(0.92), location: 1.0),
        ]
    )

    static let midnight = ExportColorTheme(
        id: "midnight",
        name: "Midnight",
        previewColors: [
            Color(red: 0.055, green: 0.086, blue: 0.16),
            Color(red: 0.83, green: 0.66, blue: 0.33),
            Color(red: 0.92, green: 0.94, blue: 0.96)
        ],
        background: Color(red: 0.055, green: 0.086, blue: 0.16),
        backgroundSecondary: Color(red: 0.08, green: 0.12, blue: 0.22),
        accent: Color(red: 0.83, green: 0.66, blue: 0.33),
        textPrimary: Color(red: 0.92, green: 0.94, blue: 0.96),
        textSecondary: Color(red: 0.92, green: 0.94, blue: 0.96).opacity(0.8),
        textTertiary: Color(red: 0.92, green: 0.94, blue: 0.96).opacity(0.5),
        overlayGradient: [
            .init(color: .clear, location: 0),
            .init(color: Color(red: 0.055, green: 0.086, blue: 0.16).opacity(0.3), location: 0.25),
            .init(color: Color(red: 0.055, green: 0.086, blue: 0.16).opacity(0.65), location: 0.55),
            .init(color: Color(red: 0.055, green: 0.086, blue: 0.16).opacity(0.88), location: 1.0),
        ]
    )

    static let sage = ExportColorTheme(
        id: "sage",
        name: "Sage",
        previewColors: [
            Color(red: 0.18, green: 0.23, blue: 0.18),
            Color(red: 0.55, green: 0.65, blue: 0.52),
            Color(red: 0.96, green: 0.94, blue: 0.91)
        ],
        background: Color(red: 0.18, green: 0.23, blue: 0.18),
        backgroundSecondary: Color(red: 0.22, green: 0.28, blue: 0.22),
        accent: Color(red: 0.55, green: 0.65, blue: 0.52),
        textPrimary: Color(red: 0.96, green: 0.94, blue: 0.91),
        textSecondary: Color(red: 0.96, green: 0.94, blue: 0.91).opacity(0.8),
        textTertiary: Color(red: 0.96, green: 0.94, blue: 0.91).opacity(0.5),
        overlayGradient: [
            .init(color: .clear, location: 0),
            .init(color: Color(red: 0.18, green: 0.23, blue: 0.18).opacity(0.3), location: 0.25),
            .init(color: Color(red: 0.18, green: 0.23, blue: 0.18).opacity(0.65), location: 0.55),
            .init(color: Color(red: 0.18, green: 0.23, blue: 0.18).opacity(0.88), location: 1.0),
        ]
    )

    static let dustyRose = ExportColorTheme(
        id: "dustyRose",
        name: "Dusty Rose",
        previewColors: [
            Color(red: 0.165, green: 0.125, blue: 0.145),
            Color(red: 0.78, green: 0.58, blue: 0.58),
            Color(red: 0.96, green: 0.92, blue: 0.93)
        ],
        background: Color(red: 0.165, green: 0.125, blue: 0.145),
        backgroundSecondary: Color(red: 0.22, green: 0.17, blue: 0.19),
        accent: Color(red: 0.78, green: 0.58, blue: 0.58),
        textPrimary: Color(red: 0.96, green: 0.92, blue: 0.93),
        textSecondary: Color(red: 0.96, green: 0.92, blue: 0.93).opacity(0.8),
        textTertiary: Color(red: 0.96, green: 0.92, blue: 0.93).opacity(0.5),
        overlayGradient: [
            .init(color: .clear, location: 0),
            .init(color: Color(red: 0.165, green: 0.125, blue: 0.145).opacity(0.3), location: 0.25),
            .init(color: Color(red: 0.165, green: 0.125, blue: 0.145).opacity(0.65), location: 0.55),
            .init(color: Color(red: 0.165, green: 0.125, blue: 0.145).opacity(0.88), location: 1.0),
        ]
    )

    static let allThemes: [ExportColorTheme] = [.classic, .warmSand, .midnight, .sage, .dustyRose]
}

// MARK: - Trip Export Customization

struct TripExportCustomization: Equatable {
    var theme: ExportColorTheme = .classic
    var aspectRatio: ExportAspectRatio = .stories
    var customCaption: String = ""
    var selectedHeroPhotoIndex: Int = 0
    var selectedLogPhotoIndices: Set<Int> = []

    var canvasSize: CGSize { aspectRatio.size }
}
