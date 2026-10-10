import Foundation
import Testing
@testable import AstraStyle

@Suite("Studio bounded polling")
struct StudioPollingPolicyTests {
    @Test("Production polling starts at two seconds and caps at eight")
    func backoffIsBounded() {
        var delay = StudioPollingPolicy.initialDelay
        var values: [Duration] = []
        for _ in 0..<5 {
            values.append(delay)
            delay = StudioPollingPolicy.nextDelay(after: delay)
        }
        #expect(values == [.seconds(2), .seconds(4), .seconds(8), .seconds(8), .seconds(8)])
        #expect(StudioPollingPolicy.timeout == .seconds(180))
    }

    @Test("An injected smaller maximum is respected")
    func honorsInjectedMaximum() {
        #expect(StudioPollingPolicy.nextDelay(after: .seconds(2), maximum: .seconds(3)) == .seconds(3))
    }
}
