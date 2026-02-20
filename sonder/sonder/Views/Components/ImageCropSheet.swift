//
//  ImageCropSheet.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import SwiftUI
import UIKit

/// Fullscreen Move & Scale crop view using a native UIScrollView for proper
/// pinch-to-zoom anchoring. The image fills a square crop frame at minimum zoom;
/// the user can zoom in further and pan, then tap Done to get a cropped UIImage.
struct ImageCropSheet: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    private let cropSize: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            ZStack {
                Color.black

                // Native UIScrollView-based zoomable image
                CropScrollView(image: image, cropSize: cropSize, viewSize: viewSize)

                // Semi-transparent overlay with clear square hole
                CropOverlayView(cropSize: cropSize, viewSize: viewSize)
                    .allowsHitTesting(false)

                // Controls
                VStack {
                    HStack {
                        Button("Cancel") { onCancel() }
                            .foregroundStyle(.white)
                            .font(.system(size: 17))

                        Spacer()

                        Text("Move and Scale")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)

                        Spacer()

                        Text("Cancel").opacity(0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, safeTop + 12)

                    Spacer()

                    Button {
                        // Find the scroll view and extract the crop
                        NotificationCenter.default.post(
                            name: .cropRequested,
                            object: nil
                        )
                    } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(SonderColors.terracotta)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, safeBottom + 20)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onReceive(NotificationCenter.default.publisher(for: .cropCompleted)) { notification in
            if let cropped = notification.object as? UIImage {
                onDone(cropped)
            }
        }
    }
}

// MARK: - Crop Overlay

private struct CropOverlayView: View {
    let cropSize: CGFloat
    let viewSize: CGSize

    var body: some View {
        let centerX = viewSize.width / 2
        let centerY = viewSize.height / 2
        let half = cropSize / 2

        Canvas { context, size in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRoundedRect(
                in: CGRect(x: centerX - half, y: centerY - half, width: cropSize, height: cropSize),
                cornerSize: CGSize(width: 4, height: 4)
            )
            context.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))

            let borderRect = CGRect(x: centerX - half, y: centerY - half, width: cropSize, height: cropSize)
            context.stroke(
                Path(roundedRect: borderRect, cornerRadius: 4),
                with: .color(.white.opacity(0.6)),
                lineWidth: 1
            )
        }
    }
}

// MARK: - UIScrollView-based Crop View

private struct CropScrollView: UIViewRepresentable {
    let image: UIImage
    let cropSize: CGFloat
    let viewSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image, cropSize: cropSize)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        // Set up the scroll view frame and zoom after layout
        DispatchQueue.main.async {
            configureScrollView(scrollView, imageView: imageView, coordinator: context.coordinator)
        }

        // Listen for crop request
        context.coordinator.cropObserver = NotificationCenter.default.addObserver(
            forName: .cropRequested,
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.performCrop()
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    private func configureScrollView(_ scrollView: UIScrollView, imageView: UIImageView, coordinator: Coordinator) {
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return }

        // The scroll view's frame = the crop square, centered in the view
        let cropOriginX = (viewSize.width - cropSize) / 2
        let cropOriginY = (viewSize.height - cropSize) / 2
        scrollView.frame = CGRect(x: cropOriginX, y: cropOriginY, width: cropSize, height: cropSize)

        // Allow scrolling beyond the crop frame so the image can pan fully
        scrollView.clipsToBounds = false

        // Image view size = natural image size (we'll use zoom to scale it)
        imageView.frame = CGRect(x: 0, y: 0, width: imgW, height: imgH)
        scrollView.contentSize = CGSize(width: imgW, height: imgH)

        // Calculate minimum zoom so the image fills the crop square
        let scaleW = cropSize / imgW
        let scaleH = cropSize / imgH
        let minZoom = max(scaleW, scaleH)

        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = minZoom * 5
        scrollView.zoomScale = minZoom

        // Center the image
        coordinator.centerContent(in: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let sourceImage: UIImage
        let cropSize: CGFloat
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var cropObserver: Any?

        init(image: UIImage, cropSize: CGFloat) {
            self.sourceImage = image
            self.cropSize = cropSize
        }

        deinit {
            if let observer = cropObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        func centerContent(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let contentW = scrollView.contentSize.width
            let contentH = scrollView.contentSize.height
            let boundsW = scrollView.bounds.width
            let boundsH = scrollView.bounds.height

            let offsetX = max(0, (boundsW - contentW) / 2)
            let offsetY = max(0, (boundsH - contentH) / 2)

            imageView.frame.origin = CGPoint(x: offsetX, y: offsetY)
        }

        func performCrop() {
            guard let scrollView,
                  let cgImage = sourceImage.cgImage else { return }

            let zoomScale = scrollView.zoomScale
            let offset = scrollView.contentOffset

            // The visible rect in content coordinates = the crop square
            let visibleRect = CGRect(
                x: offset.x / zoomScale,
                y: offset.y / zoomScale,
                width: cropSize / zoomScale,
                height: cropSize / zoomScale
            )

            // Convert from image-view coordinates to source pixel coordinates
            let imgW = sourceImage.size.width
            let imgH = sourceImage.size.height
            guard imgW > 0, imgH > 0 else { return }

            let pixelRect = CGRect(
                x: visibleRect.origin.x * CGFloat(cgImage.width) / imgW,
                y: visibleRect.origin.y * CGFloat(cgImage.height) / imgH,
                width: visibleRect.width * CGFloat(cgImage.width) / imgW,
                height: visibleRect.height * CGFloat(cgImage.height) / imgH
            )

            let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
            let clampedRect = pixelRect.intersection(bounds)

            guard !clampedRect.isNull,
                  clampedRect.width > 0, clampedRect.height > 0,
                  let cropped = cgImage.cropping(to: clampedRect) else {
                NotificationCenter.default.post(name: .cropCompleted, object: sourceImage)
                return
            }

            let result = UIImage(cgImage: cropped, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)
            NotificationCenter.default.post(name: .cropCompleted, object: result)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    fileprivate static let cropRequested = Notification.Name("ImageCropSheet.cropRequested")
    fileprivate static let cropCompleted = Notification.Name("ImageCropSheet.cropCompleted")
}
