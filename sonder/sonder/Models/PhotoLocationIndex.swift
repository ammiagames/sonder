//
//  PhotoLocationIndex.swift
//  sonder
//
//  Created by Michael Song on 2/18/26.
//

import Foundation
import SwiftData

@Model
final class PhotoLocationIndex {
    @Attribute(.unique) var localIdentifier: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(
        localIdentifier: String,
        latitude: Double,
        longitude: Double,
        createdAt: Date = Date()
    ) {
        self.localIdentifier = localIdentifier
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}
