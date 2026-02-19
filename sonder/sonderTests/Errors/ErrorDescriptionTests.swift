import Testing
import Foundation
@testable import sonder

struct ErrorDescriptionTests {

    @Test func authError_descriptions() {
        let cases: [AuthError] = [.invalidCredential, .networkError, .userCreationFailed]
        for error in cases {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func syncError_descriptions() {
        let cases: [SyncError] = [.missingPlace, .networkError, .invalidData]
        for error in cases {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func photoError_descriptions() {
        let cases: [PhotoService.PhotoError] = [
            .compressionFailed,
            .uploadFailed(NSError(domain: "test", code: 1)),
            .networkError,
            .invalidImage
        ]
        for error in cases {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func placesError_descriptions() {
        let cases: [GooglePlacesService.PlacesError] = [
            .invalidAPIKey,
            .networkError(NSError(domain: "test", code: 1)),
            .invalidResponse,
            .apiError("test"),
            .offline
        ]
        for error in cases {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

}
