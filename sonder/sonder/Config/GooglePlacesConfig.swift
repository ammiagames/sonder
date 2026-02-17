//
//  GooglePlacesConfig.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation

/// Configuration for Google Places API
struct GooglePlacesConfig {
    static let apiKey = "AIzaSyB0M33cRQfJkZbRKVf77KlsftQ_3nJXk20"

    // REST API base URL (used only for photo URLs — all other calls go through the SDK)
    static let baseURL = "https://places.googleapis.com/v1"

    // Search configuration
    static let autocompleteDebounceMs: Int = 500
    static let nearbyRadiusMeters: Int = 500
    static let maxRecentSearches: Int = 20
}
