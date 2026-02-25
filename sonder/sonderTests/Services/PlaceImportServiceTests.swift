//
//  PlaceImportServiceTests.swift
//  sonderTests
//
//  Created by Michael Song on 2/25/26.
//

import Testing
import Foundation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct PlaceImportServiceTests {

    // MARK: - ImportJob Tests

    @Test func importJob_initialState() {
        let entries = [
            ImportedPlaceEntry(name: "Place A"),
            ImportedPlaceEntry(name: "Place B"),
        ]
        let job = ImportJob(entries: entries)

        #expect(job.totalCount == 2)
        #expect(job.resolvedCount == 0)
        #expect(job.failedCount == 0)
        #expect(job.skippedCount == 0)
        #expect(job.processedCount == 0)
        #expect(job.progress == 0)
    }

    @Test func importJob_markResolved_updatesCounters() {
        let entries = [
            ImportedPlaceEntry(name: "Place A"),
            ImportedPlaceEntry(name: "Place B"),
            ImportedPlaceEntry(name: "Place C"),
        ]
        let job = ImportJob(entries: entries)
        let details = TestData.placeDetails(name: "Place A")

        job.markResolved(entryID: entries[0].id, result: .resolved(details))
        #expect(job.resolvedCount == 1)
        #expect(job.progress == 1.0 / 3.0)

        job.markResolved(entryID: entries[1].id, result: .skipped)
        #expect(job.skippedCount == 1)

        job.markResolved(entryID: entries[2].id, result: .failed("not found"))
        #expect(job.failedCount == 1)
        #expect(job.processedCount == 3)
        #expect(job.progress == 1.0)
    }

    // MARK: - ImportSummary Tests

    @Test func importSummary_values() {
        let summary = ImportSummary(
            totalAttempted: 10,
            successCount: 7,
            failedCount: 2,
            skippedCount: 1,
            listName: "My List"
        )

        #expect(summary.totalAttempted == 10)
        #expect(summary.successCount == 7)
        #expect(summary.failedCount == 2)
        #expect(summary.skippedCount == 1)
        #expect(summary.listName == "My List")
    }

    // MARK: - ImportedPlaceEntry Tests

    @Test func importedPlaceEntry_defaultValues() {
        let entry = ImportedPlaceEntry(name: "Test Place")

        #expect(entry.name == "Test Place")
        #expect(entry.address == nil)
        #expect(entry.coordinate == nil)
        #expect(entry.sourceURL == nil)
        #expect(entry.sourceListName == nil)
        #expect(entry.dateAdded == nil)
    }

    @Test func importedPlaceEntry_uniqueIDs() {
        let entry1 = ImportedPlaceEntry(name: "A")
        let entry2 = ImportedPlaceEntry(name: "B")
        #expect(entry1.id != entry2.id)
    }

    // MARK: - PlaceImportService Integration

    @Test func service_saveResolvedPlace_cachesAndAddsToWantToGo() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        _ = container

        let wantToGoService = WantToGoService(modelContext: context)
        let placesCacheService = PlacesCacheService(modelContext: context)
        let savedListsService = SavedListsService(modelContext: context)
        let googlePlacesService = GooglePlacesService()

        let service = PlaceImportService(
            googlePlacesService: googlePlacesService,
            wantToGoService: wantToGoService,
            savedListsService: savedListsService,
            placesCacheService: placesCacheService
        )

        let details = TestData.placeDetails(
            placeId: "ChIJ_import_test",
            name: "Imported Place",
            formattedAddress: "123 Import St"
        )

        await service.saveResolvedPlace(details, userID: "user-1", listID: nil)

        // Verify place was cached
        let cachedPlace = placesCacheService.getPlace(by: "ChIJ_import_test")
        #expect(cachedPlace != nil)
        #expect(cachedPlace?.name == "Imported Place")

        // Verify WantToGo item was created
        let isInWantToGo = wantToGoService.isInWantToGo(placeID: "ChIJ_import_test", userID: "user-1")
        #expect(isInWantToGo)
    }

    @Test func service_saveResolvedPlace_withListID() async throws {
        let container = try makeTestModelContainer()
        let context = container.mainContext
        _ = container

        let wantToGoService = WantToGoService(modelContext: context)
        let placesCacheService = PlacesCacheService(modelContext: context)
        let savedListsService = SavedListsService(modelContext: context)
        let googlePlacesService = GooglePlacesService()

        let service = PlaceImportService(
            googlePlacesService: googlePlacesService,
            wantToGoService: wantToGoService,
            savedListsService: savedListsService,
            placesCacheService: placesCacheService
        )

        let details = TestData.placeDetails(placeId: "ChIJ_list_test", name: "Listed Place")

        await service.saveResolvedPlace(details, userID: "user-1", listID: "list-1")

        // Verify it was saved with the list ID
        let items = wantToGoService.getWantToGoList(for: "user-1", listID: "list-1")
        #expect(items.contains(where: { $0.placeID == "ChIJ_list_test" }))
    }

    @Test func service_parseFile_invalidURL_setsError() {
        let service = PlaceImportService(
            googlePlacesService: GooglePlacesService(),
            wantToGoService: WantToGoService(modelContext: try! makeTestModelContainer().mainContext),
            savedListsService: SavedListsService(modelContext: try! makeTestModelContainer().mainContext),
            placesCacheService: PlacesCacheService(modelContext: try! makeTestModelContainer().mainContext)
        )

        let entries = service.parseFile(url: URL(fileURLWithPath: "/nonexistent/file.json"))

        #expect(entries.isEmpty)
        #expect(service.parseError != nil)
    }

    // MARK: - ImportSource Tests

    @Test func importSource_properties() {
        let source = ImportSource.googleMaps
        #expect(source.rawValue == "Google Maps")
        #expect(source.iconSystemName == "map")
        #expect(!source.description.isEmpty)
    }
}
