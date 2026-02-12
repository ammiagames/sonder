import Testing
import Foundation
@testable import sonder

struct RecentSearchTests {

    @Test func initDefaults() {
        let before = Date()
        let search = RecentSearch(placeId: "p1", name: "Cafe", address: "123 St")
        let after = Date()

        #expect(search.searchedAt >= before)
        #expect(search.searchedAt <= after)
    }

    @Test func placeIdIsStored() {
        let search = TestData.recentSearch(placeId: "unique-place-id")

        #expect(search.placeId == "unique-place-id")
        #expect(search.name == "Test Place")
        #expect(search.address == "123 Test St")
    }
}
