import Testing
import CoreGraphics
@testable import sonder

@Suite("ScaleButtonStyle Tests")
struct ScaleButtonStyleTests {

    @Test("Default scale is 0.95")
    func defaultScale() {
        let style = ScaleButtonStyle()
        #expect(style.scale == 0.95)
    }

    @Test("Custom scale is respected")
    func customScale() {
        let style = ScaleButtonStyle(scale: 0.9)
        #expect(style.scale == 0.9)
    }

    @Test("Scale of 1.0 means no visual press effect")
    func noEffectScale() {
        let style = ScaleButtonStyle(scale: 1.0)
        #expect(style.scale == 1.0)
    }
}
