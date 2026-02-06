//
//  WantToGo.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import Foundation
import SwiftData

@Model
final class WantToGo {
    @Attribute(.unique) var id: String
    var userID: String
    var placeID: String
    var placeName: String?
    var placeAddress: String?
    var photoReference: String?
    var sourceLogID: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        userID: String,
        placeID: String,
        placeName: String? = nil,
        placeAddress: String? = nil,
        photoReference: String? = nil,
        sourceLogID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.placeID = placeID
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.photoReference = photoReference
        self.sourceLogID = sourceLogID
        self.createdAt = createdAt
    }
}

// MARK: - Codable for Supabase sync
extension WantToGo: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case placeID = "place_id"
        case placeName = "place_name"
        case placeAddress = "place_address"
        case photoReference = "photo_reference"
        case sourceLogID = "source_log_id"
        case createdAt = "created_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let userID = try container.decode(String.self, forKey: .userID)
        let placeID = try container.decode(String.self, forKey: .placeID)
        let placeName = try container.decodeIfPresent(String.self, forKey: .placeName)
        let placeAddress = try container.decodeIfPresent(String.self, forKey: .placeAddress)
        let photoReference = try container.decodeIfPresent(String.self, forKey: .photoReference)
        let sourceLogID = try container.decodeIfPresent(String.self, forKey: .sourceLogID)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.init(
            id: id,
            userID: userID,
            placeID: placeID,
            placeName: placeName,
            placeAddress: placeAddress,
            photoReference: photoReference,
            sourceLogID: sourceLogID,
            createdAt: createdAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(placeID, forKey: .placeID)
        try container.encodeIfPresent(placeName, forKey: .placeName)
        try container.encodeIfPresent(placeAddress, forKey: .placeAddress)
        try container.encodeIfPresent(photoReference, forKey: .photoReference)
        try container.encodeIfPresent(sourceLogID, forKey: .sourceLogID)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
