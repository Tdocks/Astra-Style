//
//  AstraEndpoint.swift
//  AstraStyle
//
//  Typed enumeration of every Supabase Edge Function the client is allowed
//  to call (spec §14 "API / Edge Functions" — 16 endpoints, verbatim). The
//  iOS client talks only to these Edge Functions and never directly to a
//  model provider (spec §8).
//

import Foundation

public enum AstraEndpoint: Sendable, Equatable {
    case completeOnboarding
    case generateStyleDNA
    case analyzeClosetItem
    case batchAnalyzeCloset
    case generateOutfits
    case rankOutfits
    case generateDailyBrief
    case kyraRespond
    case extractProduct
    case evaluateProduct
    case generateStudio
    case studioStatus(id: UUID)
    case generatePacking
    case syncSubscriptions
    case appStoreWebhook
    case deleteAccount

    /// HTTP method for the endpoint.
    public var method: HTTPMethod {
        switch self {
        case .studioStatus:
            .get
        case .deleteAccount:
            .delete
        default:
            .post
        }
    }

    /// Path relative to the Edge Functions base URL
    /// (`{SUPABASE_URL}/functions/v1/`).
    public var path: String {
        switch self {
        case .completeOnboarding: "profile/complete-onboarding"
        case .generateStyleDNA: "style-dna/generate"
        case .analyzeClosetItem: "closet/analyze-item"
        case .batchAnalyzeCloset: "closet/batch-analyze"
        case .generateOutfits: "outfits/generate"
        case .rankOutfits: "outfits/rank"
        case .generateDailyBrief: "daily-brief/generate"
        case .kyraRespond: "kyra/respond"
        case .extractProduct: "products/extract"
        case .evaluateProduct: "products/evaluate"
        case .generateStudio: "studio/generate"
        case .studioStatus(let id): "studio/status/\(id.uuidString)"
        case .generatePacking: "packing/generate"
        case .syncSubscriptions: "subscriptions/sync"
        case .appStoreWebhook: "app-store/webhook"
        case .deleteAccount: "account"
        }
    }

    /// Every endpoint requires a valid JWT except the App Store server
    /// notification webhook, which authenticates via its own shared secret
    /// (spec §14 "Validate JWT" applies to user-initiated calls).
    public var requiresAuthentication: Bool {
        self != .appStoreWebhook
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}
