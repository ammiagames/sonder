//
//  ImageCropSheet.swift
//  sonder
//
//  Created by Michael Song on 2/19/26.
//

import SwiftUI
import UIKit

/// Saved zoom/offset so a re-crop starts where the user left off.
struct CropState: Codable {
    let zoomScale: CGFloat
    let contentOffset: CGPoint
}

/// Fullscreen "Move and Scale" crop sheet backed by a pure-UIKit view controller.
/// Matches the native iOS crop UX from UIImagePickerController(allowsEditing: true).
struct ImageCropSheet: UIViewControllerRepresentable {
    let image: UIImage
    let initialCropState: CropState?
    let onDone: (UIImage, CropState) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CropViewController {
        CropViewController(image: image, initialCropState: initialCropState, onDone: onDone, onCancel: onCancel)
    }

    func updateUIViewController(_ vc: CropViewController, context: Context) {}
}

// MARK: - ScrollViewContainer

/// Forwards all touches to the scroll view so panning/zooming works from
/// outside the crop rect (i.e. from the dimmed overlay area).
private class ScrollViewContainer: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let scrollView = subviews.first else { return super.hitTest(point, with: event) }
        let converted = convert(point, to: scrollView)
        return scrollView.hitTest(converted, with: event) ?? super.hitTest(point, with: event)
    }
}

// MARK: - CropViewController

/// Pure UIKit crop controller with UIScrollView for native pinch/pan behavior.
final class CropViewController: UIViewController, UIScrollViewDelegate {
    private let sourceImage: UIImage
    private let initialCropState: CropState?
    private let onDone: (UIImage, CropState) -> Void
    private let onCancel: () -> Void

    private let scrollViewContainer = ScrollViewContainer()
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let borderView = UIView()
    private let dimmingView = UIView()

    private var cropRect: CGRect = .zero
    private var hasConfigured = false

    init(image: UIImage, initialCropState: CropState?, onDone: @escaping (UIImage, CropState) -> Void, onCancel: @escaping () -> Void) {
        self.sourceImage = image
        self.initialCropState = initialCropState
        self.onDone = onDone
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        setupScrollView()
        setupDimming()
        setupBorder()
        setupControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasConfigured else { return }
        hasConfigured = true
        configureCrop()
    }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true
        scrollView.clipsToBounds = false
        scrollView.backgroundColor = .clear
        scrollView.decelerationRate = .normal

        imageView.image = sourceImage
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)

        scrollViewContainer.backgroundColor = .clear
        scrollViewContainer.addSubview(scrollView)
        view.addSubview(scrollViewContainer)

        // Double-tap to toggle between min and max zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    private func setupDimming() {
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        dimmingView.isUserInteractionEnabled = false
        view.addSubview(dimmingView)
    }

    private func setupBorder() {
        borderView.backgroundColor = .clear
        borderView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        borderView.layer.borderWidth = 0.5
        borderView.layer.cornerRadius = 2
        borderView.isUserInteractionEnabled = false
        view.addSubview(borderView)
    }

    private func setupControls() {
        let titleLabel = UILabel()
        titleLabel.text = "Move and Scale"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.setTitleColor(.white.withAlphaComponent(0.85), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("Choose", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = UIColor(SonderColors.terracotta)
        doneButton.layer.cornerRadius = 22
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 36, bottom: 12, right: 36)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Configure crop geometry

    private func configureCrop() {
        let viewW = view.bounds.width
        let viewH = view.bounds.height
        let safeTop = view.safeAreaInsets.top
        let safeBottom = view.safeAreaInsets.bottom

        // Header and footer heights for controls
        let headerH = safeTop + 52
        let footerH = safeBottom + 72

        // Crop square: full width, vertically centered in the remaining space
        let cropSize = viewW
        let availableH = viewH - headerH - footerH
        let cropY = headerH + max(0, (availableH - cropSize) / 2)

        cropRect = CGRect(x: 0, y: cropY, width: cropSize, height: cropSize)

        // Container fills the screen; scroll view sits at crop rect inside it
        scrollViewContainer.frame = view.bounds
        scrollView.frame = cropRect

        // Dimming overlay: full screen with transparent cutout at crop rect
        dimmingView.frame = view.bounds
        let path = UIBezierPath(rect: dimmingView.bounds)
        path.append(UIBezierPath(roundedRect: cropRect, cornerRadius: 2).reversing())
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        dimmingView.layer.mask = mask

        // Border sits on the crop edge
        borderView.frame = cropRect

        // Size image view to natural image dimensions (zoom handles scaling)
        let imgW = sourceImage.size.width
        let imgH = sourceImage.size.height
        guard imgW > 0, imgH > 0 else { return }

        imageView.frame = CGRect(x: 0, y: 0, width: imgW, height: imgH)
        scrollView.contentSize = CGSize(width: imgW, height: imgH)

        // Min zoom: image fills the crop square (no gaps)
        let scaleW = cropSize / imgW
        let scaleH = cropSize / imgH
        let minZoom = max(scaleW, scaleH)

        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = max(minZoom * 5, 1.0)

        // Restore previous crop position or default to min zoom centered
        if let state = initialCropState {
            let clampedZoom = max(state.zoomScale, minZoom)
            scrollView.zoomScale = clampedZoom
            centerContent()
            // Defer offset restore to next runloop so layout settles first
            DispatchQueue.main.async { [weak self] in
                self?.scrollView.contentOffset = state.contentOffset
            }
        } else {
            scrollView.zoomScale = minZoom
            centerContent()
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

    private func centerContent() {
        let contentW = scrollView.contentSize.width
        let contentH = scrollView.contentSize.height
        let boundsW = scrollView.bounds.width
        let boundsH = scrollView.bounds.height

        let offsetX = max(0, (boundsW - contentW) / 2)
        let offsetY = max(0, (boundsH - contentH) / 2)
        imageView.frame.origin = CGPoint(x: offsetX, y: offsetY)
    }

    // MARK: - Double tap

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let newZoom = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
            let size = CGSize(
                width: scrollView.bounds.width / newZoom,
                height: scrollView.bounds.height / newZoom
            )
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onCancel()
    }

    @objc private func doneTapped() {
        let state = CropState(zoomScale: scrollView.zoomScale, contentOffset: scrollView.contentOffset)
        let cropped = performCrop()
        onDone(cropped, state)
    }

    private func performCrop() -> UIImage {
        guard let cgImage = sourceImage.cgImage else { return sourceImage }

        let zoomScale = scrollView.zoomScale
        let offset = scrollView.contentOffset
        let cropSize = cropRect.width

        // Visible rect in content (image-view) coordinates
        let visibleRect = CGRect(
            x: offset.x / zoomScale,
            y: offset.y / zoomScale,
            width: cropSize / zoomScale,
            height: cropSize / zoomScale
        )

        // Convert to source pixel coordinates
        let imgW = sourceImage.size.width
        let imgH = sourceImage.size.height
        guard imgW > 0, imgH > 0 else { return sourceImage }

        let pixelRect = CGRect(
            x: visibleRect.origin.x * CGFloat(cgImage.width) / imgW,
            y: visibleRect.origin.y * CGFloat(cgImage.height) / imgH,
            width: visibleRect.width * CGFloat(cgImage.width) / imgW,
            height: visibleRect.height * CGFloat(cgImage.height) / imgH
        )

        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clampedRect = pixelRect.intersection(imageBounds)

        guard !clampedRect.isNull,
              clampedRect.width > 0, clampedRect.height > 0,
              let cropped = cgImage.cropping(to: clampedRect) else {
            return sourceImage
        }

        return UIImage(cgImage: cropped, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)
    }
}
