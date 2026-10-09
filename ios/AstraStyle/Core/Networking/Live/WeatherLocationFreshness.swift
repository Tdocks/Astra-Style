import CoreLocation
import Foundation

enum WeatherLocationFreshness {
    static let maximumAge: TimeInterval = 15 * 60
    static let maximumFutureSkew: TimeInterval = 5 * 60
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 5_000

    static func isUsable(_ location: CLLocation, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return age <= maximumAge
            && age >= -maximumFutureSkew
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
    }
}
