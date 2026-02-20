//
//  InviteCardRenderer.swift
//  sonder
//

import SwiftUI
import SwiftData

/// Generates an invite card image with the user's recent log photos embedded in the polaroid frames.
@MainActor
enum InviteCardRenderer {

    /// Loads up to 3 recent log photos and renders the invite card.
    /// Falls back to gradient placeholders if no photos are available.
    static func render(
        user: User?,
        logs: [Log]
    ) async -> UIImage? {
        let userID = user?.id
        let inviterName = user?.firstName ?? user?.username ?? "A friend"
        let inviterUsername = user?.username ?? "sonder"

        // Load photos from recent logs
        var photos: [UIImage] = []
        if let userID {
            let logsWithPhotos = logs
                .filter { $0.userID == userID && $0.photoURL != nil }
                .sorted { ($0.createdAt) > ($1.createdAt) }
                .prefix(3)

            for log in logsWithPhotos {
                guard let urlString = log.photoURL,
                      let url = URL(string: urlString) else { continue }

                if let image = await ImageDownsampler.downloadImage(
                    from: url,
                    targetSize: CGSize(width: 300, height: 300)
                ) {
                    photos.append(image)
                }
            }
        }

        let data = InviteCardData(
            inviterName: inviterName,
            inviterUsername: inviterUsername,
            photos: photos
        )

        let canvas = InviteCardDottedTrail(data: data)
            .frame(width: 1080, height: 1350)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0
        return renderer.uiImage
    }
}
