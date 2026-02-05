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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay {
                                ProgressView()
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
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
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        PlacePhotoView(photoReference: nil)
        PlacePhotoView(photoReference: "test", size: 100)
    }
}
