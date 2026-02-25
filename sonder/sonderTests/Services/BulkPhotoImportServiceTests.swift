import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import sonder

@Suite(.serialized)
@MainActor
struct BulkPhotoImportServiceTests {

    // MARK: - Helpers

    private func makeTestContainer() throws -> ModelContainer {
        try makeTestModelContainer()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - BulkImportState Tests

    @Test func bulkImportState_displayText() {
        #expect(BulkImportState.selecting.displayText == "Select Photos")
        #expect(BulkImportState.extracting(progress: 0.5).displayText == "Extracting locations...")
        #expect(BulkImportState.clustering.displayText == "Grouping photos...")
        #expect(BulkImportState.resolving(progress: 0.3).displayText == "Finding places...")
        #expect(BulkImportState.reviewing.displayText == "Review")
        #expect(BulkImportState.saving(progress: 0.8).displayText == "Creating logs...")
        #expect(BulkImportState.complete(logCount: 5).displayText == "Created 5 logs")
        #expect(BulkImportState.failed("oops").displayText == "oops")
    }

    @Test func bulkImportState_progress() {
        #expect(BulkImportState.selecting.progress == nil)
        #expect(BulkImportState.extracting(progress: 0.5).progress == 0.5)
        #expect(BulkImportState.clustering.progress == nil)
        #expect(BulkImportState.resolving(progress: 0.3).progress == 0.3)
        #expect(BulkImportState.reviewing.progress == nil)
        #expect(BulkImportState.saving(progress: 0.8).progress == 0.8)
        #expect(BulkImportState.complete(logCount: 5).progress == nil)
    }

    // MARK: - PhotoCluster Model Tests

    @Test func photoCluster_defaultValues() {
        let photo = PhotoMetadata(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            creationDate: Date()
        )
        let cluster = PhotoCluster(photoMetadata: [photo])

        #expect(cluster.suggestedPlaces.isEmpty)
        #expect(cluster.confirmedPlace == nil)
        #expect(cluster.rating == nil)
    }

    // MARK: - Review Mutations

    @Test func updateRating_setsRatingOnCluster() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let service = BulkPhotoImportService(
            googlePlacesService: GooglePlacesService(),
            placesCacheService: PlacesCacheService(modelContext: context),
            photoService: PhotoService(),
            photoSuggestionService: PhotoSuggestionService(),
            syncEngine: SyncEngine(modelContext: context),
            modelContext: context
        )

        let photo = PhotoMetadata(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            creationDate: Date()
        )
        let cluster = PhotoCluster(photoMetadata: [photo])

        // Inject cluster manually via reflection-free approach
        service.clusters = [cluster]

        service.updateRating(for: cluster.id, rating: .great)
        #expect(service.clusters[0].rating == .great)
    }

    @Test func removeCluster_removesFromList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let service = BulkPhotoImportService(
            googlePlacesService: GooglePlacesService(),
            placesCacheService: PlacesCacheService(modelContext: context),
            photoService: PhotoService(),
            photoSuggestionService: PhotoSuggestionService(),
            syncEngine: SyncEngine(modelContext: context),
            modelContext: context
        )

