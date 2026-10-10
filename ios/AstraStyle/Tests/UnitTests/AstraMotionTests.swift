import Testing
@testable import AstraStyle

@Suite("Reduce Motion design-system behavior")
struct AstraMotionTests {
    @Test("Hero geometry falls back to opacity when Reduce Motion is enabled")
    func heroMotionPolicy() {
        #expect(AstraMotion.usesMatchedGeometry(reduceMotion: false))
        #expect(!AstraMotion.usesMatchedGeometry(reduceMotion: true))
    }

    @Test("Breathing loop is absent when Reduce Motion is enabled")
    func breathingMotionPolicy() {
        if case .some = AstraMotion.breathingAnimation(reduceMotion: false) {
            // The regular setting keeps the slow repeating animation.
        } else {
            Issue.record("Breathing should remain available when Reduce Motion is off")
        }

        if case .none = AstraMotion.breathingAnimation(reduceMotion: true) {
            // Reduce Motion presents a static state.
        } else {
            Issue.record("Reduce Motion must not create a breathing animation")
        }
    }

    @Test("Outfit paging spring is omitted when Reduce Motion is enabled")
    func outfitPagingMotionPolicy() {
        if case .some = AstraMotion.outfitPagingAnimation(reduceMotion: false) {
            // Paging uses the settling spring when motion is allowed.
        } else {
            Issue.record("Outfit paging should animate when Reduce Motion is off")
        }

        if case .none = AstraMotion.outfitPagingAnimation(reduceMotion: true) {
            // Reduce Motion switches to an immediate state change.
        } else {
            Issue.record("Reduce Motion must disable outfit paging interpolation")
        }
    }
}
