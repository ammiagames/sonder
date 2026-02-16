import Testing
import Foundation
import UIKit
@testable import sonder

@Suite(.serialized)
@MainActor
struct PhotoServiceTests {

    @Test func compressImage_underLimit() {
        let service = PhotoService()

        // Create a small 200x200 red image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        let data = service.compressImage(image, maxSizeBytes: 50_000)
        #expect(data != nil)
        #expect(data!.count <= 50_000)
    }

    @Test func hasActiveUploads_false() {
        let service = PhotoService()
        #expect(service.hasActiveUploads == false)
        #expect(service.totalPendingPhotos == 0)
    }

    @Test func isUploading_false() {
        let service = PhotoService()
        #expect(service.isUploading == false)
    }
}
