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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
