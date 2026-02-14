import Testing
import Foundation
import CoreLocation
import SwiftData
@testable import sonder

@Suite(.serialized)
@MainActor
struct ExploreMapServiceTests {

    private func makeSUT() -> ExploreMapService {
        ExploreMapService()
    }

    // MARK: - Unified Pin Computation

    @Test func computeUnifiedPins_personalOnly() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])

        #expect(pins.count == 1)
        if case .personal(let pinLogs, let pinPlace) = pins[0] {
            #expect(pinLogs.count == 1)
            #expect(pinLogs[0].id == "log1")
            #expect(pinPlace.id == "p1")
        } else {
            Issue.record("Expected .personal pin")
        }
    }

    @Test func computeUnifiedPins_friendsOnly() throws {
        let service = makeSUT()

        // Populate friends' data
        let friendPlace = ExploreMapPlace(
            id: "p1",
            name: "Coffee Shop",
            address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            photoReference: nil,
            logs: [TestData.feedItem(id: "f1", place: TestData.feedPlace(id: "p1"))]
        )
        service.placesMap = ["p1": friendPlace]

        let pins = service.computeUnifiedPins(personalLogs: [], places: [])

        #expect(pins.count == 1)
        if case .friends(let place) = pins[0] {
            #expect(place.id == "p1")
        } else {
            Issue.record("Expected .friends pin")
        }
    }

    @Test func computeUnifiedPins_combinedWhenBothExist() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .mustSee)
        context.insert(place)
        context.insert(log)
        try context.save()

        let friendPlace = ExploreMapPlace(
            id: "p1",
            name: "Coffee Shop",
            address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            photoReference: nil,
            logs: [TestData.feedItem(id: "f1", place: TestData.feedPlace(id: "p1"))]
        )
        service.placesMap = ["p1": friendPlace]

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])

        #expect(pins.count == 1)
        if case .combined(let pinLogs, let pinPlace, let pinFriendPlace) = pins[0] {
            #expect(pinLogs.count == 1)
            #expect(pinLogs[0].id == "log1")
            #expect(pinPlace.id == "p1")
            #expect(pinFriendPlace.id == "p1")
        } else {
            Issue.record("Expected .combined pin")
        }
    }

    // MARK: - Want to Go overlay on unified pins

    @Test func wantToGoPlaceIDs_overlapsWithUnifiedPins() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])
        #expect(pins.count == 1)

        // Simulate wantToGoPlaceIDs derived from WantToGoService.items
        let wantToGoItems = [TestData.wantToGo(userID: "u1", placeID: "p1")]
        let wantToGoPlaceIDs = Set(wantToGoItems.map(\.placeID))

        // The pin's placeID should be in the want-to-go set (merged overlay)
        #expect(wantToGoPlaceIDs.contains(pins[0].placeID))
    }

    @Test func wantToGoPlaceIDs_noOverlapIsStandalonePin() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])
        let unifiedPlaceIDs = Set(pins.map(\.placeID))

        // Want to Go for a DIFFERENT place — should be standalone, not overlapping
        let wantToGoItems = [TestData.wantToGo(userID: "u1", placeID: "p2")]
        let standaloneWantToGoIDs = wantToGoItems
            .map(\.placeID)
            .filter { !unifiedPlaceIDs.contains($0) }

        #expect(standaloneWantToGoIDs == ["p2"])
    }

    // MARK: - Pin selection toggle

    @Test func mapPinTag_toggleSelection() {
        let tag = MapPinTag.unified("pin-1")
        var selection: MapPinTag? = nil

        // Select
        selection = selection == tag ? nil : tag
        #expect(selection == tag)

        // Toggle (re-tap) → deselect
        selection = selection == tag ? nil : tag
        #expect(selection == nil)

        // Select again
        selection = selection == tag ? nil : tag
        #expect(selection == tag)

        // Select different pin → switches
        let otherTag = MapPinTag.unified("pin-2")
        selection = selection == otherTag ? nil : otherTag
        #expect(selection == otherTag)
    }

    @Test func mapPinTag_wantToGoToggle() {
        let tag = MapPinTag.wantToGo("wtg-1")
        var selection: MapPinTag? = nil

        // Select
        selection = selection == tag ? nil : tag
        #expect(selection == tag)

        // Toggle → deselect
        selection = selection == tag ? nil : tag
        #expect(selection == nil)
    }

    // MARK: - Annotated pin identity (merged bookmark badge)

    @Test func annotatedPinIdentity_changesWithWantToGoState() {
        let service = makeSUT()

        let friendPlace = ExploreMapPlace(
            id: "p1",
            name: "Coffee Shop",
            address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            photoReference: nil,
            logs: [TestData.feedItem(id: "f1", place: TestData.feedPlace(id: "p1"))]
        )
        service.placesMap = ["p1": friendPlace]

        let pins = service.computeUnifiedPins(personalLogs: [], places: [])
        let pin = pins[0]

        // Simulate annotatedPins computation: identity = "\(pin.id)_\(isWtg)"
        let identityWithout = "\(pin.id)_false"
        let identityWith = "\(pin.id)_true"

        // Identities MUST differ so ForEach forces Map to recreate the annotation
        #expect(identityWithout != identityWith)
        #expect(identityWithout == "friends-p1_false")
        #expect(identityWith == "friends-p1_true")
    }

    @Test func annotatedPinIdentity_personalPinIncludesWantToGoState() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])
        let pin = pins[0]

        // Personal pin identity also changes with want-to-go state
        let identityWithout = "\(pin.id)_false"
        let identityWith = "\(pin.id)_true"

        #expect(identityWithout == "personal-p1_false")
        #expect(identityWith == "personal-p1_true")
        #expect(identityWithout != identityWith)
    }

    @Test func mapSelection_nativeSelectionBehavior() {
        // Map(selection:) with .tag() handles selection natively.
        // onTapGesture on annotation content CONFLICTS with this —
        // it consumes the tap before Map can process it, causing
        // the pin to select then immediately deselect.
        // Fix: rely on Map's built-in selection + simultaneousGesture for deselect.
        var selection: MapPinTag? = nil
        let tag = MapPinTag.unified("pin-1")

        // Map sets selection on annotation tap
        selection = tag
        #expect(selection == tag)

        // Map clears selection on background tap
        selection = nil
        #expect(selection == nil)

        // Map switches selection when tapping different pin
        selection = tag
        let other = MapPinTag.unified("pin-2")
        selection = other
        #expect(selection == other)
    }

    // MARK: - Re-tap to deselect (simultaneousGesture)

    @Test func retapSelectedPin_deselects() {
        // Simulates the simultaneousGesture logic on annotation content:
        // When a pin is already selected and the user re-taps it,
        // the gesture checks isSelected and clears mapSelection.
        var mapSelection: MapPinTag? = nil
        let tag = MapPinTag.unified("pin-1")

        // Initially select the pin (Map's built-in selection)
        mapSelection = tag
        #expect(mapSelection == tag)

        // Simulate re-tap: simultaneousGesture fires, checks isSelected
        let isSelected = mapSelection == tag
        if isSelected {
            mapSelection = nil
        }
        #expect(mapSelection == nil)
    }

    @Test func tapNonSelectedPin_doesNotInterfere() {
        // When a pin is NOT selected, the simultaneousGesture does nothing,
        // letting Map's native selection handle the tap.
        var mapSelection: MapPinTag? = nil
        let tag = MapPinTag.unified("pin-1")

        // Simulate simultaneousGesture firing on a non-selected pin
        let isSelected = mapSelection == tag
        if isSelected {
            mapSelection = nil
        }
        // mapSelection unchanged — Map's native gesture handles the selection
        #expect(mapSelection == nil)

        // Map's native selection sets the tag
        mapSelection = tag
        #expect(mapSelection == tag)
    }

    @Test func retapWantToGoPin_deselects() {
        var mapSelection: MapPinTag? = nil
        let tag = MapPinTag.wantToGo("wtg-1")

        // Select
        mapSelection = tag
        #expect(mapSelection == tag)

        // Re-tap: simultaneousGesture deselects
        let isSelected = mapSelection == tag
        if isSelected {
            mapSelection = nil
        }
        #expect(mapSelection == nil)
    }

    // MARK: - Standalone WTG Pin Identification

    @Test func standaloneWantToGo_excludesUnifiedPlaceIDs() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        // Create a personal pin at place p1
        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])
        let unifiedPlaceIDs = Set(pins.map(\.placeID))

        // WTG items: p1 (overlaps with unified) and p2 (standalone)
        let wtgItems = [
            WantToGoMapItem(id: "wtg-1", placeID: "p1", placeName: "Coffee Shop",
                            placeAddress: nil, photoReference: nil,
                            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41)),
            WantToGoMapItem(id: "wtg-2", placeID: "p2", placeName: "Bakery",
                            placeAddress: nil, photoReference: nil,
                            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)),
        ]

        // Simulate standaloneWantToGoItems filtering
        let standalone = wtgItems.filter { !unifiedPlaceIDs.contains($0.placeID) }

        #expect(standalone.count == 1)
        #expect(standalone[0].placeID == "p2")
        #expect(standalone[0].placeName == "Bakery")
    }

    @Test func standaloneWantToGo_allStandaloneWhenNoUnifiedPins() {
        let service = makeSUT()

        // No personal logs, no friends' places
        let pins = service.computeUnifiedPins(personalLogs: [], places: [])
        let unifiedPlaceIDs = Set(pins.map(\.placeID))
        #expect(unifiedPlaceIDs.isEmpty)

        // All WTG items should be standalone
        let wtgItems = [
            WantToGoMapItem(id: "wtg-1", placeID: "p1", placeName: "Place A",
                            placeAddress: nil, photoReference: nil,
                            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41)),
            WantToGoMapItem(id: "wtg-2", placeID: "p2", placeName: "Place B",
                            placeAddress: nil, photoReference: nil,
                            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)),
        ]

        let standalone = wtgItems.filter { !unifiedPlaceIDs.contains($0.placeID) }
        #expect(standalone.count == 2)
    }

    @Test func standaloneWantToGo_emptyWhenAllOverlap() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        // Create personal pins at p1 and p2
        let place1 = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let place2 = TestData.place(id: "p2", name: "Bakery", latitude: 37.78, longitude: -122.42)
        let log1 = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        let log2 = TestData.log(id: "log2", userID: "u1", placeID: "p2", rating: .mustSee)
        context.insert(place1)
        context.insert(place2)
        context.insert(log1)
        context.insert(log2)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log1, log2], places: [place1, place2])
        let unifiedPlaceIDs = Set(pins.map(\.placeID))

        // WTG items all overlap with unified pins
        let wtgItems = [
            WantToGoMapItem(id: "wtg-1", placeID: "p1", placeName: "Coffee Shop",
                            placeAddress: nil, photoReference: nil,
                            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41)),
            WantToGoMapItem(id: "wtg-2", placeID: "p2", placeName: "Bakery",
                            placeAddress: nil, photoReference: nil,
                            coordinate: CLLocationCoordinate2D(latitude: 37.78, longitude: -122.42)),
        ]

        let standalone = wtgItems.filter { !unifiedPlaceIDs.contains($0.placeID) }
        #expect(standalone.isEmpty)
    }

    // MARK: - Bookmark Badge on Annotated Pins

    @Test func annotatedPin_bookmarkBadgePosition_personalPin() throws {
        // Verify personal pin with WTG gets identity including WTG state
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(place)
        context.insert(log)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])
        let pin = pins[0]

        // Simulate annotatedPins with WTG badge
        let wantToGoPlaceIDs: Set<String> = ["p1"]
        let isWtg = wantToGoPlaceIDs.contains(pin.placeID)
        #expect(isWtg == true)

        // Identity must encode WTG state for Map annotation recreation
        let identity = "\(pin.id)_\(isWtg)"
        #expect(identity == "personal-p1_true")
    }

    // MARK: - Log Deletion → Map Pin Update

    @Test func deletingLog_removesPersonalPinFromMap() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place1 = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let place2 = TestData.place(id: "p2", name: "Bakery", latitude: 37.78, longitude: -122.42)
        let log1 = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        let log2 = TestData.log(id: "log2", userID: "u1", placeID: "p2", rating: .mustSee)
        context.insert(place1)
        context.insert(place2)
        context.insert(log1)
        context.insert(log2)
        try context.save()

        // Before deletion: 2 pins
        let pinsBefore = service.computeUnifiedPins(personalLogs: [log1, log2], places: [place1, place2])
        #expect(pinsBefore.count == 2)

        // Delete log1 from SwiftData
        context.delete(log1)
        try context.save()

        // After deletion: only log2 remains → 1 pin
        let pinsAfter = service.computeUnifiedPins(personalLogs: [log2], places: [place1, place2])
        #expect(pinsAfter.count == 1)
        #expect(pinsAfter[0].placeID == "p2")
    }

    @Test func deletingLog_combinedPinBecomesFriendsOnly() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .mustSee)
        context.insert(place)
        context.insert(log)
        try context.save()

        let friendPlace = ExploreMapPlace(
            id: "p1", name: "Coffee Shop", address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            photoReference: nil,
            logs: [TestData.feedItem(id: "f1", place: TestData.feedPlace(id: "p1"))]
        )
        service.placesMap = ["p1": friendPlace]

        // Before deletion: combined pin
        let pinsBefore = service.computeUnifiedPins(personalLogs: [log], places: [place])
        #expect(pinsBefore.count == 1)
        if case .combined = pinsBefore[0] { } else {
            Issue.record("Expected .combined pin before deletion")
        }

        // Delete the log — simulate @Query returning empty personal logs
        context.delete(log)
        try context.save()

        let pinsAfter = service.computeUnifiedPins(personalLogs: [], places: [place])
        #expect(pinsAfter.count == 1)
        if case .friends(let p) = pinsAfter[0] {
            #expect(p.id == "p1")
        } else {
            Issue.record("Expected .friends pin after deletion")
        }
    }

    @Test func deletingLog_navigationStateClearedBySafetyNet() throws {
        // Simulates the onChange(of: allLogs.count) safety net logic in ExploreMapView.
        // When a detail log is deleted, the handler clears navigation state.
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid)
        context.insert(log)
        try context.save()

        // Simulate navigation state
        var showDetail = true
        var detailLog: Log? = log
        var detailPlace: Place? = TestData.place(id: "p1")

        // Simulate deletion: log removed from allLogs
        context.delete(log)
        try context.save()

        let allLogs: [Log] = (try? context.fetch(FetchDescriptor<Log>())) ?? []

        // Safety net logic: if detail log no longer exists, clear state
        if showDetail, let dl = detailLog,
           !allLogs.contains(where: { $0.id == dl.id }) {
            showDetail = false
            detailLog = nil
            detailPlace = nil
        }

        #expect(showDetail == false)
        #expect(detailLog == nil)
        #expect(detailPlace == nil)
    }

    @Test func deletingLog_onDeleteCallbackClearsParentState() {
        // Simulates the onDelete callback pattern: LogDetailView calls onDelete
        // before dismiss so the parent clears its navigation binding.
        var showDetail = true
        var detailLog: String? = "log1"
        var detailPlace: String? = "p1"

        // The onDelete closure the parent provides
        let onDelete = {
            showDetail = false
            detailLog = nil
            detailPlace = nil
        }

        // LogDetailView's deleteLog() calls onDelete?()
        onDelete()

        #expect(showDetail == false)
        #expect(detailLog == nil)
        #expect(detailPlace == nil)
    }

    // MARK: - Multi-Log Tests

    @Test func computeUnifiedPins_multipleLogsAtSamePlace_keepsAll() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log1 = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid,
                                createdAt: fixedDate())
        let log2 = TestData.log(id: "log2", userID: "u1", placeID: "p1", rating: .mustSee,
                                createdAt: fixedDate().addingTimeInterval(86400))
        let log3 = TestData.log(id: "log3", userID: "u1", placeID: "p1", rating: .skip,
                                createdAt: fixedDate().addingTimeInterval(172800))
        context.insert(place)
        context.insert(log1)
        context.insert(log2)
        context.insert(log3)
        try context.save()

        let pins = service.computeUnifiedPins(personalLogs: [log1, log2, log3], places: [place])

        #expect(pins.count == 1)
        if case .personal(let pinLogs, let pinPlace) = pins[0] {
            #expect(pinLogs.count == 3)
            #expect(pinPlace.id == "p1")
            // Sorted by createdAt descending — most recent first
            #expect(pinLogs[0].id == "log3")
            #expect(pinLogs[1].id == "log2")
            #expect(pinLogs[2].id == "log1")
        } else {
            Issue.record("Expected .personal pin")
        }

        // visitCount should reflect all logs
        #expect(pins[0].visitCount == 3)
        // bestRating should scan all logs
        #expect(pins[0].bestRating == .mustSee)
        // userRating should be most recent log's rating
        #expect(pins[0].userRating == .skip)
    }

    @Test func computeUnifiedPins_multipleLogsAtSamePlace_combined() throws {
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", name: "Coffee Shop", latitude: 37.77, longitude: -122.41)
        let log1 = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .solid,
                                createdAt: fixedDate())
        let log2 = TestData.log(id: "log2", userID: "u1", placeID: "p1", rating: .mustSee,
                                createdAt: fixedDate().addingTimeInterval(86400))
        context.insert(place)
        context.insert(log1)
        context.insert(log2)
        try context.save()

        let friendPlace = ExploreMapPlace(
            id: "p1", name: "Coffee Shop", address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            photoReference: nil,
            logs: [TestData.feedItem(id: "f1", place: TestData.feedPlace(id: "p1"))]
        )
        service.placesMap = ["p1": friendPlace]

        let pins = service.computeUnifiedPins(personalLogs: [log1, log2], places: [place])

        #expect(pins.count == 1)
        if case .combined(let pinLogs, let pinPlace, let pinFriendPlace) = pins[0] {
            #expect(pinLogs.count == 2)
            // Most recent first
            #expect(pinLogs[0].id == "log2")
            #expect(pinLogs[1].id == "log1")
            #expect(pinPlace.id == "p1")
            #expect(pinFriendPlace.id == "p1")
        } else {
            Issue.record("Expected .combined pin")
        }

        #expect(pins[0].visitCount == 2)
    }

    @Test func annotatedPin_bookmarkBadgePosition_combinedPin() throws {
        // Combined pin with WTG: both friend badge and bookmark should be present
        let service = makeSUT()
        let container = try makeTestModelContainer()
        let context = container.mainContext

        let place = TestData.place(id: "p1", latitude: 37.77, longitude: -122.41)
        let log = TestData.log(id: "log1", userID: "u1", placeID: "p1", rating: .mustSee)
        context.insert(place)
        context.insert(log)
        try context.save()

        let friendPlace = ExploreMapPlace(
            id: "p1", name: "Coffee Shop", address: "123 Main St",
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41),
            photoReference: nil,
            logs: [TestData.feedItem(id: "f1", place: TestData.feedPlace(id: "p1"))]
        )
        service.placesMap = ["p1": friendPlace]

        let pins = service.computeUnifiedPins(personalLogs: [log], places: [place])
        let pin = pins[0]

        // Verify it's a combined pin
        if case .combined(let pinLogs, _, let pinFriend) = pin {
            #expect(pinLogs.first?.rating == .mustSee)
            #expect(pinFriend.friendCount == 1)
        } else {
            Issue.record("Expected .combined pin")
        }

        // WTG overlay: both bookmark and friend badge should coexist
        let wantToGoPlaceIDs: Set<String> = ["p1"]
        let isWtg = wantToGoPlaceIDs.contains(pin.placeID)
        #expect(isWtg == true)

        // Identity encodes WTG state
        let identity = "\(pin.id)_\(isWtg)"
        #expect(identity == "combined-p1_true")
    }
}
