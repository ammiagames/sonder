//
//  TripExportRouteMap.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI
import MapKit
import UIKit

/// Style 2: The Annotated Map — clean map with small markers + field notes list.
struct TripExportRouteMap: View {
    let data: TripExportData
    let mapSnapshot: UIImage?
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }

    private var maxFieldNotes: Int {
        switch canvasSize.height {
        case 1920: return 6
        case 1350: return 4
        default: return 3
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map — top ~55%
            mapBackground

            // Frosted info panel — bottom ~45%
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 16 * s) {
                    // Trip name
                    Text(data.tripName)
                        .font(.system(size: 72 * s, weight: .bold, design: .serif))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)

                    // Date range
                    if let dateText = data.dateRangeText {
                        Text(dateText)
                            .font(.system(size: 28 * s))
                            .foregroundColor(theme.textSecondary)
                    }

                    // Field notes list
                    fieldNotesList

                    // Rating summary
                    HStack(spacing: 24 * s) {
                        if data.ratingCounts.mustSee > 0 {
                            Text("\(Rating.mustSee.emoji) \(data.ratingCounts.mustSee)")
                        }
                        if data.ratingCounts.solid > 0 {
                            Text("\(Rating.solid.emoji) \(data.ratingCounts.solid)")
                        }
                        if data.ratingCounts.skip > 0 {
                            Text("\(Rating.skip.emoji) \(data.ratingCounts.skip)")
                        }
                    }
                    .font(.system(size: 34 * s))
                    .foregroundColor(theme.textSecondary.opacity(0.85))

                    // Caption
                    if let caption = data.customCaption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 26 * s, design: .serif))
                            .italic()
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(2)
                    }

                    // Footer
                    HStack {
                        Spacer()
                        Text("sonder")
                            .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.textTertiary) +
                        Text("  \u{00B7}  your travel story")
                            .font(.system(size: 22 * s))
                            .foregroundColor(theme.textTertiary)
                        Spacer()
                    }
                    .padding(.top, 4 * s)
                }
                .padding(.horizontal, 56 * s)
                .padding(.bottom, 40 * s)
            }
            .background(alignment: .bottom) {
                LinearGradient(
                    stops: theme.overlayGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 960 * s)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: - Map Background

    private var mapBackground: some View {
        Group {
            if let snapshot = mapSnapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [theme.backgroundSecondary, theme.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    VStack(spacing: 12 * s) {
                        Image(systemName: "map")
                            .font(.system(size: 64 * s))
                            .foregroundColor(theme.textTertiary)
                        Text("Map unavailable")
                            .font(.system(size: 24 * s))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Field Notes List

    private var fieldNotesList: some View {
        let stops = Array(data.stops.prefix(maxFieldNotes))
        return VStack(alignment: .leading, spacing: 14 * s) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                fieldNoteRow(index: index + 1, stop: stop)
            }

            // "+N more stops" if truncated
            if data.stops.count > maxFieldNotes {
                Text("+\(data.stops.count - maxFieldNotes) more stops")
                    .font(.system(size: 22 * s))
                    .foregroundColor(theme.textTertiary)
                    .padding(.leading, 44 * s)
            }
        }
        .padding(.vertical, 8 * s)
    }

    private func fieldNoteRow(index: Int, stop: ExportStop) -> some View {
        HStack(alignment: .top, spacing: 12 * s) {
            // Number badge
            Text("\(index)")
                .font(.system(size: 18 * s, weight: .bold, design: .rounded))
                .foregroundColor(theme.background)
                .frame(width: 30 * s, height: 30 * s)
                .background(theme.accent)
                .clipShape(Circle())

            // Stop info
            VStack(alignment: .leading, spacing: 4 * s) {
                // Place name + rating
                HStack(spacing: 8 * s) {
                    Text(stop.placeName)
                        .font(.system(size: 26 * s, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    Text(stop.rating.emoji)
                        .font(.system(size: 24 * s))
                }

                // Note (italic)
                if let note = stop.note, !note.isEmpty {
                    Text("\u{201C}\(note)\u{201D}")
                        .font(.system(size: 22 * s, design: .serif))
                        .italic()
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                // Tags
                if !stop.tags.isEmpty {
                    HStack(spacing: 6 * s) {
                        ForEach(Array(stop.tags.prefix(3)), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 18 * s, weight: .medium))
                                .foregroundColor(theme.accent)
                                .padding(.horizontal, 8 * s)
                                .padding(.vertical, 3 * s)
                                .background(theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Map Snapshot Generator

enum TripMapSnapshotGenerator {
    /// Generates a map snapshot with numbered dots at each stop and dashed route lines.
    static func generateSnapshot(
        stops: [ExportStop],
        logPhotos: [LogPhotoData],
        size: CGSize = CGSize(width: 1080, height: 1920),
        markerSize: CGFloat = 48,
        tintColor: UIColor = UIColor(SonderColors.terracotta)
    ) async -> UIImage? {
        guard !stops.isEmpty else { return nil }

        let lats = stops.map(\.coordinate.latitude)
        let lngs = stops.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.8, 0.02)
        let lngDelta = max((maxLng - minLng) * 1.8, 0.02)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .mutedStandard

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            return drawOverlay(on: snapshot, stops: stops, markerSize: markerSize, tintColor: tintColor)
        } catch {
            return nil
        }
    }

    private static func drawOverlay(
        on snapshot: MKMapSnapshotter.Snapshot,
        stops: [ExportStop],
        markerSize: CGFloat,
        tintColor: UIColor
    ) -> UIImage {
        let image = snapshot.image
        let size = image.size

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            image.draw(at: .zero)

            let context = ctx.cgContext
            let points = stops.map { snapshot.point(for: $0.coordinate) }

            // Dashed route line
            if points.count >= 2 {
                context.setStrokeColor(tintColor.cgColor)
                context.setLineWidth(6)
                context.setLineDash(phase: 0, lengths: [14, 8])
                context.setLineCap(.round)

                context.move(to: points[0])
                for i in 1..<points.count {
                    context.addLine(to: points[i])
                }
                context.strokePath()
            }

            // Numbered colored dots at each stop
            let circleSize: CGFloat = markerSize
            for (index, point) in points.enumerated() {
                let rect = CGRect(
                    x: point.x - circleSize / 2,
                    y: point.y - circleSize / 2,
                    width: circleSize,
                    height: circleSize
                )

                // White border
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: rect.insetBy(dx: -4, dy: -4))

                // Colored fill
                context.setFillColor(tintColor.cgColor)
                context.fillEllipse(in: rect)

                // White border stroke
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(4)
                context.setLineDash(phase: 0, lengths: [])
                context.strokeEllipse(in: rect)

                // Number text
                let numberStr = "\(index + 1)" as NSString
                let fontSize: CGFloat = circleSize * 0.5
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let strSize = numberStr.size(withAttributes: attrs)
                let strRect = CGRect(
                    x: rect.midX - strSize.width / 2,
                    y: rect.midY - strSize.height / 2,
                    width: strSize.width,
                    height: strSize.height
                )
                numberStr.draw(in: strRect, withAttributes: attrs)
            }
        }
    }
}
