//
//  TagInputView.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Tag input component with suggestions and freeform entry
struct TagInputView: View {
    @Binding var selectedTags: [String]
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private let suggestedTags = [
        "food", "coffee", "bar", "restaurant",
        "hike", "viewpoint", "museum", "beach",
        "hotel", "shopping"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            // Selected tags
            if !selectedTags.isEmpty {
                FlowLayout(spacing: SonderSpacing.xs) {
                    ForEach(selectedTags, id: \.self) { tag in
                        TagChip(tag: tag, isSelected: true) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedTags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }

            // Input field
            HStack {
                TextField("Add a tag...", text: $inputText)
                    .font(SonderTypography.body)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isInputFocused)
                    .onSubmit {
                        addCustomTag()
                    }

                if !inputText.isEmpty {
                    Button(action: addCustomTag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(SonderColors.terracotta)
                    }
                }
            }
            .padding(SonderSpacing.sm)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

            // Suggested tags
            if selectedTags.count < 5 {
                VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                    Text("Suggestions")
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)

                    FlowLayout(spacing: SonderSpacing.xs) {
                        ForEach(availableSuggestions, id: \.self) { tag in
                            TagChip(tag: tag, isSelected: false) {
                                addTag(tag)
                            }
                        }
                    }
                }
            }
        }
    }

    private var availableSuggestions: [String] {
        suggestedTags.filter { !selectedTags.contains($0) }
    }

    private func addCustomTag() {
        var tag = inputText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }

        // Remove # if user typed it
        if tag.hasPrefix("#") {
            tag = String(tag.dropFirst())
        }

        addTag(tag)
        inputText = ""
    }

    private func addTag(_ tag: String) {
        guard !selectedTags.contains(tag) && selectedTags.count < 10 else { return }

        withAnimation(.spring(response: 0.3)) {
            selectedTags.append(tag)
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

/// Individual tag chip component
struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SonderSpacing.xxs) {
                Text(tag)
                    .font(SonderTypography.caption)

                if isSelected {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xxs)
            .background(isSelected ? SonderColors.terracotta : SonderColors.warmGray)
            .foregroundStyle(isSelected ? .white : SonderColors.inkDark)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Flow layout for tags that wraps to next line
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let maxX = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxX && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX)
        }

        return (
            CGSize(width: maxWidth, height: currentY + lineHeight),
            positions
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var tags: [String] = ["food", "coffee"]

        var body: some View {
            TagInputView(selectedTags: $tags)
                .padding()
        }
    }

    return PreviewWrapper()
}
