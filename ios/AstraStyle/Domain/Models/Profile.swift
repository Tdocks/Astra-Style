//
//  Profile.swift
//  AstraStyle
//
//  Maps `profiles` (spec §9).
//

import Foundation

public struct Profile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String?
    public var avatarURL: URL?
    public var locationName: String?
    public var timezone: String?
    public var units: UnitsPreference
    public var theme: ThemePreference
    public var onboardingCompletedAt: Date?
    public var subscriptionTier: SubscriptionTier
    public var wardrobeGraph: WardrobeGraph
    public var referralCode: String?
    public var referredBy: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        displayName: String? = nil,
        avatarURL: URL? = nil,
        locationName: String? = nil,
        timezone: String? = nil,
        units: UnitsPreference = .imperial,
        theme: ThemePreference = .dark,
        onboardingCompletedAt: Date? = nil,
        subscriptionTier: SubscriptionTier = .free,
        wardrobeGraph: WardrobeGraph = .menswear3Role,
        referralCode: String? = nil,
        referredBy: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.locationName = locationName
        self.timezone = timezone
        self.units = units
        self.theme = theme
        self.onboardingCompletedAt = onboardingCompletedAt
        self.subscriptionTier = subscriptionTier
        self.wardrobeGraph = wardrobeGraph
        self.referralCode = referralCode
        self.referredBy = referredBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case locationName = "location_name"
        case timezone
        case units
        case theme
        case onboardingCompletedAt = "onboarding_completed_at"
        case subscriptionTier = "subscription_tier"
        case wardrobeGraph = "wardrobe_graph"
        case referralCode = "referral_code"
        case referredBy = "referred_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        units = try container.decodeIfPresent(UnitsPreference.self, forKey: .units) ?? .imperial
        theme = try container.decodeIfPresent(ThemePreference.self, forKey: .theme) ?? .dark
        onboardingCompletedAt = try container.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        subscriptionTier = try container.decodeIfPresent(SubscriptionTier.self, forKey: .subscriptionTier) ?? .free
        wardrobeGraph = try container.decodeIfPresent(WardrobeGraph.self, forKey: .wardrobeGraph) ?? .menswear3Role
        referralCode = try container.decodeIfPresent(String.self, forKey: .referralCode)
        referredBy = try container.decodeIfPresent(UUID.self, forKey: .referredBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encode(units, forKey: .units)
        try container.encode(theme, forKey: .theme)
        try container.encodeIfPresent(onboardingCompletedAt, forKey: .onboardingCompletedAt)
        try container.encode(subscriptionTier, forKey: .subscriptionTier)
        try container.encode(wardrobeGraph, forKey: .wardrobeGraph)
        try container.encodeIfPresent(referralCode, forKey: .referralCode)
        try container.encodeIfPresent(referredBy, forKey: .referredBy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    /// The first-name-only greeting used by Kyra's Daily Brief header
    /// (spec §6.11 "Good morning, [Name]."). Falls back gracefully when no
    /// display name has been set yet.
    public var greetingName: String {
        guard let displayName, !displayName.isEmpty else {
            return String(localized: "there", comment: "Fallback name when no display name is set")
        }
        return displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}
