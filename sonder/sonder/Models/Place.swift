//
//  Place.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class Place {
    @Attribute(.unique) var id: String // Google place_id
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var types: [String]
    var photoReference: String?
    var createdAt: Date
    
    init(
        id: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        types: [String] = [],
        photoReference: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.types = types
        self.photoReference = photoReference
        self.createdAt = createdAt
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var categoryIcon: String {
        ExploreMapFilter.CategoryFilter.category(for: types)?.icon ?? "mappin"
    }
}

// MARK: - Codable for Supabase sync
extension Place: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case latitude = "lat"
        case longitude = "lng"
        case types
        case photoReference = "photo_reference"
        case createdAt = "created_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let address = try container.decode(String.self, forKey: .address)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let types = try container.decodeIfPresent([String].self, forKey: .types) ?? []
        let photoReference = try container.decodeIfPresent(String.self, forKey: .photoReference)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        self.init(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            types: types,
            photoReference: photoReference,
            createdAt: createdAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(types, forKey: .types)
        try container.encodeIfPresent(photoReference, forKey: .photoReference)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
