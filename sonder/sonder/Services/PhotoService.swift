//
//  PhotoService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import UIKit
import Supabase
import os

/// Service for handling photo compression and upload to Supabase Storage
@Observable
@MainActor
final class PhotoService {
    private let logger = Logger(subsystem: "com.sonder.app", category: "PhotoService")
    private let storageBucket = "photos"
    private let maxRetries = 3
    private let maxDimension: CGFloat = 1200
    private let compressionQuality: CGFloat = 0.8

    /// Single-upload state (used by uploadPhoto for cover photos / avatars)
    var isUploading = false
    var uploadProgress: Double = 0
    var error: PhotoError?

    // MARK: - Batch Upload Tracking

    struct PhotoUploadBatch {
        let logID: String
        let totalCount: Int
        var completedCount: Int = 0
        var results: [String: String] = [:]    // placeholderID -> uploaded URL
        var failedIDs: Set<String> = []
    }

    var activeBatches: [String: PhotoUploadBatch] = [:]

    /// Whether any background photo uploads are in progress.
    var hasActiveUploads: Bool { !activeBatches.isEmpty }

    /// Overall progress across all active batches (0.0 – 1.0).
    var overallProgress: Double {
        let total = activeBatches.values.reduce(0) { $0 + $1.totalCount }
        guard total > 0 else { return 0 }
        let completed = activeBatches.values.reduce(0) { $0 + $1.completedCount }
        return Double(completed) / Double(total)
    }

    /// Total number of photos still pending upload across all batches.
    var totalPendingPhotos: Int {
        activeBatches.values.reduce(0) { $0 + ($1.totalCount - $1.completedCount) }
    }

    /// Total number of photos being uploaded (across all batches).
    var totalPhotosInFlight: Int {
        activeBatches.values.reduce(0) { $0 + $1.totalCount }
    }

    enum PhotoError: LocalizedError {
        case compressionFailed
        case uploadFailed(Error)
        case networkError
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .compressionFailed:
                return "Failed to compress image."
            case .uploadFailed(let error):
                return "Upload failed: \(error.localizedDescription)"
            case .networkError:
                return "Network error. Photo will upload when online."
            case .invalidImage:
                return "Invalid image format."
            }
        }
    }

    // MARK: - Public API (Single Upload)

    /// Upload a photo for a user (used for cover photos, avatars)
    func uploadPhoto(_ image: UIImage, for userId: String) async -> String? {
        isUploading = true
        error = nil
        uploadProgress = 0

        defer {
            isUploading = false
            uploadProgress = 0
        }

        guard let compressedData = compressImage(image) else {
            error = .compressionFailed
            return nil
        }

        uploadProgress = 0.3

        let filename = "\(userId)/\(UUID().uuidString).jpg"

        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let result = try await SupabaseConfig.client.storage
                    .from(storageBucket)
                    .upload(
                        filename,
                        data: compressedData,
                        options: FileOptions(contentType: "image/jpeg")
                    )

                uploadProgress = 1.0

                let publicURL = try SupabaseConfig.client.storage
                    .from(storageBucket)
                    .getPublicURL(path: result.path)

                return publicURL.absoluteString
            } catch {
                lastError = error
                logger.warning("Upload attempt \(attempt) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    try? await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
        }

        self.error = .uploadFailed(lastError ?? NSError(domain: "PhotoService", code: -1))
        return nil
    }

    /// Upload multiple photos sequentially with progress tracking
    /// (kept for cover photo / avatar use cases)
    func uploadPhotos(
        _ images: [UIImage],
        for userId: String,
        onProgress: @escaping (Int, Int) -> Void
    ) async -> [String] {
        var urls: [String] = []
        for (index, image) in images.enumerated() {
            onProgress(index + 1, images.count)
            if let url = await uploadPhoto(image, for: userId) {
                urls.append(url)
            }
        }
        return urls
    }

    // MARK: - Batch Upload API

    /// Queue images for background upload, returning placeholder strings immediately.
    ///
    /// - Parameters:
    ///   - images: The images to upload.
    ///   - userId: User ID for storage path.
    ///   - logID: The log these photos belong to.
    ///   - onComplete: Called on MainActor when the batch finishes with a mapping
    ///     of placeholder ID -> uploaded URL (failed uploads are omitted).
    /// - Returns: Array of `"pending-upload:<uuid>"` placeholder strings.
    func queueBatchUpload(
        images: [UIImage],
        for userId: String,
        logID: String,
        onComplete: @escaping @MainActor ([String: String]) -> Void
    ) -> [String] {
        // Compress images synchronously (fast, ~50ms each)
        var entries: [(placeholderID: String, data: Data)] = []
        for image in images {
            let placeholderID = UUID().uuidString.lowercased()
            guard let data = compressImage(image) else { continue }
            entries.append((placeholderID: placeholderID, data: data))
        }

        let placeholders = entries.map { "pending-upload:\($0.placeholderID)" }

        // Create batch tracker
        activeBatches[logID] = PhotoUploadBatch(
            logID: logID,
            totalCount: entries.count
        )

        // Fire off background uploads
        Task {
            for entry in entries {
                let url = await uploadCompressedData(entry.data, for: userId)

                if let url {
                    activeBatches[logID]?.results[entry.placeholderID] = url
                } else {
                    activeBatches[logID]?.failedIDs.insert(entry.placeholderID)
                }
                activeBatches[logID]?.completedCount += 1
            }

            // Batch done — deliver results and clean up
            let results = activeBatches[logID]?.results ?? [:]
            activeBatches.removeValue(forKey: logID)
            onComplete(results)
        }

        return placeholders
    }

    // MARK: - Internal Upload

    /// Upload pre-compressed JPEG data (does NOT mutate single-upload state).
    private func uploadCompressedData(_ data: Data, for userId: String) async -> String? {
        let filename = "\(userId)/\(UUID().uuidString).jpg"

        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let result = try await SupabaseConfig.client.storage
                    .from(storageBucket)
                    .upload(
                        filename,
                        data: data,
                        options: FileOptions(contentType: "image/jpeg")
                    )

                let publicURL = try SupabaseConfig.client.storage
                    .from(storageBucket)
                    .getPublicURL(path: result.path)

                return publicURL.absoluteString
            } catch {
                lastError = error
                logger.warning("Upload attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < maxRetries {
                    try? await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
        }

        logger.error("Photo upload failed after \(self.maxRetries) retries: \(lastError?.localizedDescription ?? "unknown")")
        return nil
    }

    // MARK: - Image Compression

    /// Compress and resize an image
    private func compressImage(_ image: UIImage) -> Data? {
        let originalSize = image.size
        var newSize = originalSize

        if originalSize.width > maxDimension || originalSize.height > maxDimension {
            let widthRatio = maxDimension / originalSize.width
            let heightRatio = maxDimension / originalSize.height
            let ratio = min(widthRatio, heightRatio)

            newSize = CGSize(
                width: originalSize.width * ratio,
                height: originalSize.height * ratio
            )
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }

    /// Compress image to fit within a maximum file size
    func compressImage(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        var quality = compressionQuality
        var data = compressImage(image)

        // Create resized image for retries (first call already resized)
        let resizedImage: UIImage? = data.flatMap { UIImage(data: $0) }

        while let currentData = data,
              currentData.count > maxSizeBytes && quality > 0.1 {
            quality -= 0.1
            data = (resizedImage ?? image).jpegData(compressionQuality: quality)
        }

        return data
    }
}
