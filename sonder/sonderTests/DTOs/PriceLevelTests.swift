import Testing
import Foundation
@testable import sonder

struct PriceLevelTests {

    @Test func rawValues() {
        #expect(PriceLevel.free.rawValue == "PRICE_LEVEL_FREE")
        #expect(PriceLevel.inexpensive.rawValue == "PRICE_LEVEL_INEXPENSIVE")
        #expect(PriceLevel.moderate.rawValue == "PRICE_LEVEL_MODERATE")
        #expect(PriceLevel.expensive.rawValue == "PRICE_LEVEL_EXPENSIVE")
        #expect(PriceLevel.veryExpensive.rawValue == "PRICE_LEVEL_VERY_EXPENSIVE")
    }

    @Test func displayStrings() {
        #expect(PriceLevel.free.displayString == "Free")
        #expect(PriceLevel.inexpensive.displayString == "$")
        #expect(PriceLevel.moderate.displayString == "$$")
        #expect(PriceLevel.expensive.displayString == "$$$")
        #expect(PriceLevel.veryExpensive.displayString == "$$$$")
    }

    @Test func codableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for level in [PriceLevel.free, .inexpensive, .moderate, .expensive, .veryExpensive] {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(PriceLevel.self, from: data)
            #expect(decoded == level)
        }
    }
}
