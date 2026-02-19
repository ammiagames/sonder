//
//  DownsampledAsyncImage.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI
import UIKit

// MARK: - Tab Visibility Environment

/// Environment key so parent views (e.g. MainTabView) can signal when a tab
/// is hidden. DownsampledAsyncImage uses this to nil out decoded bitmaps on
/// invisible tabs, reclaiming memory while the image stays in NSCache for
/// instant reload when the tab becomes visible again.
private struct TabVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isTabVisible: Bool {
        get { self[TabVisibleKey.self] }
        set { self[TabVisibleKey.self] = newValue }
    }
}

/// Controls whether an image load should participate in shared caches.
enum ImageCacheMode {
    /// Read/write shared memory + disk caches.
    case cached
    /// Do not read/write shared caches (use ephemeral network fetch).
    case transient
}

/// Loads a remote image and downsamples it to the target display size on decode,
/// using a fraction of the memory compared to `AsyncImage`.
///
/// A 1000x1000 avatar displayed at 24pt uses ~4MB with AsyncImage but only ~2KB
/// when downsampled. Shared `NSCache` handles memory-pressure eviction.
struct DownsampledAsyncImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    let contentMode: ContentMode
    let cacheMode: ImageCacheMode
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.isTabVisible) private var isTabVisible
    @State private var image: UIImage?
    @State private var failed = false
    @State private var shimmerPhase: CGFloat = -1
    @State private var teardownTask: Task<Void, Never>?

    init(
        url: URL?,
        targetSize: CGSize,
        contentMode: ContentMode = .fill,
        cacheMode: ImageCacheMode = .cached,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.cacheMode = cacheMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(.easeIn(duration: 0.15)))
            } else {
                placeholder()
                    .overlay {
                        if !failed {
                            shimmerOverlay
                        }
                    }
            }
        }
        .animation(.easeIn(duration: 0.15), value: image != nil)
        .task(id: url) {
            failed = false
            guard let url else { image = nil; return }
            await loadImage(from: url)
        }
        .onChange(of: isTabVisible) { _, visible in
            if !visible {
                // Tab hidden — release the decoded bitmap to free memory after
                // the tab transition completes so placeholders don't flash.
                teardownTask?.cancel()
                teardownTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    guard !Task.isCancelled, !isTabVisible else { return }
                    image = nil
                }
            } else {
                // Tab visible again — cancel any pending teardown and reload.
                teardownTask?.cancel()
                teardownTask = nil
                if image == nil, let url {
                    Task { await loadImage(from: url) }
                }
            }
        }
    }

    /// Warm gradient that slides across the placeholder while loading.
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.25), location: 0.4),
                    .init(color: Color.white.opacity(0.35), location: 0.5),
                    .init(color: Color.white.opacity(0.25), location: 0.6),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 1.5)
            .offset(x: shimmerPhase * width * 1.5)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerPhase = 1
                }
            }
        }
        .clipped()
    }

    private func loadImage(from url: URL) async {
        // Check cache first (key includes target size to avoid serving tiny thumbnails)
        let cacheKey = ImageDownsampler.cacheKey(for: url, pointSize: targetSize)
        if cacheMode == .cached, let cached = ImageDownsampler.cache.object(forKey: cacheKey) {
            self.image = cached
            return
        }

        // Download and downsample
        do {
            let session = ImageDownsampler.session(for: cacheMode)
            let (data, response) = try await session.data(from: url)

            // Skip processing if we got an error HTTP status
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                await MainActor.run { self.failed = true }
                return
            }

            let scale = UITraitCollection.current.displayScale
            let pixelSize = CGSize(
                width: targetSize.width * scale,
                height: targetSize.height * scale
            )

            if let downsampled = ImageDownsampler.downsample(data: data, to: pixelSize) {
                if cacheMode == .cached {
                    ImageDownsampler.cache.setObject(
                        downsampled,
                        forKey: cacheKey,
                        cost: ImageDownsampler.cacheCost(for: downsampled)
                    )
                }
                await MainActor.run {
                    self.image = downsampled
                }
            } else {
                await MainActor.run { self.failed = true }
            }
        } catch {
            await MainActor.run { self.failed = true }
        }
    }
}

// MARK: - Convenience init without placeholder

extension DownsampledAsyncImage where Placeholder == Color {
    init(url: URL?, targetSize: CGSize, contentMode: ContentMode = .fill, cacheMode: ImageCacheMode = .cached) {
        self.init(url: url, targetSize: targetSize, contentMode: contentMode, cacheMode: cacheMode) {
            Color.clear
        }
    }
}

// MARK: - Image Downsampler

enum ImageDownsampler {
    /// Shared in-memory bitmap cache.
    nonisolated(unsafe) static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 30 * 1024 * 1024 // 30MB
        return cache
    }()

    /// Builds a cache key that includes the target pixel dimensions so the same
    /// URL rendered at different display sizes gets independent cache entries.
    static func cacheKey(for url: URL, pointSize: CGSize) -> NSString {
        let scale = UITraitCollection.current.displayScale
        let pw = Int(pointSize.width * scale)
        let ph = Int(pointSize.height * scale)
        return NSString(string: "\(url.absoluteString)#\(pw)x\(ph)")
    }

    /// URLSession with disk cache for raw responses.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        let diskCache = URLCache(
            memoryCapacity: 0,             // skip memory tier (NSCache handles that)
            diskCapacity: 180 * 1024 * 1024 // 180MB disk
        )
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Ephemeral session used for transient image loads (e.g. one-off search previews).
    static let transientSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func session(for mode: ImageCacheMode) -> URLSession {
        mode == .cached ? session : transientSession
    }

    /// Approximate in-memory cost of a decoded UIImage in bytes.
    static func cacheCost(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(1, width * height * 4)
    }

    /// Clears both memory and disk image caches.
    static func clearCaches() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Downloads an image from a URL and downsamples it to the target point size.
    /// Uses the shared disk-cached session so previously-viewed photos are instant.
    /// Intended for export rendering where a synchronous UIImage is needed.
    static func downloadImage(
        from url: URL,
        targetSize: CGSize,
        cacheMode: ImageCacheMode = .cached
    ) async -> UIImage? {
        do {
            let cacheKey = cacheKey(for: url, pointSize: targetSize)
            if cacheMode == .cached, let cached = cache.object(forKey: cacheKey) {
                return cached
            }

            let (data, _) = try await session(for: cacheMode).data(from: url)
            let pixelSize = CGSize(width: targetSize.width * 2, height: targetSize.height * 2)
            guard let image = downsample(data: data, to: pixelSize) else {
                return nil
            }
            if cacheMode == .cached {
                cache.setObject(image, forKey: cacheKey, cost: cacheCost(for: image))
            }
            return image
        } catch {
            return nil
        }
    }

    /// Downsamples image data to the target pixel size using ImageIO.
    /// This decodes directly at the target size, never allocating the full image.
    nonisolated static func downsample(data: Data, to maxPixelSize: CGSize) -> UIImage? {
        // Reject obviously invalid data (empty, too small, or HTML error responses)
        guard data.count > 100 else { return nil }
        // Quick check: valid images start with known magic bytes, not '<' (HTML)
        if let firstByte = data.first, firstByte == 0x3C { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        // Verify the source actually contains an image before attempting thumbnail
        guard CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete else {
            return nil
        }

        let maxDimension = max(maxPixelSize.width, maxPixelSize.height)

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
