//
//  PlacePhotoView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI

/// Displays a place photo from Google Places API with caching
struct PlacePhotoView: View {
    let photoReference: String?
    var size: CGFloat = 60
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let photoReference = photoReference,
               let url = GooglePlacesService.photoURL(for: photoReference, maxWidth: Int(size * 2)) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(
                SonderColors.placeholderGradient
            )
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(SonderColors.terracotta.opacity(0.5))
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        PlacePhotoView(photoReference: nil)
        PlacePhotoView(photoReference: "test", size: 100)
    }
}