        let photo1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let photo2 = PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)
        let cluster1 = PhotoCluster(photoMetadata: [photo1])
        let cluster2 = PhotoCluster(photoMetadata: [photo2])

        service.clusters = [cluster1, cluster2]
        service.removeCluster(cluster1.id)

        #expect(service.clusters.count == 1)
        #expect(service.clusters[0].id == cluster2.id)
    }

    // MARK: - Validation

    @Test func canSave_falseWhenNoRatings() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let service = BulkPhotoImportService(
            googlePlacesService: GooglePlacesService(),
            placesCacheService: PlacesCacheService(modelContext: context),
            photoService: PhotoService(),
            photoSuggestionService: PhotoSuggestionService(),
            syncEngine: SyncEngine(modelContext: context),
            modelContext: context
        )

        let nearby = NearbyPlace(
            placeId: "place1",
            name: "Test Place",
            address: "123 St",
            latitude: 40.0,
            longitude: -74.0,
            types: [],
            photoReference: nil
        )
        let cluster = PhotoCluster(
            photoMetadata: [PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)],
            suggestedPlaces: [nearby]
        )

        service.clusters = [cluster]
        #expect(!service.canSave) // No rating set
    }

    @Test func canSave_trueWhenRatingAndPlacePresent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let service = BulkPhotoImportService(
            googlePlacesService: GooglePlacesService(),
            placesCacheService: PlacesCacheService(modelContext: context),
            photoService: PhotoService(),
            photoSuggestionService: PhotoSuggestionService(),
            syncEngine: SyncEngine(modelContext: context),
            modelContext: context
        )

        let nearby = NearbyPlace(
            placeId: "place1",
            name: "Test Place",
            address: "123 St",
            latitude: 40.0,
            longitude: -74.0,
            types: [],
            photoReference: nil
        )
        let cluster = PhotoCluster(
            photoMetadata: [PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)],
            suggestedPlaces: [nearby],
            rating: .great
        )

        service.clusters = [cluster]
        #expect(service.canSave)
    }

    @Test func readyCount_countsOnlyValidClusters() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let service = BulkPhotoImportService(
            googlePlacesService: GooglePlacesService(),
            placesCacheService: PlacesCacheService(modelContext: context),
            photoService: PhotoService(),
            photoSuggestionService: PhotoSuggestionService(),
            syncEngine: SyncEngine(modelContext: context),
            modelContext: context
        )

        let nearby = NearbyPlace(
            placeId: "place1",
            name: "Test",
            address: "123 St",
            latitude: 40.0,
            longitude: -74.0,
            types: [],
            photoReference: nil
        )

        let ready = PhotoCluster(
            photoMetadata: [PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)],
            suggestedPlaces: [nearby],
            rating: .mustSee
        )
        let notReady = PhotoCluster(
            photoMetadata: [PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)],
            suggestedPlaces: [nearby]
            // No rating
        )

        service.clusters = [ready, notReady]
        #expect(service.readyCount == 1)
    }

    // MARK: - tripSortOrder Assignment

    @Test func saveAllLogs_assignsIncrementingTripSortOrder() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let cacheService = PlacesCacheService(modelContext: context)
        let service = BulkPhotoImportService(
            googlePlacesService: GooglePlacesService(),
            placesCacheService: cacheService,
            photoService: PhotoService(),
            photoSuggestionService: PhotoSuggestionService(),
            syncEngine: SyncEngine(modelContext: context),
            modelContext: context
        )

        // Pre-create a place so cachePlace can find it
        let place = Place(
            id: "place1",
            name: "Test Place",
            address: "123 St",
            latitude: 40.0,
            longitude: -74.0
        )
        context.insert(place)
        try context.save()

        // Create a trip
        let trip = Trip(name: "Test Trip", createdBy: "user1")
        context.insert(trip)
        try context.save()

        // Add an existing log to the trip
        let existingLog = Log(
            userID: "user1",
            placeID: "place1",
            rating: .okay,
            tripID: trip.id,
            tripSortOrder: 0
        )
        context.insert(existingLog)
        try context.save()

        // Setup clusters with confirmed places (no photos to avoid PHAsset loading)
        let cluster1 = PhotoCluster(
            photoMetadata: [],
            confirmedPlace: place,
            rating: .great
        )
        let cluster2 = PhotoCluster(
            photoMetadata: [],
            confirmedPlace: place,
            rating: .mustSee
        )

        service.clusters = [cluster1, cluster2]

        await service.saveAllLogs(userID: "user1", tripID: trip.id)

        // Fetch all logs for the trip
        let tripID = trip.id
        let descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.tripID == tripID }
        )
        let tripLogs = (try? context.fetch(descriptor)) ?? []

        // Should have 3 logs total (1 existing + 2 new)
        #expect(tripLogs.count == 3)

        // New logs should have tripSortOrder 1 and 2
        let newLogs = tripLogs.filter { $0.id != existingLog.id }.sorted { ($0.tripSortOrder ?? 0) < ($1.tripSortOrder ?? 0) }
        #expect(newLogs.count == 2)
        #expect(newLogs[0].tripSortOrder == 1)
        #expect(newLogs[1].tripSortOrder == 2)
    }
}
