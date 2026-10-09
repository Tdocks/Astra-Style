import Foundation

public enum ProfileSnapshotValue: Sendable {
    case profile(Profile)
    case style(StyleProfile)
    case body(BodyProfile)
    case lifestyle(LifestyleProfile)
    case styleMissing(ownerID: UUID)
    case bodyMissing(ownerID: UUID)
    case lifestyleMissing(ownerID: UUID)

    public var ownerID: UUID {
        switch self {
        case .profile(let value): value.id
        case .style(let value): value.userID
        case .body(let value): value.userID
        case .lifestyle(let value): value.userID
        case .styleMissing(let ownerID), .bodyMissing(let ownerID), .lifestyleMissing(let ownerID): ownerID
        }
    }
}

public struct ProfileSnapshot: Sendable {
    public var profile: Profile?
    public var styleProfile: StyleProfile?
    public var bodyProfile: BodyProfile?
    public var lifestyleProfile: LifestyleProfile?
    public var profileFetched: Bool
    public var styleFetched: Bool
    public var bodyFetched: Bool
    public var lifestyleFetched: Bool
    public var pendingProfile: Bool
    public var pendingStyle: Bool
    public var pendingBody: Bool
    public var pendingLifestyle: Bool

    public init(
        profile: Profile? = nil,
        styleProfile: StyleProfile? = nil,
        bodyProfile: BodyProfile? = nil,
        lifestyleProfile: LifestyleProfile? = nil,
        profileFetched: Bool = false,
        styleFetched: Bool = false,
        bodyFetched: Bool = false,
        lifestyleFetched: Bool = false,
        pendingProfile: Bool = false,
        pendingStyle: Bool = false,
        pendingBody: Bool = false,
        pendingLifestyle: Bool = false
    ) {
        self.profile = profile
        self.styleProfile = styleProfile
        self.bodyProfile = bodyProfile
        self.lifestyleProfile = lifestyleProfile
        self.profileFetched = profileFetched
        self.styleFetched = styleFetched
        self.bodyFetched = bodyFetched
        self.lifestyleFetched = lifestyleFetched
        self.pendingProfile = pendingProfile
        self.pendingStyle = pendingStyle
        self.pendingBody = pendingBody
        self.pendingLifestyle = pendingLifestyle
    }

    public var isEmpty: Bool {
        !profileFetched && !styleFetched && !bodyFetched && !lifestyleFetched
    }

    public mutating func apply(_ value: ProfileSnapshotValue, pending: Bool) {
        switch value {
        case .profile(let value):
            profile = value
            profileFetched = true
            pendingProfile = pending
        case .style(let value):
            styleProfile = value
            styleFetched = true
            pendingStyle = pending
        case .body(let value):
            bodyProfile = value
            bodyFetched = true
            pendingBody = pending
        case .lifestyle(let value):
            lifestyleProfile = value
            lifestyleFetched = true
            pendingLifestyle = pending
        case .styleMissing:
            styleProfile = nil
            styleFetched = true
            pendingStyle = pending
        case .bodyMissing:
            bodyProfile = nil
            bodyFetched = true
            pendingBody = pending
        case .lifestyleMissing:
            lifestyleProfile = nil
            lifestyleFetched = true
            pendingLifestyle = pending
        }
    }
}

/// Durable, account-scoped projection of the four profile tables.
public protocol ProfileSnapshotCaching: Sendable {
    func snapshot(for ownerID: UUID) async throws -> ProfileSnapshot?
    func store(_ value: ProfileSnapshotValue, pendingSync: Bool) async throws
    /// Refreshes remote state while preserving any local edit still queued.
    func mergeRemote(_ value: ProfileSnapshotValue) async throws
    func removeAll(ownerID: UUID) async throws
}

public protocol ProfileCachePurging: Sendable {
    func purgeLocalProfileCache(ownerID: UUID) async throws
}

/// Lossless dates for profile snapshots and queued edits. Network JSON uses
/// ISO-8601 separately; persistent local data uses reference-second numbers
/// so subsecond timestamps survive a process restart exactly.
enum ProfileSnapshotCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            guard let date = wholeSeconds.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid saved profile date."
                )
            }
            return date
        }
        return decoder
    }
}

/// In-memory cache for previews and repository tests. Production injects the
/// SwiftData implementation from AppContainer.
public actor InMemoryProfileSnapshotCache: ProfileSnapshotCaching {
    private var snapshots: [UUID: ProfileSnapshot] = [:]

    public init() {}

    public func snapshot(for ownerID: UUID) async throws -> ProfileSnapshot? {
        snapshots[ownerID]
    }

    public func store(_ value: ProfileSnapshotValue, pendingSync: Bool) async throws {
        var snapshot = snapshots[value.ownerID] ?? ProfileSnapshot()
        snapshot.apply(value, pending: pendingSync)
        snapshots[value.ownerID] = snapshot
    }

    public func mergeRemote(_ value: ProfileSnapshotValue) async throws {
        var snapshot = snapshots[value.ownerID] ?? ProfileSnapshot()
        let pending: Bool
        switch value {
        case .profile: pending = snapshot.pendingProfile
        case .style, .styleMissing: pending = snapshot.pendingStyle
        case .body, .bodyMissing: pending = snapshot.pendingBody
        case .lifestyle, .lifestyleMissing: pending = snapshot.pendingLifestyle
        }
        if !pending { snapshot.apply(value, pending: false) }
        snapshots[value.ownerID] = snapshot
    }

    public func removeAll(ownerID: UUID) async throws {
        snapshots[ownerID] = nil
    }
}
