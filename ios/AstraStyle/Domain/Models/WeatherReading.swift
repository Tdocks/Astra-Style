import Foundation

/// A weather snapshot plus the local source needed to describe it honestly.
/// This wrapper is never encoded into an API request; the provider observation
/// timestamp remains on `snapshot` and the cache-source bit stays on device.
public struct WeatherReading: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case live
        case lastKnown
    }

    public let snapshot: WeatherSnapshot
    public let source: Source

    public init(snapshot: WeatherSnapshot, source: Source) {
        self.snapshot = snapshot
        self.source = source
    }

    public var isLastKnown: Bool { source == .lastKnown }
}
