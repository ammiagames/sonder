//
//  PhotoService.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import UIKit
import Supabase

/// Service for handling photo compression and upload to Supabase Storage
@Observable
@MainActor
final class PhotoService {
    private let storageBucket = "photos"
    private let maxRetries = 3
    private let maxDimension: CGFloat = 1200
    private let compressionQuality: CGFloat = 0.8

    var isUploading = false
    var uploadProgress: Double = 0
    var error: PhotoError?

    /// Queue of pending photo uploads (stores compressed JPEG Data, not UIImage)
    private var uploadQueue: [(id: String, data: Data, userId: String)] = []
    private var isProcessingQueue = false

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

    // MARK: - Public API

    /// Upload a photo for a user
    /// - Parameters:
    ///   - image: The UIImage to upload
    ///   - userId: The user's ID for organizing photos
    /// - Returns: The public URL of the uploaded photo, or nil if failed
    func uploadPhoto(_ image: UIImage, for userId: String) async -> String? {
        isUploading = true
        error = nil
        uploadProgress = 0

        defer {
            isUploading = false
            uploadProgress = 0
        }

        // Compress image
        guard let compressedData = compressImage(image) else {
            error = .compressionFailed
            return nil
        }

        uploadProgress = 0.3

        // Generate unique filename
        let filename = "\(userId)/\(UUID().uuidString).jpg"

        // Upload with retries
        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let result = try await SupabaseConfig.client.storage
                    .from(storageBucket)
                    .upload(
                        path: filename,
                        file: compressedData,
                        options: FileOptions(contentType: "image/jpeg")
                    )

                uploadProgress = 1.0

                // Get public URL
                let publicURL = try SupabaseConfig.client.storage
                    .from(storageBucket)
                    .getPublicURL(path: result.path)

                return publicURL.absoluteString
            } catch {
                lastError = error
                print("Upload attempt \(attempt) failed: \(error)")

                if attempt < maxRetries {
                    // Wait before retry
                    try? await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
        }

        self.error = .uploadFailed(lastError ?? NSError(domain: "PhotoService", code: -1))
        return nil
    }

    /// Queue a photo for upload (for offline support)
    /// Compresses immediately so we store ~100KB of Data instead of ~5MB UIImage
    func queuePhotoUpload(image: UIImage, for userId: String) -> String {
        let id = UUID().uuidString
        guard let data = compressImage(image) else {
            error = .compressionFailed
            return id
        }
        uploadQueue.append((id: id, data: data, userId: userId))
        processQueue()
        return id
    }

    /// Process queued uploads
    func processQueue() {
        guard !isProcessingQueue && !uploadQueue.isEmpty else { return }

        isProcessingQueue = true

        Task {
            while !uploadQueue.isEmpty {
                let item = uploadQueue.removeFirst()
                _ = await uploadCompressedData(item.data, for: item.userId)
            }
            isProcessingQueue = false
        }
    }

    /// Upload pre-compressed JPEG data (used by the queue)
    private func uploadCompressedData(_ data: Data, for userId: String) async -> String? {
        isUploading = true
        error = nil
        uploadProgress = 0.3

        defer {
            isUploading = false
            uploadProgress = 0
        }

        let filename = "\(userId)/\(UUID().uuidString).jpg"

        var lastError: Error?
        for attempt in 1...maxRetries {
            do {
                let result = try await SupabaseConfig.client.storage
                    .from(storageBucket)
                    .upload(
                        path: filename,
                        file: data,
                        options: FileOptions(contentType: "image/jpeg")
                    )

                uploadProgress = 1.0

                let publicURL = try SupabaseConfig.client.storage
                    .from(storageBucket)
                    .getPublicURL(path: result.path)

                return publicURL.absoluteString
            } catch {
                lastError = error
                print("Upload attempt \(attempt) failed: \(error)")
                if attempt < maxRetries {
                    try? await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
        }

        self.error = .uploadFailed(lastError ?? NSError(domain: "PhotoService", code: -1))
        return nil
    }

    /// Get the number of pending uploads
    var pendingUploadCount: Int {
        uploadQueue.count
    }

    // MARK: - Image Compression

    /// Compress and resize an image
    /// - Parameter image: The original UIImage
    /// - Returns: JPEG data of the compressed image
    private func compressImage(_ image: UIImage) -> Data? {
        // Calculate new size maintaining aspect ratio
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

        // Resize image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // Compress to JPEG
        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }

    /// Compress image to fit within a maximum file size
    /// - Parameters:
    ///   - image: The original UIImage
    ///   - maxSizeBytes: Maximum file size in bytes
    /// - Returns: JPEG data within the size limit
    func compressImage(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        var quality = compressionQuality
        var data = compressImage(image)

        while let currentData = data,
              currentData.count > maxSizeBytes && quality > 0.1 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
        }

        return data
    }
}
