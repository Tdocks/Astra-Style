import Foundation

public enum DiscoverEditorialKind: String, Decodable, Hashable, Sendable {
    case styleEducation = "style_education"
    case seasonalGuide = "seasonal_guide"
    case fitGuide = "fit_guide"
    case brandSpotlight = "brand_spotlight"
}

public struct DiscoverGuideSource: Decodable, Hashable, Sendable, Identifiable {
    public let title: String
    public let url: String

    public var id: String { url }

    public var destination: URL? {
        guard let destination = URL(string: url), destination.scheme == "https", destination.host != nil else {
            return nil
        }
        return destination
    }
}

public struct DiscoverGuideSection: Decodable, Hashable, Sendable, Identifiable {
    public let heading: String
    public let body: String

    public var id: String { heading }
}

public struct DiscoverGuide: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let sortOrder: Int
    public let kind: DiscoverEditorialKind
    public let title: String
    public let summary: String
    public let readingMinutes: Int
    public let season: String?
    public let sections: [DiscoverGuideSection]
    public let isPublished: Bool
    public let editorialLabel: String?
    public let isSponsored: Bool?
    public let sponsorshipDisclosure: String?
    public let sources: [DiscoverGuideSource]?
    public let reviewedAt: String?

    public var visibleCommercialLabel: String? {
        if isSponsored == true { return sponsorshipDisclosure }
        return editorialLabel
    }

    public var isSafeToPublish: Bool {
        let requiredText = [id, title, summary]
        guard requiredText.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              sortOrder >= 0,
              (1...12).contains(readingMinutes),
              !sections.isEmpty,
              sections.allSatisfy({
                  !$0.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              })
        else { return false }

        if isSponsored == true,
           (sponsorshipDisclosure ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if kind == .brandSpotlight {
            guard let reviewedAt,
                  ISO8601DateFormatter().date(from: reviewedAt) != nil,
                  let sources, !sources.isEmpty,
                  sources.allSatisfy({
                      !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.destination != nil
                  })
            else { return false }

            if isSponsored == true { return true }
            return isSponsored == false && editorialLabel == "Editorial · Not sponsored"
        }
        return true
    }
}

struct DiscoverEditorialDocument: Decodable, Sendable {
    let schemaVersion: Int
    let entries: [DiscoverGuide]
}
