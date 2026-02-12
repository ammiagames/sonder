import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct PlacesCacheServiceTests {

    private func makeSUT() throws -> (PlacesCacheService, ModelContext, ModelContainer) {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        let service = PlacesCacheService(modelContext: context)
        return (service, context, container)
    }

    // MARK: - Recent Searches

    @Test func addRecentSearch_insertsNew() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        service.addRecentSearch(placeId: "p1", name: "Cafe", address: "123 St")

        let results = service.getRecentSearches()
        #expect(results.count == 1)
        #expect(results.first?.placeId == "p1")
        #expect(results.first?.name == "Cafe")
    }

    @Test func addRecentSearch_updatesTimestamp() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        service.addRecentSearch(placeId: "p1", name: "Cafe", address: "123 St")
        let firstTimestamp = service.getRecentSearches().first!.searchedAt

        Thread.sleep(forTimeInterval: 0.01)
        service.addRecentSearch(placeId: "p1", name: "Cafe", address: "123 St")

        let results = service.getRecentSearches()
        #expect(results.count == 1)
        #expect(results.first!.searchedAt >= firstTimestamp)
    }

    @Test func getRecentSearches_sortOrder() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        service.addRecentSearch(placeId: "p1", name: "First", address: "1 St")
        Thread.sleep(forTimeInterval: 0.01)
        service.addRecentSearch(placeId: "p2", name: "Second", address: "2 St")
        Thread.sleep(forTimeInterval: 0.01)
        service.addRecentSearch(placeId: "p3", name: "Third", address: "3 St")

        let results = service.getRecentSearches()
        #expect(results.count == 3)
        #expect(results[0].placeId == "p3")
        #expect(results[1].placeId == "p2")
        #expect(results[2].placeId == "p1")
    }

    @Test func clearRecentSearch_removesOne() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        service.addRecentSearch(placeId: "p1", name: "First", address: "1 St")
        service.addRecentSearch(placeId: "p2", name: "Second", address: "2 St")

        service.clearRecentSearch(placeId: "p1")

        let results = service.getRecentSearches()
        #expect(results.count == 1)
        #expect(results.first?.placeId == "p2")
    }

    @Test func clearAllRecentSearches() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        service.addRecentSearch(placeId: "p1", name: "First", address: "1 St")
        service.addRecentSearch(placeId: "p2", name: "Second", address: "2 St")
        service.addRecentSearch(placeId: "p3", name: "Third", address: "3 St")

        service.clearAllRecentSearches()

        let results = service.getRecentSearches()
        #expect(results.isEmpty)
    }

    @Test func trimRecentSearches_enforcesMax() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        for i in 1...25 {
            Thread.sleep(forTimeInterval: 0.001)
            service.addRecentSearch(placeId: "p\(i)", name: "Place \(i)", address: "\(i) St")
        }

        let results = service.getRecentSearches()
        #expect(results.count == 20)
        #expect(results.first?.placeId == "p25")
    }

    // MARK: - Place Cache from Details

    @Test func cachePlaceFromDetails_inserts() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let details = TestData.placeDetails(placeId: "p-detail-1", name: "Detail Place")

        let place = service.cachePlace(from: details)

        #expect(place.id == "p-detail-1")
        #expect(place.name == "Detail Place")

        let fetched = service.getPlace(by: "p-detail-1")
        #expect(fetched != nil)
        #expect(fetched?.name == "Detail Place")
    }

    @Test func cachePlaceFromDetails_updates() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let details1 = TestData.placeDetails(placeId: "p-1", name: "Old Name")
        _ = service.cachePlace(from: details1)

        let details2 = TestData.placeDetails(placeId: "p-1", name: "New Name")
        let updated = service.cachePlace(from: details2)

        #expect(updated.name == "New Name")

        let fetched = service.getPlace(by: "p-1")
        #expect(fetched?.name == "New Name")
    }

    // MARK: - Place Cache from Nearby

    @Test func cachePlaceFromNearby_inserts() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let nearby = TestData.nearbyPlace(placeId: "nb-1", name: "Nearby Cafe")

        let place = service.cachePlace(from: nearby)

        #expect(place.id == "nb-1")
        #expect(place.name == "Nearby Cafe")
    }

    @Test func cachePlaceFromNearby_updatesPhotoIfMissing() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive

        let nearby1 = TestData.nearbyPlace(placeId: "nb-1", photoReference: nil)
        _ = service.cachePlace(from: nearby1)

        let nearby2 = NearbyPlace(
            placeId: "nb-1",
            name: "Nearby Cafe",
            address: "456 Ave",
            latitude: 40.0,
            longitude: -74.0,
            types: [],
            photoReference: "new-photo-ref"
        )
        let updated = service.cachePlace(from: nearby2)

        #expect(updated.photoReference == "new-photo-ref")
    }

    // MARK: - Get Place

    @Test func getPlace_found() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive
        let place = TestData.place(id: "find-me")
        context.insert(place)
        try context.save()

        let found = service.getPlace(by: "find-me")
        #expect(found != nil)
        #expect(found?.id == "find-me")
    }

    @Test func getPlace_notFound() throws {
        let (service, _, container) = try makeSUT()
        _ = container  // Keep container alive
        let found = service.getPlace(by: "nonexistent")
        #expect(found == nil)
    }

    // MARK: - Search Cached Places

    @Test func searchCachedPlaces_byName() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive
        context.insert(TestData.place(id: "p1", name: "Italian Bistro", address: "100 Main"))
        context.insert(TestData.place(id: "p2", name: "Sushi Bar", address: "200 Oak"))
        try context.save()

        let results = service.searchCachedPlaces(query: "Italian")
        #expect(results.count == 1)
        #expect(results.first?.id == "p1")
    }

    @Test func searchCachedPlaces_byAddress() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive
        context.insert(TestData.place(id: "p1", name: "Cafe", address: "100 Broadway"))
        context.insert(TestData.place(id: "p2", name: "Bar", address: "200 Elm"))
        try context.save()

        let results = service.searchCachedPlaces(query: "Broadway")
        #expect(results.count == 1)
        #expect(results.first?.id == "p1")
    }

    @Test func searchCachedPlaces_caseInsensitive() throws {
        let (service, context, container) = try makeSUT()
        _ = container  // Keep container alive
        context.insert(TestData.place(id: "p1", name: "PIZZA Palace", address: "100 Main"))
        try context.save()

        let results = service.searchCachedPlaces(query: "pizza")
        #expect(results.count == 1)
        #expect(results.first?.id == "p1")
    }
}
