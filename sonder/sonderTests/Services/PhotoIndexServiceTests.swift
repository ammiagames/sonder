//
//  PhotoIndexServiceTests.swift
//  sonderTests
//
//  Created by Michael Song on 2/18/26.
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import sonder

@Suite(.serialized)
@MainActor
struct PhotoIndexServiceTests {

    private func makeSUT() throws -> (PhotoIndexService, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let service = PhotoIndexService(modelContainer: container)
        return (service, context, container)
    }

    /// Inserts index entries directly into the context for query testing.
    private func insertEntry(
        _ context: ModelContext,
        id: String,
        latitude: Double,
        longitude: Double
    ) {
        let entry = PhotoLocationIndex(
            localIdentifier: id,
            latitude: latitude,
            longitude: longitude
        )
        context.insert(entry)
        try! context.save()
    }

    // MARK: - Query Tests

    @Test func query_findsNearbyPhotos() throws {
        let (service, context, container) = try makeSUT()
        _ = container
        service.hasBuiltIndex = true

        // Times Square: 40.7580, -73.9855
        let searchLocation = CLLocation(latitude: 40.7580, longitude: -73.9855)

        // ~50m away — should be found
        insertEntry(context, id: "nearby-1", latitude: 40.7584, longitude: -73.9855)
        // ~100m away — should be found
        insertEntry(context, id: "nearby-2", latitude: 40.7589, longitude: -73.9855)
        // ~5km away — should NOT be found
        insertEntry(context, id: "far-away", latitude: 40.8000, longitude: -73.9855)

        let results = service.query(near: [searchLocation], radiusMeters: 200)

        #expect(results.contains("nearby-1"))
        #expect(results.contains("nearby-2"))
        #expect(!results.contains("far-away"))
    }

    @Test func query_emptyLocations_returnsEmpty() throws {
        let (service, _, container) = try makeSUT()
        _ = container
        service.hasBuiltIndex = true

        let results = service.query(near: [], radiusMeters: 200)
        #expect(results.isEmpty)
    }

    @Test func query_multipleSearchLocations() throws {
        let (service, context, container) = try makeSUT()
        _ = container
        service.hasBuiltIndex = true

        // Two search centers ~10km apart
        let location1 = CLLocation(latitude: 40.7580, longitude: -73.9855) // Times Square
        let location2 = CLLocation(latitude: 40.6892, longitude: -74.0445) // Statue of Liberty

        // Near Times Square
        insertEntry(context, id: "near-ts", latitude: 40.7582, longitude: -73.9856)
        // Near Statue of Liberty
        insertEntry(context, id: "near-sol", latitude: 40.6894, longitude: -74.0443)
        // Far from both
        insertEntry(context, id: "far", latitude: 41.0000, longitude: -74.0000)

        let results = service.query(near: [location1, location2], radiusMeters: 200)

        #expect(results.contains("near-ts"))
        #expect(results.contains("near-sol"))
        #expect(!results.contains("far"))
    }

    @Test func query_respectsRadius() throws {
        let (service, context, container) = try makeSUT()
        _ = container
        service.hasBuiltIndex = true

        let searchLocation = CLLocation(latitude: 40.7580, longitude: -73.9855)

        // ~150m away — inside 200m radius
        insertEntry(context, id: "inside", latitude: 40.7593, longitude: -73.9855)
        // ~250m away — outside 200m radius
        insertEntry(context, id: "outside", latitude: 40.7602, longitude: -73.9855)

        let results = service.query(near: [searchLocation], radiusMeters: 200)

        #expect(results.contains("inside"))
        #expect(!results.contains("outside"))
    }

    @Test func query_returnsEmptyWhenIndexNotBuilt() throws {
        let (service, context, container) = try makeSUT()
        _ = container
        // hasBuiltIndex defaults to false

        let searchLocation = CLLocation(latitude: 40.7580, longitude: -73.9855)
        insertEntry(context, id: "nearby", latitude: 40.7582, longitude: -73.9855)

        let results = service.query(near: [searchLocation], radiusMeters: 200)
        #expect(results.isEmpty)
    }

    @Test func query_noMatchesReturnsEmpty() throws {
        let (service, context, container) = try makeSUT()
        _ = container
        service.hasBuiltIndex = true

        // All entries are far from search location
        let searchLocation = CLLocation(latitude: 40.7580, longitude: -73.9855)
        insertEntry(context, id: "far-1", latitude: 35.0000, longitude: -118.0000)
        insertEntry(context, id: "far-2", latitude: 48.8566, longitude: 2.3522)

        let results = service.query(near: [searchLocation], radiusMeters: 200)
        #expect(results.isEmpty)
    }
}
