//
//  Occasion.swift
//  AstraStyle
//
//  Maps `occasions` (spec §9). Either synced from EventKit (spec §7
//  "Calendar: when enabling occasion-aware recommendations") or entered
//  manually via the "Add a planned occasion" global action (spec §4).
//

import Foundation

public struct Occasion: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var userID: UUID
    public var title: String
    public var startsAt: Date
    public var endsAt: Date?
    public var location: String?
    public var dressCode: DressCode?
    public var source: OccasionSource
    public var calendarEventIdentifier: String?

    public init(
        id: UUID,
        userID: UUID,
        title: String,
        startsAt: Date,
        endsAt: Date? = nil,
        location: String? = nil,
        dressCode: DressCode? = nil,
        source: OccasionSource = .manual,
        calendarEventIdentifier: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.location = location
        self.dressCode = dressCode
        self.source = source
        self.calendarEventIdentifier = calendarEventIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case location
        case dressCode = "dress_code"
        case source
        case calendarEventIdentifier = "calendar_event_identifier"
    }
}
