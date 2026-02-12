import Foundation
import SwiftData
import Testing
@testable import sonder

/// Creates an in-memory SwiftData ModelContainer for testing.
/// Each call creates a uniquely named store to avoid conflicts between parallel tests.
/// IMPORTANT: Callers must keep a strong reference to the returned container.
@MainActor
func makeTestModelContainer() throws -> ModelContainer {
    let config = ModelConfiguration(
        UUID().uuidString,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(
        for: User.self, Place.self, Log.self, Trip.self,
        TripInvitation.self, Follow.self, WantToGo.self, RecentSearch.self,
        configurations: config
    )
}

/// Returns a deterministic UTC date for test assertions: 2025-01-15T12:00:00Z
func fixedDate() -> Date {
    var components = DateComponents()
    components.year = 2025
    components.month = 1
    components.day = 15
    components.hour = 12
    components.minute = 0
    components.second = 0
    components.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: components)!
}

/// Creates a JSONEncoder configured for Supabase-compatible date encoding
func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

/// Creates a JSONDecoder configured for Supabase-compatible date decoding
func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}
