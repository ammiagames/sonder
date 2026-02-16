//
//  DownsampledAsyncImage.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI
import UIKit

/// Loads a remote image and downsamples it to the target display size on decode,
/// using a fraction of the memory compared to `AsyncImage`.
///
/// A 1000x1000 avatar displayed at 24pt uses ~4MB with AsyncImage but only ~2KB
/// when downsampled. Shared `NSCache` with a 30MB cap handles eviction.
struct DownsampledAsyncImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false
    @State private var shimmerPhase: CGFloat = -1

    init(
        url: URL?,
        targetSize: CGSize,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
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
        if let cached = ImageDownsampler.cache.object(forKey: cacheKey) {
            self.image = cached
            return
        }

        // Download and downsample
        do {
            let (data, _) = try await ImageDownsampler.session.data(from: url)
            let scale = UIScreen.main.scale
            let pixelSize = CGSize(
                width: targetSize.width * scale,
                height: targetSize.height * scale
            )

            if let downsampled = ImageDownsampler.downsample(data: data, to: pixelSize) {
                ImageDownsampler.cache.setObject(downsampled, forKey: cacheKey)
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
    init(url: URL?, targetSize: CGSize, contentMode: ContentMode = .fill) {
        self.init(url: url, targetSize: targetSize, contentMode: contentMode) {
            Color.clear
        }
    }
}

// MARK: - Image Downsampler

enum ImageDownsampler {
    /// Shared cache capped at 30MB
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 30 * 1024 * 1024 // 30MB
        return cache
    }()

    /// Builds a cache key that includes the target pixel dimensions so the same
    /// URL rendered at different display sizes gets independent cache entries.
    static func cacheKey(for url: URL, pointSize: CGSize) -> NSString {
        let scale = UIScreen.main.scale
        let pw = Int(pointSize.width * scale)
        let ph = Int(pointSize.height * scale)
        return NSString(string: "\(url.absoluteString)#\(pw)x\(ph)")
    }

    /// URLSession with disk cache for raw responses. The NSCache above stores tiny
    /// downsampled bitmaps in memory; this URLCache persists the original JPEG data
    /// on disk so subsequent launches don't re-download from the network.
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        let diskCache = URLCache(
            memoryCapacity: 0,             // skip memory tier (NSCache handles that)
            diskCapacity: 150 * 1024 * 1024 // 150MB disk
        )
        config.urlCache = diskCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// Downloads an image from a URL and downsamples it to the target point size.
    /// Uses the shared disk-cached session so previously-viewed photos are instant.
    /// Intended for export rendering where a synchronous UIImage is needed.
    static func downloadImage(from url: URL, targetSize: CGSize) async -> UIImage? {
        do {
            let (data, _) = try await session.data(from: url)
            let pixelSize = CGSize(width: targetSize.width * 2, height: targetSize.height * 2)
            return downsample(data: data, to: pixelSize)
        } catch {
            return nil
        }
    }

    /// Downsamples image data to the target pixel size using ImageIO.
    /// This decodes directly at the target size, never allocating the full image.
    static func downsample(data: Data, to maxPixelSize: CGSize) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
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
