//
//  Trip.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import SwiftData

@Model
final class Trip {
    @Attribute(.unique) var id: String
    var name: String
    var coverPhotoURL: String?
    var startDate: Date?
    var endDate: Date?
    var collaboratorIDs: [String]
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: String = UUID().uuidString,
        name: String,
        coverPhotoURL: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        collaboratorIDs: [String] = [],
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.coverPhotoURL = coverPhotoURL
        self.startDate = startDate
        self.endDate = endDate
        self.collaboratorIDs = collaboratorIDs
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Codable for Supabase sync
extension Trip: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case coverPhotoURL = "cover_photo_url"
        case startDate = "start_date"
        case endDate = "end_date"
        case collaboratorIDs = "collaborator_ids"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let coverPhotoURL = try container.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        let startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        let endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        let collaboratorIDs = try container.decodeIfPresent([String].self, forKey: .collaboratorIDs) ?? []
        let createdBy = try container.decode(String.self, forKey: .createdBy)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.init(
            id: id,
            name: name,
            coverPhotoURL: coverPhotoURL,
            startDate: startDate,
            endDate: endDate,
            collaboratorIDs: collaboratorIDs,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(coverPhotoURL, forKey: .coverPhotoURL)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(collaboratorIDs, forKey: .collaboratorIDs)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
