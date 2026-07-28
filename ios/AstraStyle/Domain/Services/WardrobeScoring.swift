//
//  WardrobeScoring.swift
//  AstraStyle
//
//  Protocol surface for the Wardrobe Score composite (spec §10):
//  Versatility 25%, Fit confidence 15%, Occasion coverage 15%,
//  Color cohesion 10%, Wear utilization 15%, Condition 10%,
//  Redundancy control 10%. "Do not equate expensive clothing with a
//  higher score" — price never enters this computation.
//

import Foundation

public protocol WardrobeScoring: Sendable {
    func score(items: [ClosetItem], wears: [OutfitWear], outfits: [Outfit]) -> WardrobeScore
}

/// Reference weights for the local (offline-safe) implementation. The
/// server-side computation is authoritative for the value shown in
/// Profile (spec §6.22); this protocol exists so the Closet tab can show a
/// reasonable estimate without a network round trip, and so the formula is
/// unit-testable (spec §22 "Unit tests: Wardrobe score").
public enum WardrobeScoreWeights {
    public static let versatility = 0.25
    public static let fitConfidence = 0.15
    public static let occasionCoverage = 0.15
    public static let colorCohesion = 0.10
    public static let wearUtilization = 0.15
    public static let condition = 0.10
    public static let redundancyControl = 0.10
}
