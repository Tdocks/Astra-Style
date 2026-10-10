import Foundation
import Testing
@testable import AstraStyle

@Suite("Analytics event privacy contract")
struct AnalyticsEventPrivacyTests {
    private struct Scenario {
        let event: AnalyticsEvent
        let expectedName: String
        let expectedKeys: Set<String>
    }

    @Test("Every spec event has a fixed name and an allowlisted shallow payload")
    func eventPayloadsStayNonSensitive() throws {
        let id = try #require(UUID(uuidString: "B97AA0BB-68B4-4E3A-BFB8-71A2A9D76365"))
        let events: [Scenario] = [
            Scenario(event: .onboardingStarted, expectedName: "onboarding_started", expectedKeys: []),
            Scenario(event: .onboardingCompleted, expectedName: "onboarding_completed", expectedKeys: []),
            Scenario(event: .closetItemAdded(category: .top, source: .manualEntry), expectedName: "closet_item_added", expectedKeys: ["category", "source"]),
            Scenario(event: .scanCorrected(fieldsCorrectedCount: 2), expectedName: "scan_corrected", expectedKeys: ["fields_corrected_count"]),
            Scenario(event: .outfitGenerated(count: 3, occasionID: id), expectedName: "outfit_generated", expectedKeys: ["count", "occasion_id"]),
            Scenario(event: .outfitMarkedWorn(outfitID: id), expectedName: "outfit_marked_worn", expectedKeys: ["outfit_id"]),
            Scenario(event: .outfitRejected(outfitID: id, reasonTags: [StyleFeedbackSignal.badFit.rawValue]), expectedName: "outfit_rejected", expectedKeys: ["outfit_id", "reason_tags"]),
            Scenario(event: .kyraPromptSent(intent: .dailyOutfit), expectedName: "kyra_prompt_sent", expectedKeys: ["intent"]),
            Scenario(event: .productEvaluated(verdict: .consider), expectedName: "product_evaluated", expectedKeys: ["verdict"]),
            Scenario(event: .affiliateLinkOpened(retailer: "Todd Snyder"), expectedName: "affiliate_link_opened", expectedKeys: ["retailer"]),
            Scenario(event: .studioGenerationStarted(preset: .smartCasual), expectedName: "studio_generation_started", expectedKeys: ["preset"]),
            Scenario(event: .studioGenerationCompleted(succeeded: true), expectedName: "studio_generation_completed", expectedKeys: ["succeeded"]),
            Scenario(event: .paywallViewed(context: .onboarding), expectedName: "paywall_viewed", expectedKeys: ["context"]),
            Scenario(event: .subscriptionStarted(productID: AstraProductID.monthly.rawValue), expectedName: "subscription_started", expectedKeys: ["product_id"]),
            Scenario(event: .subscriptionRenewed(productID: AstraProductID.annual.rawValue), expectedName: "subscription_renewed", expectedKeys: ["product_id"]),
            Scenario(event: .subscriptionCancelled(productID: AstraProductID.monthly.rawValue), expectedName: "subscription_cancelled", expectedKeys: ["product_id"])
        ]

        #expect(events.count == 16)
        let deniedKeys: Set<String> = [
            "image", "image_url", "image_path", "storage_path", "prompt", "raw_prompt",
            "message", "free_text", "body", "description", "email", "location", "coordinates"
        ]

        for scenario in events {
            let event = scenario.event
            #expect(event.name == scenario.expectedName)
            #expect(Set(event.properties.keys) == scenario.expectedKeys)
            #expect(Set(event.properties.keys).isDisjoint(with: deniedKeys))

            for value in event.properties.values {
                try assertShallowNonSensitive(value)
            }

            let queued = QueuedAnalyticsEvent(userID: id, event: event)
            let data = try JSONEncoder().encode(queued)
            let wire = try #require(String(data: data, encoding: .utf8))
            #expect(!wire.localizedCaseInsensitiveContains("https://"))
            #expect(!wire.localizedCaseInsensitiveContains("file://"))
            #expect(!wire.localizedCaseInsensitiveContains("private prompt"))
            #expect(!wire.localizedCaseInsensitiveContains("secret.jpg"))
        }
    }

    @Test("Feedback, retailer, and subscription inputs are allowlisted before serialization")
    func adversarialCategoricalInputsAreSanitized() throws {
        let id = try #require(UUID(uuidString: "B97AA0BB-68B4-4E3A-BFB8-71A2A9D76365"))
        let privateValues = [
            "https://private.example/image.jpg?token=secret",
            "file:///Users/person/coat.jpg",
            "I hated the fit; prompt: wear my navy suit",
            "person@example.com",
            "Todd Snyder https://private.example/prompt"
        ]
        let events: [AnalyticsEvent] = [
            .outfitRejected(
                outfitID: id,
                reasonTags: [StyleFeedbackSignal.badFit.rawValue, privateValues[2], privateValues[3], StyleFeedbackSignal.wrongColor.rawValue]
            ),
            .affiliateLinkOpened(retailer: privateValues[0]),
            .affiliateLinkOpened(retailer: privateValues[4]),
            .subscriptionStarted(productID: privateValues[3])
        ]

        let rejectedProperties = events[0].properties
        guard case .array(let tags) = rejectedProperties["reason_tags"] else {
            Issue.record("The outfit rejection payload must preserve its reason_tags key.")
            return
        }
        #expect(tags == [.string(StyleFeedbackSignal.badFit.rawValue), .string(StyleFeedbackSignal.wrongColor.rawValue)])
        #expect(events[1].properties["retailer"] == .string("other"))
        #expect(events[2].properties["retailer"] == .string("other"))
        #expect(events[3].properties["product_id"] == .string("other"))

        for event in events {
            let data = try JSONEncoder().encode(QueuedAnalyticsEvent(userID: id, event: event))
            let wire = try #require(String(data: data, encoding: .utf8))
            for privateValue in privateValues {
                #expect(!wire.localizedCaseInsensitiveContains(privateValue))
            }
        }
    }

    @Test("Known catalog retailers serialize as stable IDs")
    func catalogRetailersUseCanonicalIDs() {
        let retailers = [
            ("Todd Snyder", "todd_snyder"),
            ("Drake's", "drakes"),
            ("Alden", "alden"),
            ("Hodinkee", "hodinkee")
        ]
        for (label, identifier) in retailers {
            #expect(AnalyticsEvent.affiliateLinkOpened(retailer: label).properties["retailer"] == .string(identifier))
        }
    }

    private func assertShallowNonSensitive(_ value: AstraJSONValue) throws {
        switch value {
        case .null, .bool:
            return
        case .number(let number):
            #expect(number.isFinite)
        case .string(let string):
            #expect(string.count <= 120)
            #expect(!string.contains("://"))
            #expect(!string.contains("/"))
            #expect(!string.contains("\n"))
        case .array(let values):
            for value in values {
                guard case .string(let string) = value else {
                    Issue.record("Analytics arrays must contain only bounded categorical strings.")
                    return
                }
                #expect(string.count <= 64)
                #expect(!string.contains("://"))
                #expect(!string.contains("/"))
                #expect(!string.contains("\n"))
            }
        case .object:
            Issue.record("Analytics properties must remain a shallow object.")
        }
    }
}
