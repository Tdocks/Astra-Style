import Foundation

/// Shared bounded exponential backoff for generation, reopening and exports.
enum StudioPollingPolicy {
    static let initialDelay: Duration = .seconds(2)
    static let maximumDelay: Duration = .seconds(8)
    static let timeout: Duration = .seconds(180)

    static func nextDelay(after delay: Duration, maximum: Duration = maximumDelay) -> Duration {
        min(delay + delay, maximum)
    }
}
