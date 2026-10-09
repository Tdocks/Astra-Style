import Foundation

public struct ProfileOfflineMutation: Codable, Sendable {
    public enum Table: String, Codable, Sendable {
        case profile
        case style
        case body
        case lifestyle
    }

    public let ownerID: UUID
    public let table: Table
    public let updatedAtReferenceSeconds: Double
    public let payload: Data

    public init(ownerID: UUID, value: ProfileSnapshotValue) throws {
        guard value.ownerID == ownerID else {
            throw AstraError.auth("Profile changes belong to another account.")
        }
        self.ownerID = ownerID
        let encoder = ProfileSnapshotCoding.makeEncoder()
        switch value {
        case .profile(let profile):
            table = .profile
            updatedAtReferenceSeconds = profile.updatedAt.timeIntervalSinceReferenceDate
            payload = try encoder.encode(profile)
        case .style(let profile):
            table = .style
            updatedAtReferenceSeconds = profile.updatedAt.timeIntervalSinceReferenceDate
            payload = try encoder.encode(profile)
        case .body(let profile):
            table = .body
            updatedAtReferenceSeconds = profile.updatedAt.timeIntervalSinceReferenceDate
            payload = try encoder.encode(profile)
        case .lifestyle(let profile):
            table = .lifestyle
            updatedAtReferenceSeconds = profile.updatedAt.timeIntervalSinceReferenceDate
            payload = try encoder.encode(profile)
        case .styleMissing, .bodyMissing, .lifestyleMissing:
            throw AstraError.validation("An empty profile cannot be queued as an edit.")
        }
    }

    public func decodedValue() throws -> ProfileSnapshotValue {
        let decoder = ProfileSnapshotCoding.makeDecoder()
        let exactTimestamp = Date(timeIntervalSinceReferenceDate: updatedAtReferenceSeconds)
        let value: ProfileSnapshotValue
        switch table {
        case .profile:
            var profile = try decoder.decode(Profile.self, from: payload)
            profile.updatedAt = exactTimestamp
            value = .profile(profile)
        case .style:
            var profile = try decoder.decode(StyleProfile.self, from: payload)
            profile.updatedAt = exactTimestamp
            value = .style(profile)
        case .body:
            var profile = try decoder.decode(BodyProfile.self, from: payload)
            profile.updatedAt = exactTimestamp
            value = .body(profile)
        case .lifestyle:
            var profile = try decoder.decode(LifestyleProfile.self, from: payload)
            profile.updatedAt = exactTimestamp
            value = .lifestyle(profile)
        }
        guard value.ownerID == ownerID, updatedAtReferenceSeconds.isFinite else {
            throw AstraError.auth("A queued profile change belongs to another account.")
        }
        return value
    }

    public var updatedAt: Date {
        Date(timeIntervalSinceReferenceDate: updatedAtReferenceSeconds)
    }
}
