//
//  TripExportRouteMap.swift
//  sonder
//
//  Created by Michael Song on 2/15/26.
//

import SwiftUI
import MapKit
import UIKit

/// Style 3: Bold Route Map — large map with numbered photo circles and bold info below.
/// Rendered at 1080x1920 for Instagram Stories.
struct TripExportRouteMap: View {
    let data: TripExportData
    let mapSnapshot: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            // Map section
            mapSection
                .frame(width: 1080, height: 1150)
                .clipped()

            // Info section on cream
            VStack(alignment: .leading, spacing: 16) {
                // Brand mark
                Text("sonder")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
                    .tracking(2)

                // Trip name — bold serif
                Text(data.tripName)
                    .font(.system(size: 80, weight: .bold, design: .serif))
                    .foregroundColor(SonderColors.inkDark)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                // Date + stats
                HStack(spacing: 12) {
                    if let dateText = data.dateRangeText {
                        Text(dateText)
                        Text("\u{00B7}")
                    }
                    Text("\(data.placeCount) \(data.placeCount == 1 ? "place" : "places")")
                }
                .font(.system(size: 32))
                .foregroundColor(SonderColors.inkMuted)

                // Ratings
                HStack(spacing: 24) {
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
                .font(.system(size: 36))
                .foregroundColor(SonderColors.inkMuted)

                // Stop list (up to 5)
                if !data.stops.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(data.stops.prefix(5).enumerated()), id: \.offset) { index, stop in
                            HStack(spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .foregroundColor(SonderColors.terracotta)
                                    .frame(width: 48, alignment: .trailing)

                                Text(stop.placeName)
                                    .font(.system(size: 30))
                                    .foregroundColor(SonderColors.inkDark)
                                    .lineLimit(1)

                                Spacer()

                                Text(stop.rating.emoji)
                                    .font(.system(size: 32))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 20)

            Spacer(minLength: 0)

            // Footer
            HStack {
                Spacer()
                Text("sonder")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta) +
                Text("  \u{00B7}  your travel story")
                    .font(.system(size: 24))
                    .foregroundColor(SonderColors.inkLight)
                Spacer()
            }
            .padding(.bottom, 40)
        }
        .frame(width: 1080, height: 1920)
        .background(SonderColors.cream)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        ZStack {
            if let snapshot = mapSnapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 1080, height: 1150)
            } else {
                Rectangle()
                    .fill(SonderColors.warmGray)
                    .frame(width: 1080, height: 1150)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "map")
                                .font(.system(size: 48))
                                .foregroundColor(SonderColors.inkLight)
                            Text("Map")
                                .font(.system(size: 20))
                                .foregroundColor(SonderColors.inkLight)
                        }
                    }
            }

            // Bottom fade into cream
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, SonderColors.cream],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
            }
        }
    }
}

// MARK: - Map Snapshot Generator

enum TripMapSnapshotGenerator {
    /// Generates a map snapshot with numbered circles at each stop and dashed route lines.
    /// The snapshot is at 1080x1150 pixels.
    static func generateSnapshot(
        stops: [ExportStop],
        logPhotos: [LogPhotoData]
    ) async -> UIImage? {
        guard !stops.isEmpty else { return nil }

        // Calculate region covering all stops with padding
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
        options.size = CGSize(width: 1080, height: 1150)
        options.mapType = .mutedStandard

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            return drawOverlay(on: snapshot, stops: stops, logPhotos: logPhotos)
        } catch {
            return nil
        }
    }

    private static func drawOverlay(
        on snapshot: MKMapSnapshotter.Snapshot,
        stops: [ExportStop],
        logPhotos: [LogPhotoData]
    ) -> UIImage {
        let image = snapshot.image
        let size = image.size

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Draw the map base
            image.draw(at: .zero)

            let context = ctx.cgContext

            // Convert stops to screen points
            let points = stops.map { snapshot.point(for: $0.coordinate) }

            // Draw dashed route line (6pt width)
            if points.count >= 2 {
                context.setStrokeColor(UIColor(SonderColors.terracotta).cgColor)
                context.setLineWidth(6)
                context.setLineDash(phase: 0, lengths: [16, 10])
                context.setLineCap(.round)

                context.move(to: points[0])
                for i in 1..<points.count {
                    context.addLine(to: points[i])
                }
                context.strokePath()
            }

            // Draw numbered circles at each stop (100pt diameter)
            let circleSize: CGFloat = 100
            for (index, point) in points.enumerated() {
                let rect = CGRect(
                    x: point.x - circleSize / 2,
                    y: point.y - circleSize / 2,
                    width: circleSize,
                    height: circleSize
                )

                // White border circle (5pt)
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: rect.insetBy(dx: -5, dy: -5))

                // Photo circle or colored fill
                if index < logPhotos.count {
                    // Clip to circle and draw photo
                    context.saveGState()
                    context.addEllipse(in: rect)
                    context.clip()
                    logPhotos[index].image.draw(in: rect)
                    context.restoreGState()
                } else {
                    // Terracotta fill fallback
                    context.setFillColor(UIColor(SonderColors.terracotta).withAlphaComponent(0.3).cgColor)
                    context.fillEllipse(in: rect)
                }

                // White border stroke
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(5)
                context.setLineDash(phase: 0, lengths: [])
                context.strokeEllipse(in: rect)

                // Number badge (36pt diameter)
                let badgeSize: CGFloat = 36
                let badgeRect = CGRect(
                    x: point.x + circleSize / 2 - badgeSize / 2,
                    y: point.y - circleSize / 2 - badgeSize / 4,
                    width: badgeSize,
                    height: badgeSize
                )

                // Badge background
                context.setFillColor(UIColor(SonderColors.terracotta).cgColor)
                context.fillEllipse(in: badgeRect)

                // Badge border
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(3)
                context.strokeEllipse(in: badgeRect)

                // Badge number (20pt font)
                let numberStr = "\(index + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let strSize = numberStr.size(withAttributes: attrs)
                let strRect = CGRect(
                    x: badgeRect.midX - strSize.width / 2,
                    y: badgeRect.midY - strSize.height / 2,
                    width: strSize.width,
                    height: strSize.height
                )
                numberStr.draw(in: strRect, withAttributes: attrs)
            }
        }
    }
}
