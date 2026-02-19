import Testing
import Foundation
@testable import sonder

@Suite("ProfileStatsService")
struct ProfileStatsServiceTests {

    // MARK: - Taste DNA

    @Test("All restaurant logs → food = 1.0, others near 0")
    func tasteDNA_allFood() {
        let place = TestData.place(id: "p1", types: ["restaurant"])
        let logs = (0..<5).map { i in
            TestData.log(id: "log-\(i)", placeID: "p1", rating: .solid, createdAt: fixedDate())
        }
        let placeMap = ["p1": place]

        let dna = ProfileStatsService.computeTasteDNA(logs: logs, placeMap: placeMap)

        #expect(dna.food == 1.0)
        #expect(dna.coffee == 0.0)
        #expect(dna.nightlife == 0.0)
        #expect(dna.outdoors == 0.0)
        #expect(dna.shopping == 0.0)
        #expect(dna.attractions == 0.0)
    }

    @Test("Mixed categories → proportional values")
    func tasteDNA_mixed() {
        let restaurant = TestData.place(id: "p1", types: ["restaurant"])
        let cafe = TestData.place(id: "p2", types: ["cafe"])
        let logs = [
            TestData.log(id: "l1", placeID: "p1", rating: .solid, createdAt: fixedDate()),
            TestData.log(id: "l2", placeID: "p1", rating: .solid, createdAt: fixedDate()),
            TestData.log(id: "l3", placeID: "p2", rating: .solid, createdAt: fixedDate()),
        ]
        let placeMap = ["p1": restaurant, "p2": cafe]

        let dna = ProfileStatsService.computeTasteDNA(logs: logs, placeMap: placeMap)

        // Food: 2 logs * weight 2 = 4, Coffee: 1 log * weight 2 = 2 → food=1.0, coffee=0.5
        #expect(dna.food == 1.0)
        #expect(dna.coffee == 0.5)
    }

    @Test("Must-See weighs 3x, Solid 2x, Skip 1x")
    func tasteDNA_ratingWeights() {
        let restaurant = TestData.place(id: "p1", types: ["restaurant"])
        let cafe = TestData.place(id: "p2", types: ["cafe"])
        let logs = [
            TestData.log(id: "l1", placeID: "p1", rating: .skip, createdAt: fixedDate()),   // weight 1
            TestData.log(id: "l2", placeID: "p2", rating: .mustSee, createdAt: fixedDate()), // weight 3
        ]
        let placeMap = ["p1": restaurant, "p2": cafe]

        let dna = ProfileStatsService.computeTasteDNA(logs: logs, placeMap: placeMap)

        // Food: 1*1=1, Coffee: 1*3=3 → coffee=1.0, food=1/3
        #expect(dna.coffee == 1.0)
        #expect(abs(dna.food - 1.0 / 3.0) < 0.001)
    }

    @Test("Empty logs → all zero")
    func tasteDNA_empty() {
        let dna = ProfileStatsService.computeTasteDNA(logs: [], placeMap: [:])
        #expect(dna.isEmpty)
    }

    // MARK: - Archetype

    @Test(">60% food → Foodie")
    func archetype_foodie() {
        let dna = TasteDNA(food: 0.8, coffee: 0.1, nightlife: 0.0, outdoors: 0.0, shopping: 0.0, attractions: 0.1)
        let archetype = ProfileStatsService.classifyArchetype(tasteDNA: dna, logs: [TestData.log()], placeMap: [:])
        #expect(archetype == .foodie)
    }

    @Test(">60% attractions → Culture Vulture")
    func archetype_cultureVulture() {
        let dna = TasteDNA(food: 0.1, coffee: 0.0, nightlife: 0.0, outdoors: 0.0, shopping: 0.0, attractions: 0.8)
        let archetype = ProfileStatsService.classifyArchetype(tasteDNA: dna, logs: [TestData.log()], placeMap: [:])
        #expect(archetype == .cultureVulture)
    }

    @Test(">60% nightlife → Night Owl")
    func archetype_nightOwl() {
        let dna = TasteDNA(food: 0.1, coffee: 0.0, nightlife: 0.8, outdoors: 0.0, shopping: 0.0, attractions: 0.0)
        let archetype = ProfileStatsService.classifyArchetype(tasteDNA: dna, logs: [TestData.log()], placeMap: [:])
        #expect(archetype == .nightOwl)
    }

    @Test("High cities + low revisits → Wanderer")
    func archetype_wanderer() {
        // 4 unique places in 4 different cities, no revisits
        let places = [
            TestData.place(id: "p1", address: "123 St, CityA, StateA, USA"),
            TestData.place(id: "p2", address: "456 Ave, CityB, StateB, USA"),
            TestData.place(id: "p3", address: "789 Blvd, CityC, StateC, USA"),
            TestData.place(id: "p4", address: "321 Rd, CityD, StateD, USA"),
        ]
        let logs = places.map { TestData.log(id: "l-\($0.id)", placeID: $0.id, createdAt: fixedDate()) }
        let placeMap = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let dna = TasteDNA(food: 0.3, coffee: 0.3, nightlife: 0.2, outdoors: 0.1, shopping: 0.0, attractions: 0.1)

        let archetype = ProfileStatsService.classifyArchetype(tasteDNA: dna, logs: logs, placeMap: placeMap)
        #expect(archetype == .wanderer)
    }

