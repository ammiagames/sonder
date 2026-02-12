import Testing
import Foundation
@testable import sonder

struct WantToGoWithPlaceTests {

    @Test func idDelegation() {
        let wantToGo = TestData.wantToGo(id: "wtg-42")
        let place = TestData.feedPlace()
        let item = WantToGoWithPlace(wantToGo: wantToGo, place: place)

        #expect(item.id == "wtg-42")
    }

    @Test func createdAtDelegation() {
        let date = fixedDate()
        let wantToGo = TestData.wantToGo(createdAt: date)
        let place = TestData.feedPlace()
        let item = WantToGoWithPlace(wantToGo: wantToGo, place: place)

        #expect(item.createdAt == date)
    }

    @Test func sourceUserCanBeNil() {
        let wantToGo = TestData.wantToGo()
        let place = TestData.feedPlace()
        let item = WantToGoWithPlace(wantToGo: wantToGo, place: place)

        #expect(item.sourceUser == nil)
    }
}
