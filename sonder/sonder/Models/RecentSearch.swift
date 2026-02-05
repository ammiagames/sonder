//
//  RecentSearch.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData

/// SwiftData model for tracking recent place searches
@Model
final class RecentSearch {
    @Attribute(.unique) var placeId: String
    var name: String
    var address: String
    var searchedAt: Date

    init(placeId: String, name: String, address: String, searchedAt: Date = Date()) {
        self.placeId = placeId
        self.name = name
        self.address = address
        self.searchedAt = searchedAt
    }
}
