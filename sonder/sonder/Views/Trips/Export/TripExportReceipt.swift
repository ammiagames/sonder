//
//  TripExportReceipt.swift
//  sonder
//
//  Thermal receipt aesthetic — monospace, itemized, retro-ironic.
//  Distinctive and meme-worthy. Nobody else has this.
//

import SwiftUI

struct TripExportReceipt: View {
    let data: TripExportData
    var theme: ExportColorTheme = .classic
    var canvasSize: CGSize = CGSize(width: 1080, height: 1920)

    private var s: CGFloat { canvasSize.height / 1920 }

    // Receipt palette — always warm paper, ignores theme for authenticity
    private let receiptBg = Color(red: 0.985, green: 0.965, blue: 0.935)
    private let ink = Color(red: 0.13, green: 0.12, blue: 0.11)
    private let faded = Color(red: 0.42, green: 0.39, blue: 0.36)

    private var maxItems: Int {
        switch canvasSize.height {
        case 1920: return 10
        case 1350: return 7
        default: return 5
        }
    }

    var body: some View {
        ZStack {
            receiptBg

            // Thermal print texture — faint horizontal bands
            thermalTexture

            // Receipt content centered
            VStack(spacing: 0) {
                Spacer().frame(height: 80 * s)

                receiptHeader
                spacer(40)
                doubleLine
                spacer(32)

                tripDetails
                spacer(28)
                dashedLine
                spacer(28)

                mono("ORDER DETAILS:", weight: .bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                spacer(20)

                orderItems
                spacer(28)
                dashedLine
                spacer(28)

                subtotals
                spacer(28)
                doubleLine
                spacer(40)

                thankYou
                spacer(48)

                barcodeDecoration
                spacer(20)

                // Timestamp
                mono(receiptTimestamp, size: 18, color: faded)
                spacer(12)
                mono("Logged on sonder", size: 18, color: faded)

                Spacer()
            }
            .padding(.horizontal, 100 * s)

            // Very subtle grain
            FilmGrainOverlay(opacity: 0.012, seed: data.tripName.hashValue &+ 3)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: - Header

    private var receiptHeader: some View {
        VStack(spacing: 12 * s) {
            // Decorative star line
            mono("\u{2605} \u{2605} \u{2605}", size: 20, color: faded)

            Text("S O N D E R")
                .font(.system(size: 44 * s, weight: .black, design: .monospaced))
                .foregroundColor(ink)
                .tracking(6 * s)

            mono("your travel story", size: 22, color: faded)
        }
    }

    // MARK: - Trip Details

    private var tripDetails: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            receiptRow("TRIP", data.tripName)
            if let dateText = data.dateRangeText {
                receiptRow("DATE", dateText)
            }
            receiptRow("DAYS", "\(data.dayCount)")
            receiptRow("STOPS", "\(data.placeCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            mono("\(label):", size: 24, weight: .bold)
                .frame(width: 130 * s, alignment: .leading)
            mono(value, size: 24)
                .lineLimit(2)
        }
    }

    // MARK: - Order Items

    private var orderItems: some View {
        let stops = Array(data.stops.prefix(maxItems))
        return VStack(alignment: .leading, spacing: 16 * s) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                VStack(alignment: .leading, spacing: 3 * s) {
                    // Place name + rating aligned right
                    HStack(spacing: 0) {
                        mono(String(format: "%02d. ", index + 1), size: 24, weight: .bold)
                        mono(stop.placeName, size: 24)
                            .lineLimit(1)
                        Spacer()
                        mono(stop.rating.emoji, size: 24)
                    }

                    // Note excerpt
                    if let note = stop.note, !note.isEmpty {
                        let excerpt = String(note.prefix(42))
                        mono("    \"\(excerpt)\"", size: 20, color: faded)
                            .lineLimit(1)
                    }
                }
            }

            if data.stops.count > maxItems {
                mono("    + \(data.stops.count - maxItems) more...", size: 22, color: faded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Subtotals

    private var subtotals: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            mono("SUBTOTAL", size: 24, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            spacer(6)

            if data.ratingCounts.mustSee > 0 {
                subtotalRow("MUST-SEE  \(Rating.mustSee.emoji)", count: data.ratingCounts.mustSee)
            }
            if data.ratingCounts.great > 0 {
                subtotalRow("GREAT     \(Rating.great.emoji)", count: data.ratingCounts.great)
            }
            if data.ratingCounts.okay > 0 {
                subtotalRow("OKAY      \(Rating.okay.emoji)", count: data.ratingCounts.okay)
            }
            if data.ratingCounts.skip > 0 {
                subtotalRow("SKIP      \(Rating.skip.emoji)", count: data.ratingCounts.skip)
            }

            spacer(10)
            dashedLine
            spacer(10)

            HStack {
                mono("TOTAL PLACES:", size: 26, weight: .bold)
                Spacer()
                mono("\(data.placeCount)", size: 26, weight: .bold)
            }

            HStack {
                mono("TOTAL DAYS:", size: 26, weight: .bold)
                Spacer()
                mono("\(data.dayCount)", size: 26, weight: .bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtotalRow(_ label: String, count: Int) -> some View {
        HStack {
            mono("  \(label)", size: 22)
            Spacer()
            mono("x\(count)", size: 22)
        }
    }

    // MARK: - Thank You

    private var thankYou: some View {
        VStack(spacing: 14 * s) {
            Text("THANK YOU")
                .font(.system(size: 38 * s, weight: .black, design: .monospaced))
                .foregroundColor(ink)
            Text("FOR TRAVELING")
                .font(.system(size: 38 * s, weight: .black, design: .monospaced))
                .foregroundColor(ink)

            spacer(10)

            if let caption = data.customCaption, !caption.isEmpty {
                mono("\"\(caption)\"", size: 22, color: faded)
                    .multilineTextAlignment(.center)
            } else {
                mono(data.tripName, size: 22, color: faded)
                mono("was a trip to remember.", size: 22, color: faded)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Barcode Decoration

    private var barcodeDecoration: some View {
        Canvas { context, size in
            var rng = ExportSeededRNG(seed: UInt64(bitPattern: Int64(data.tripName.hashValue &+ 99)))
            let barCount = 50
            let totalWidth = size.width * 0.65
            let startX = (size.width - totalWidth) / 2
            let barSpacing = totalWidth / CGFloat(barCount)

            for i in 0..<barCount {
                let barW = CGFloat.random(in: 1.5...4.5, using: &rng) * s
                let barH = CGFloat.random(in: 28...55, using: &rng) * s
                let x = startX + CGFloat(i) * barSpacing
                let rect = CGRect(
                    x: x - barW / 2,
                    y: (size.height - barH) / 2,
                    width: barW,
                    height: barH
                )
                context.fill(Path(rect), with: .color(ink.opacity(0.65)))
            }
        }
        .frame(height: 65 * s)
    }

    // MARK: - Helpers

    private func mono(_ text: String, size: CGFloat = 24, weight: Font.Weight = .regular, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: size * s, weight: weight, design: .monospaced))
            .foregroundColor(color ?? ink)
    }

    private func spacer(_ pts: CGFloat) -> some View {
        Spacer().frame(height: pts * s)
    }

    private var dashedLine: some View {
        Canvas { context, size in
            let dash: CGFloat = 8 * s
            let gap: CGFloat = 5 * s
            var x: CGFloat = 0
            while x < size.width {
                let w = min(dash, size.width - x)
                context.fill(
                    Path(CGRect(x: x, y: 0, width: w, height: 1.5 * s)),
                    with: .color(faded.opacity(0.45))
                )
                x += dash + gap
            }
        }
        .frame(height: 2 * s)
    }

    private var doubleLine: some View {
        VStack(spacing: 4 * s) {
            Rectangle().fill(faded.opacity(0.5)).frame(height: 1.5 * s)
            Rectangle().fill(faded.opacity(0.5)).frame(height: 1.5 * s)
        }
    }

    private var thermalTexture: some View {
        Canvas { context, size in
            var rng = ExportSeededRNG(seed: 777)
            var y: CGFloat = 0
            while y < size.height {
                let alpha = Double.random(in: 0...0.018, using: &rng)
                if alpha > 0.006 {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.black.opacity(alpha))
                    )
                }
                y += 2
            }
        }
        .allowsHitTesting(false)
    }

    private var receiptTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: Date())
    }
}