    @Test("High notes/tags → Curator")
    func archetype_curator() {
        let logs = [
            TestData.log(id: "l1", note: "Amazing view", tags: ["scenic", "must-go"], createdAt: fixedDate()),
            TestData.log(id: "l2", note: "Best coffee", tags: ["coffee"], createdAt: fixedDate()),
            TestData.log(id: "l3", note: "Great food", tags: ["restaurant"], createdAt: fixedDate()),
        ]
        let dna = TasteDNA(food: 0.3, coffee: 0.3, nightlife: 0.2, outdoors: 0.1, shopping: 0.0, attractions: 0.1)

        let archetype = ProfileStatsService.classifyArchetype(tasteDNA: dna, logs: logs, placeMap: [:])
        #expect(archetype == .curator)
    }

    @Test("Default → Explorer")
    func archetype_default() {
        let logs = [TestData.log(id: "l1", createdAt: fixedDate())]
        let dna = TasteDNA(food: 0.3, coffee: 0.3, nightlife: 0.2, outdoors: 0.1, shopping: 0.0, attractions: 0.1)

        let archetype = ProfileStatsService.classifyArchetype(tasteDNA: dna, logs: logs, placeMap: [:])
        #expect(archetype == .explorer)
    }

    // MARK: - Rating Philosophy

    @Test(">60% must-see → generous")
    func philosophy_generous() {
        let logs = [
            TestData.log(id: "l1", rating: .mustSee, createdAt: fixedDate()),
            TestData.log(id: "l2", rating: .mustSee, createdAt: fixedDate()),
            TestData.log(id: "l3", rating: .mustSee, createdAt: fixedDate()),
            TestData.log(id: "l4", rating: .solid, createdAt: fixedDate()),
        ]
        let dist = ProfileStatsService.computeRatingDistribution(logs: logs)
        #expect(dist.philosophy.contains("generous"))
    }

    @Test(">40% skip → high standards")
    func philosophy_highStandards() {
        let logs = [
            TestData.log(id: "l1", rating: .skip, createdAt: fixedDate()),
            TestData.log(id: "l2", rating: .skip, createdAt: fixedDate()),
            TestData.log(id: "l3", rating: .skip, createdAt: fixedDate()),
            TestData.log(id: "l4", rating: .solid, createdAt: fixedDate()),
            TestData.log(id: "l5", rating: .mustSee, createdAt: fixedDate()),
        ]
        let dist = ProfileStatsService.computeRatingDistribution(logs: logs)
        #expect(dist.philosophy.contains("high standards"))
    }

    @Test("Equal thirds → balanced")
    func philosophy_balanced() {
        let logs = [
            TestData.log(id: "l1", rating: .skip, createdAt: fixedDate()),
            TestData.log(id: "l2", rating: .solid, createdAt: fixedDate()),
            TestData.log(id: "l3", rating: .mustSee, createdAt: fixedDate()),
        ]
        let dist = ProfileStatsService.computeRatingDistribution(logs: logs)
        #expect(dist.philosophy.contains("balanced"))
    }

    // MARK: - Category Breakdown

    @Test("Mixed places → correct breakdown")
    func categoryBreakdown_mixed() {
        let places = [
            TestData.place(id: "p1", types: ["restaurant"]),
            TestData.place(id: "p2", types: ["cafe"]),
            TestData.place(id: "p3", types: ["restaurant"]),
        ]
        let placeMap = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let logs = [
            TestData.log(id: "l1", placeID: "p1", createdAt: fixedDate()),
            TestData.log(id: "l2", placeID: "p2", createdAt: fixedDate()),
            TestData.log(id: "l3", placeID: "p3", createdAt: fixedDate()),
        ]

        let breakdown = ProfileStatsService.computeCategoryBreakdown(logs: logs, placeMap: placeMap)

        #expect(breakdown.count == 2)
        let food = breakdown.first { $0.category == "Food" }
        let coffee = breakdown.first { $0.category == "Coffee" }
        #expect(food?.count == 2)
        #expect(coffee?.count == 1)
        #expect(abs((food?.percentage ?? 0) - 2.0/3.0) < 0.001)
    }

    // MARK: - Full Compute

    @Test("Full compute returns valid ProfileStats")
    func fullCompute() {
        let places = [
            TestData.place(id: "p1", name: "Sushi Place",
                          address: "A, New York, NY, USA",
                          latitude: 40.7128, longitude: -74.0060, types: ["restaurant"]),
            TestData.place(id: "p2", name: "Coffee Shop",
                          address: "B, Los Angeles, CA, USA",
                          latitude: 34.0522, longitude: -118.2437, types: ["cafe"]),
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let logs = [
            TestData.log(id: "l1", placeID: "p1", rating: .mustSee, note: "Amazing", tags: ["sushi"],
                        createdAt: today),
            TestData.log(id: "l2", placeID: "p2", rating: .solid,
                        createdAt: calendar.date(byAdding: .day, value: -1, to: today)!),
        ]

        let stats = ProfileStatsService.compute(logs: logs, places: places)

        #expect(stats.totalLogs == 2)
        #expect(!stats.tasteDNA.isEmpty)
        #expect(stats.ratingDistribution.total == 2)
        #expect(stats.ratingDistribution.mustSeeCount == 1)
        #expect(stats.ratingDistribution.solidCount == 1)
    }
}
