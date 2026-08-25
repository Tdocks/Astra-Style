//
//  PaywallContext.swift
//  AstraStyle
//
//  Where the paywall was triggered from (spec §16). Lives in `Domain`
//  rather than `App` or `Core/Analytics` because both layers need it —
//  `AppRouter` uses it to route to the paywall modal, and
//  `AnalyticsEvent.paywallViewed` (Core/Analytics) uses it as the event's
//  property — and `Domain` is the one layer both are allowed to depend on.
//

import Foundation

public enum PaywallContext: String, Sendable {
    case onboarding
    case closetLimit
    case outfitGenerationLimit
    case kyraDailyLimit
    case studioQuota
    case settingsUpgrade
    case dailyBrief
    case pasteEvaluate
}
