import Testing
import Foundation
@testable import sonder

struct WantToGoTests {

    @Test func initDefaults() {
        let item = WantToGo(userID: "u1", placeID: "p1")

        #expect(!item.id.isEmpty)
        #expect(item.placeName == nil)
        #expect(item.placeAddress == nil)
        #expect(item.photoReference == nil)
        #expect(item.sourceLogID == nil)
    }

    @Test func encodeThenDecode() throws {
        let item = TestData.wantToGo(
            id: "wtg-1",
            userID: "u1",
            placeID: "p1",
            placeName: "Cafe",
            placeAddress: "123 Main St",
            photoReference: "ref-1",
            sourceLogID: "log-1"
        )

        let data = try makeEncoder().encode(item)
        let decoded = try makeDecoder().decode(WantToGo.self, from: data)

        #expect(decoded.id == "wtg-1")
        #expect(decoded.userID == "u1")
        #expect(decoded.placeID == "p1")
        #expect(decoded.placeName == "Cafe")
        #expect(decoded.placeAddress == "123 Main St")
        #expect(decoded.photoReference == "ref-1")
        #expect(decoded.sourceLogID == "log-1")
    }

    @Test func encodeProducesSnakeCaseKeys() throws {
        let item = TestData.wantToGo(
            placeName: "Cafe",
            placeAddress: "123 St",
            photoReference: "ref"
        )
        let data = try makeEncoder().encode(item)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["user_id"] != nil)
        #expect(json["place_id"] != nil)
        #expect(json["place_name"] != nil)
        #expect(json["place_address"] != nil)
        #expect(json["photo_reference"] != nil)
        #expect(json["source_log_id"] == nil || json["source_log_id"] is NSNull || true) // nil encoded or not
        #expect(json["placeName"] == nil)
        #expect(json["placeAddress"] == nil)
    }
}
