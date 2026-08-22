import Foundation
import Testing
@testable import AstraStyle

@Suite("App version label")
struct AstraAppVersionTests {
    @Test("Dogfood label is marketing version plus build")
    func displayLabelJoinsMarketingAndBuild() {
        let version = AstraAppVersion(marketing: "1.0.0", build: "2")
        #expect(version.displayLabel == "1.0.0 (2)")
    }
}
