//
//  FullscreenPhotoViewer.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import SwiftUI

/// Fullscreen photo gallery with pinch-to-zoom, swipe between photos, and drag-to-dismiss.
struct FullscreenPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss

    let photoURLs: [String]
    let initialIndex: Int

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var backgroundOpacity: Double = 1

    init(photoURLs: [String], initialIndex: Int = 0) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, urlString in
                    // Only build zoomable pages for current and adjacent photos
                    if abs(index - currentIndex) <= 1 {
                        ZoomablePhotoPage(urlString: urlString, onDismissDrag: handleDrag, onDismissEnd: handleDragEnd)
                            .tag(index)
                    } else {
                        Color.black
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .clipped()

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }

            // Page counter
            if photoURLs.count > 1 {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(photoURLs.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.bottom, 50)
                }
            }
        }
        .statusBarHidden()
    }

    private func handleDrag(_ translation: CGFloat) {
        dragOffset = translation
        let progress = abs(translation) / CGFloat(300)
        backgroundOpacity = max(0.3, 1.0 - progress)
    }

    private func handleDragEnd(_ translation: CGFloat) {
        if abs(translation) > 100 {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
                backgroundOpacity = 1
            }
        }
    }
}

// MARK: - Zoomable Photo Page

private struct ZoomablePhotoPage: View {
    let urlString: String
    let onDismissDrag: (CGFloat) -> Void
    let onDismissEnd: (CGFloat) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            Group {
                if let url = URL(string: urlString) {
                    DownsampledAsyncImage(
                        url: url,
                        targetSize: CGSize(width: size.width * 2, height: size.height * 2),
                        contentMode: .fit,
                        cacheMode: .cached
                    ) {
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(offset)
            .clipped()
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = lastScale * value.magnification
                        scale = min(max(newScale, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if scale < 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                        lastScale = scale
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.01 {
                            // Pan when zoomed
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        } else {
                            // Drag-to-dismiss when at 1x
                            onDismissDrag(value.translation.height)
                        }
                    }
                    .onEnded { value in
                        if scale > 1.01 {
                            lastOffset = offset
                        } else {
                            onDismissEnd(value.translation.height)
                        }
                    }
            )
            .onTapGesture(count: 2) { location in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if scale > 1.01 {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 3.0
                        lastScale = 3.0
                        // Center zoom on tap point
                        let centerX = size.width / 2
                        let centerY = size.height / 2
                        let tapOffsetX = (centerX - location.x) * 2
                        let tapOffsetY = (centerY - location.y) * 2
                        offset = CGSize(width: tapOffsetX, height: tapOffsetY)
                        lastOffset = offset
                    }
                }
            }
        }
    }
}
