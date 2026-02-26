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

    // MARK: - movePhotos

    @Test func movePhotos_movesPhotosBetweenClusters() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let p2 = PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)
        let p3 = PhotoMetadata(id: "p3", coordinate: nil, creationDate: nil)
        let cluster1 = PhotoCluster(photoMetadata: [p1, p2])
        let cluster2 = PhotoCluster(photoMetadata: [p3])

        service.clusters = [cluster1, cluster2]

        service.movePhotos(photoIDs: ["p1"], toClusterID: cluster2.id)

        // cluster1 should have 1 photo, cluster2 should have 2
        #expect(service.clusters.count == 2)
        let c1 = service.clusters.first(where: { $0.id == cluster1.id })!
        let c2 = service.clusters.first(where: { $0.id == cluster2.id })!
        #expect(c1.photoMetadata.count == 1)
        #expect(c1.photoMetadata[0].id == "p2")
        #expect(c2.photoMetadata.count == 2)
        #expect(c2.photoMetadata.map(\.id).contains("p1"))
    }

    @Test func movePhotos_recalculatesCentroid() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0), creationDate: nil)
        let p2 = PhotoMetadata(id: "p2", coordinate: CLLocationCoordinate2D(latitude: 42.0, longitude: -72.0), creationDate: nil)
        let p3 = PhotoMetadata(id: "p3", coordinate: CLLocationCoordinate2D(latitude: 34.0, longitude: -118.0), creationDate: nil)
        let cluster1 = PhotoCluster(photoMetadata: [p1, p2], centroid: CLLocationCoordinate2D(latitude: 41.0, longitude: -73.0))
        let cluster2 = PhotoCluster(photoMetadata: [p3], centroid: CLLocationCoordinate2D(latitude: 34.0, longitude: -118.0))

        service.clusters = [cluster1, cluster2]

        // Move p2 from cluster1 to cluster2
        service.movePhotos(photoIDs: ["p2"], toClusterID: cluster2.id)

        // cluster1 centroid should now be just p1: (40, -74)
        let c1 = service.clusters.first(where: { $0.id == cluster1.id })!
        #expect(c1.centroid!.latitude == 40.0)
        #expect(c1.centroid!.longitude == -74.0)

        // cluster2 centroid should be average of p3 and p2: ((34+42)/2, (-118+-72)/2) = (38, -95)
        let c2 = service.clusters.first(where: { $0.id == cluster2.id })!
        #expect(c2.centroid!.latitude == 38.0)
        #expect(c2.centroid!.longitude == -95.0)
    }

    @Test func movePhotos_removesEmptySourceCluster() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let p2 = PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)
        let cluster1 = PhotoCluster(photoMetadata: [p1])
        let cluster2 = PhotoCluster(photoMetadata: [p2])

        service.clusters = [cluster1, cluster2]

        // Move only photo out of cluster1
        service.movePhotos(photoIDs: ["p1"], toClusterID: cluster2.id)

        #expect(service.clusters.count == 1)
        #expect(service.clusters[0].id == cluster2.id)
        #expect(service.clusters[0].photoMetadata.count == 2)
    }

    @Test func movePhotos_noOpForSameCluster() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [p1])

        service.clusters = [cluster]

        // Move photo to its own cluster — should be a no-op
        service.movePhotos(photoIDs: ["p1"], toClusterID: cluster.id)

        #expect(service.clusters.count == 1)
        #expect(service.clusters[0].photoMetadata.count == 1)
    }

    // MARK: - moveUnlocatedPhotos

    @Test func moveUnlocatedPhotos_movesToCluster() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let unlocated = PhotoMetadata(id: "u1", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [p1])

        service.clusters = [cluster]
        service.unlocatedPhotos = [unlocated]

        service.moveUnlocatedPhotos(photoIDs: ["u1"], toClusterID: cluster.id)

        #expect(service.unlocatedPhotos.isEmpty)
        #expect(service.clusters[0].photoMetadata.count == 2)
        #expect(service.clusters[0].photoMetadata.map(\.id).contains("u1"))
    }

    // MARK: - addEmptyCluster

    @Test func addEmptyCluster_appendsNewCluster() throws {
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

        service.clusters = []

        let newID = service.addEmptyCluster()

        #expect(service.clusters.count == 1)
        #expect(service.clusters[0].id == newID)
        #expect(service.clusters[0].photoMetadata.isEmpty)
        #expect(service.clusters[0].suggestedPlaces.isEmpty)
        #expect(service.clusters[0].confirmedPlace == nil)
        #expect(service.clusters[0].rating == nil)
        #expect(service.clusters[0].date != nil) // Date() is set
    }

    // MARK: - excludePhoto

    @Test func excludePhoto_movesToExcludedPool() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let p2 = PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [p1, p2])
        service.clusters = [cluster]

        service.excludePhoto("p1", fromClusterID: cluster.id)

        #expect(service.clusters[0].photoMetadata.count == 1)
        #expect(service.clusters[0].photoMetadata[0].id == "p2")
        #expect(service.excludedPhotos.count == 1)
        #expect(service.excludedPhotos[0].id == "p1")
    }

    @Test func excludePhoto_removesEmptyCluster() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [p1])
        service.clusters = [cluster]

        service.excludePhoto("p1", fromClusterID: cluster.id)

        #expect(service.clusters.isEmpty)
        #expect(service.excludedPhotos.count == 1)
    }

    @Test func restorePhoto_movesBackToCluster() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [])
        service.clusters = [cluster]
        service.excludedPhotos = [p1]

        service.restorePhoto("p1", toClusterID: cluster.id)

        #expect(service.excludedPhotos.isEmpty)
        #expect(service.clusters[0].photoMetadata.count == 1)
        #expect(service.clusters[0].photoMetadata[0].id == "p1")
    }

    // MARK: - reorderPhoto

    @Test func reorderPhoto_swapsPositions() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let p2 = PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)
        let p3 = PhotoMetadata(id: "p3", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [p1, p2, p3])
        service.clusters = [cluster]

        // Move first photo to last position
        service.reorderPhoto(in: cluster.id, fromIndex: 0, toIndex: 2)

        #expect(service.clusters[0].photoMetadata.map(\.id) == ["p2", "p3", "p1"])
    }

    @Test func reorderPhoto_noOpForSameIndex() throws {
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

        let p1 = PhotoMetadata(id: "p1", coordinate: nil, creationDate: nil)
        let p2 = PhotoMetadata(id: "p2", coordinate: nil, creationDate: nil)
        let cluster = PhotoCluster(photoMetadata: [p1, p2])
        service.clusters = [cluster]

        service.reorderPhoto(in: cluster.id, fromIndex: 0, toIndex: 0)

        #expect(service.clusters[0].photoMetadata.map(\.id) == ["p1", "p2"])
    }

    @Test func discardAllExcluded_clearsPool() throws {
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

        let e1 = PhotoMetadata(id: "e1", coordinate: nil, creationDate: nil)
        let e2 = PhotoMetadata(id: "e2", coordinate: nil, creationDate: nil)
        let e3 = PhotoMetadata(id: "e3", coordinate: nil, creationDate: nil)
        service.excludedPhotos = [e1, e2, e3]

        service.discardAllExcluded()

        #expect(service.excludedPhotos.isEmpty)
    }

    @Test func discardAllExcluded_noOpWhenEmpty() throws {
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

        service.excludedPhotos = []
        service.discardAllExcluded()

        #expect(service.excludedPhotos.isEmpty)
    }

    @Test func excludeUnlocatedPhoto_movesToExcludedPool() throws {
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

        let u1 = PhotoMetadata(id: "u1", coordinate: nil, creationDate: nil)
        let u2 = PhotoMetadata(id: "u2", coordinate: nil, creationDate: nil)
        service.unlocatedPhotos = [u1, u2]

        service.excludeUnlocatedPhoto("u1")

        #expect(service.unlocatedPhotos.count == 1)
        #expect(service.unlocatedPhotos[0].id == "u2")
        #expect(service.excludedPhotos.count == 1)
        #expect(service.excludedPhotos[0].id == "u1")
    }
}
