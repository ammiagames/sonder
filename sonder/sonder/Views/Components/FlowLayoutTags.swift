//
//  FlowLayoutTags.swift
//  sonder
//

import SwiftUI

// MARK: - Flow Layout for Tags

struct FlowLayoutTags: View {
    let tags: [String]

    var body: some View {
        FlowLayoutWrapper {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(SonderTypography.caption)
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xxs)
                    .background(SonderColors.terracotta.opacity(0.1))
                    .foregroundStyle(SonderColors.terracotta)
                    .clipShape(Capsule())
            }
        }
    }
}

struct FlowLayoutWrapper: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x,
                           y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    private func flowLayout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Photo Placeholder

struct PhotoPlaceholderView: View {
    let icon: String
    let prompt: String

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.15), SonderColors.ochre.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: SonderSpacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .ultraLight))

                    Text(prompt)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .italic()
                }
                .foregroundStyle(SonderColors.terracotta.opacity(0.45))
            }
    }
}
