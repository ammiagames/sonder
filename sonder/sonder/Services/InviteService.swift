//
//  InviteService.swift
//  sonder
//

import Foundation
import UIKit
import Supabase
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "InviteService")

/// Uploads an invite card image and a companion HTML page (with OG meta tags) to
/// Supabase Storage. The HTML page URL is what gets sent via iMessage — its OG tags
/// point to the image, producing a rich link preview.
enum InviteService {
    private static let bucket = "photos"
    private static let storageBase = "https://qxpkyblruhyrokexihef.supabase.co/storage/v1/object/public/photos"

    /// Uploads the invite card image + an HTML page with OG tags, returns the HTML page's public URL.
    /// Returns `nil` on failure — callers fall back to a plain App Store URL.
    static func uploadAndBuildInviteURL(image: UIImage, userID: String) async -> URL? {
        guard let imageData = image.jpegData(compressionQuality: 0.82) else {
            logger.error("Failed to compress invite card image to JPEG")
            return nil
        }
        logger.info("Invite card JPEG size: \(imageData.count) bytes")

        let id = UUID().uuidString
        let imagePath = "invites/\(userID)/\(id).jpg"
        let htmlPath = "invites/\(userID)/\(id).html"

        do {
            // 1. Upload the image
            try await SupabaseConfig.client.storage
                .from(bucket)
                .upload(imagePath, data: imageData, options: FileOptions(contentType: "image/jpeg"))
            logger.info("Uploaded invite image to: \(imagePath)")

            let imageURL = "\(storageBase)/\(imagePath)"

            // 2. Build and upload the HTML page with OG tags
            let html = buildHTML(imageURL: imageURL, pageURL: "\(storageBase)/\(htmlPath)")
            guard let htmlData = html.data(using: .utf8) else { return nil }

            try await SupabaseConfig.client.storage
                .from(bucket)
                .upload(htmlPath, data: htmlData, options: FileOptions(contentType: "text/html"))
            logger.info("Uploaded invite HTML to: \(htmlPath)")

            let pageURL = URL(string: "\(storageBase)/\(htmlPath)")
            logger.info("Invite URL: \(pageURL?.absoluteString ?? "nil")")
            return pageURL
        } catch {
            logger.error("Invite upload failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func buildHTML(imageURL: String, pageURL: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en"><head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>You're invited to Sonder</title>
        <meta property="og:title" content="You're invited to Sonder" />
        <meta property="og:description" content="Track and share your favorite places with friends" />
        <meta property="og:type" content="website" />
        <meta property="og:url" content="\(pageURL)" />
        <meta property="og:image" content="\(imageURL)" />
        <meta property="og:image:type" content="image/jpeg" />
        <meta property="og:image:width" content="1080" />
        <meta property="og:image:height" content="1350" />
        <meta name="twitter:card" content="summary_large_image" />
        </head><body>
        <h1>You're invited to Sonder</h1>
        <p>Track and share your favorite places with friends.</p>
        <a href="https://apps.apple.com/app/sonder">Download Sonder</a>
        <script>window.location.replace("https://apps.apple.com/app/sonder");</script>
        </body></html>
        """
    }
}
