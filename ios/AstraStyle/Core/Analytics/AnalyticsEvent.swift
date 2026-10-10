//
//  AnalyticsEvent.swift
//  AstraStyle
//
//  Every analytics event name from spec §18, typed as an enum with
//  associated properties so a call site can never typo an event name or
//  omit a property the event is defined to carry. `AnalyticsClient`
//  (AnalyticsClient.swift) is the only thing allowed to turn this into a
//  wire event.
//

import Foundation

public enum AnalyticsEvent: Sendable {
    case onboardingStarted
    case onboardingCompleted
    case closetItemAdded(category: ClothingCategory, source: AddSource)
    case scanCorrected(fieldsCorrectedCount: Int)
    case outfitGenerated(count: Int, occasionID: UUID?)
    case outfitMarkedWorn(outfitID: UUID)
    case outfitRejected(outfitID: UUID, reasonTags: [String])
    case kyraPromptSent(intent: KyraIntent?)
    case productEvaluated(verdict: KyraVerdict)
    case affiliateLinkOpened(retailer: String)
    case studioGenerationStarted(preset: StudioPromptPreset?)
    case studioGenerationCompleted(succeeded: Bool)
    case paywallViewed(context: PaywallContext)
    case subscriptionStarted(productID: String)
    case subscriptionRenewed(productID: String)
    case subscriptionCancelled(productID: String)

    public enum AddSource: String, Sendable {
        case scan
        case manualEntry = "manual_entry"
        case batchScan = "batch_scan"
    }

    private enum AnalyticsRetailer: String {
        case alden
        case drakes
        case hodinkee
        case toddSnyder = "todd_snyder"

        static func canonicalID(for value: String) -> String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "alden": self.alden.rawValue
            case "drake's", "drakes": self.drakes.rawValue
            case "hodinkee": self.hodinkee.rawValue
            case "todd snyder", "todd_snyder": self.toddSnyder.rawValue
            default: "other"
            }
        }
    }

    /// The wire event name, matching spec §18's naming exactly (snake_case,
    /// `_started`/`_completed` pairs preserved verbatim).
    public var name: String {
        switch self {
        case .onboardingStarted: "onboarding_started"
        case .onboardingCompleted: "onboarding_completed"
        case .closetItemAdded: "closet_item_added"
        case .scanCorrected: "scan_corrected"
        case .outfitGenerated: "outfit_generated"
        case .outfitMarkedWorn: "outfit_marked_worn"
        case .outfitRejected: "outfit_rejected"
        case .kyraPromptSent: "kyra_prompt_sent"
        case .productEvaluated: "product_evaluated"
        case .affiliateLinkOpened: "affiliate_link_opened"
        case .studioGenerationStarted: "studio_generation_started"
        case .studioGenerationCompleted: "studio_generation_completed"
        case .paywallViewed: "paywall_viewed"
        case .subscriptionStarted: "subscription_started"
        case .subscriptionRenewed: "subscription_renewed"
        case .subscriptionCancelled: "subscription_cancelled"
        }
    }

    /// Non-sensitive properties to attach. Per spec §18's privacy guard,
    /// this NEVER includes image bytes/paths or free-text (Kyra prompts,
    /// style feedback free text, product URLs pasted by the user) — only
    /// enum/count/id-shaped values that carry no personal content.
    public var properties: [String: AstraJSONValue] {
        switch self {
        case .onboardingStarted, .onboardingCompleted:
            return [:]
        case .closetItemAdded(let category, let source):
            return ["category": .string(category.rawValue), "source": .string(source.rawValue)]
        case .scanCorrected(let fieldsCorrectedCount):
            return ["fields_corrected_count": .number(Double(fieldsCorrectedCount))]
        case .outfitGenerated(let count, let occasionID):
            return ["count": .number(Double(count)), "occasion_id": occasionID.map { .string($0.uuidString) } ?? .null]
        case .outfitMarkedWorn(let outfitID):
            return ["outfit_id": .string(outfitID.uuidString)]
        case .outfitRejected(let outfitID, let reasonTags):
            let allowedTags = Set(StyleFeedbackSignal.allCases.map(\.rawValue))
            let safeTags = reasonTags
                .filter { allowedTags.contains($0) }
                .reduce(into: [String]()) { result, tag in
                    if !result.contains(tag) { result.append(tag) }
                }
            return ["outfit_id": .string(outfitID.uuidString), "reason_tags": .array(safeTags.map(AstraJSONValue.string))]
        case .kyraPromptSent(let intent):
            return ["intent": intent.map { .string($0.rawValue) } ?? .null]
        case .productEvaluated(let verdict):
            return ["verdict": .string(verdict.rawValue)]
        case .affiliateLinkOpened(let retailer):
            return ["retailer": .string(AnalyticsRetailer.canonicalID(for: retailer))]
        case .studioGenerationStarted(let preset):
            return ["preset": preset.map { .string($0.rawValue) } ?? .null]
        case .studioGenerationCompleted(let succeeded):
            return ["succeeded": .bool(succeeded)]
        case .paywallViewed(let context):
            return ["context": .string(context.rawValue)]
        case .subscriptionStarted(let productID), .subscriptionRenewed(let productID), .subscriptionCancelled(let productID):
            return ["product_id": .string(AstraProductID(rawValue: productID)?.rawValue ?? "other")]
        }
    }
}
