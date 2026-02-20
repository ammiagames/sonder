//
//  SMSInviteView.swift
//  sonder
//

import SwiftUI
import LinkPresentation
import MessageUI

// MARK: - Rich Invite Share Sheet (UIActivityViewController + LPLinkMetadata)

/// Presents a share sheet with a rich link preview containing the invite card image.
/// Uses UIActivityViewController + LPLinkMetadata so the preview appears in iMessage.
struct InviteShareSheet: UIViewControllerRepresentable {
    let inviteURL: URL
    let cardImage: UIImage
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = InviteLinkItem(url: inviteURL, image: cardImage)
        let activityVC = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return activityVC
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Activity item that provides LPLinkMetadata for rich link previews in Messages.
/// Shares the App Store URL (for a clean link preview) while embedding the card image via metadata.
private final class InviteLinkItem: NSObject, UIActivityItemSource {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/sonder")!

    let url: URL
    let image: UIImage

    init(url: URL, image: UIImage) {
        self.url = url
        self.image = image
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        return Self.appStoreURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        return Self.appStoreURL
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = Self.appStoreURL
        metadata.url = Self.appStoreURL
        metadata.title = "You're invited to Sonder"
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

// MARK: - Legacy SMS Compose (kept for direct SMS fallback)

struct SMSInviteView: UIViewControllerRepresentable {
    let phoneNumber: String
    let inviteURL: URL
    let onDismiss: () -> Void

    static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [phoneNumber]
        controller.body = "Hey! Come join me on Sonder — it's a fun way to remember your favorite places and discover where friends go. \(InviteLinkItem.appStoreURL.absoluteString)"
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) { [weak self] in
                self?.onDismiss()
            }
        }
    }
}
