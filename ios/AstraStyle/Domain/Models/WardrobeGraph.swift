//
//  WardrobeGraph.swift
//  AstraStyle
//
//  Product picker at onboarding (ADR 0019). Not a Settings gender toggle.
//

import Foundation

public enum WardrobeGraph: String, Codable, CaseIterable, Sendable {
    case menswear3Role = "menswear_3_role"
    case womenswear

    public var requiredRoles: [ClothingCategory] {
        switch self {
        case .menswear3Role: [.top, .bottom, .shoes]
        case .womenswear: [.shoes]
        }
    }

    public func missingRoles(in counts: [ClothingCategory: Int]) -> [ClothingCategory] {
        switch self {
        case .menswear3Role:
            return requiredRoles.filter { (counts[$0] ?? 0) == 0 }
        case .womenswear:
            let hasDress = (counts[.dress] ?? 0) > 0
            let hasSeparates = (counts[.top] ?? 0) > 0 && ((counts[.bottom] ?? 0) + (counts[.skirt] ?? 0)) > 0
            let hasShoes = (counts[.shoes] ?? 0) > 0
            var missing: [ClothingCategory] = []
            if !hasDress && !hasSeparates {
                missing.append(.dress)
                if (counts[.top] ?? 0) == 0 { missing.append(.top) }
                if (counts[.bottom] ?? 0) == 0 && (counts[.skirt] ?? 0) == 0 { missing.append(.bottom) }
            }
            if !hasShoes { missing.append(.shoes) }
            return missing
        }
    }

    public var emptyClosetAdvice: String {
        switch self {
        case .menswear3Role:
            String(localized: "Photograph a piece you own. Wear This needs a top, bottom, and shoes — start with one.",
                   comment: "Home empty state, men's graph, closet empty")
        case .womenswear:
            String(localized: "Photograph a piece you own. Wear This needs a dress or a top and bottom, plus shoes — start with one.",
                   comment: "Home empty state, women's graph, closet empty")
        }
    }

    public var growingClosetAdvice: (Int, Int) -> String {
        { have, need in
            switch self {
            case .menswear3Role:
                String(localized: "\(have) of \(need) pieces in. Keep going — Wear This also needs a top, bottom, and shoes.",
                       comment: "Home empty state, men's graph, closet growing")
            case .womenswear:
                String(localized: "\(have) of \(need) pieces in. Keep going — Wear This needs a dress or a top and bottom, plus shoes.",
                       comment: "Home empty state, women's graph, closet growing")
            }
        }
    }
}
