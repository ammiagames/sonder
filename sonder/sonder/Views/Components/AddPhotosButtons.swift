//
//  AddPhotosButtons.swift
//  sonder
//
//  Shared photo picker label views used in log creation and edit flows.
//

import SwiftUI
import PhotosUI

/// Full-width empty state button for adding photos — dashed border + "Add Photos" text.
/// Wrap in a `PhotosPicker` at the call site.
struct AddPhotosEmptyState: View {
    var height: CGFloat = 80

    var body: some View {
        HStack(spacing: SonderSpacing.xs) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
            Text("Add Photos")
                .font(SonderTypography.body)
                .fontWeight(.medium)
        }
        .foregroundStyle(SonderColors.terracotta)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        .dashedBorder(color: SonderColors.terracotta.opacity(0.3), dash: [6])
    }
}

/// Compact plus button for adding more photos at the end of a thumbnail strip.
/// Wrap in a `PhotosPicker` at the call site.
struct AddMorePhotosButton: View {
    var size: CGFloat = 80

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SonderColors.inkMuted)
        }
        .frame(width: size, height: size)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
        .dashedBorder(color: SonderColors.inkLight.opacity(0.3), cornerRadius: SonderSpacing.radiusSm, dash: [4])
    }
}
