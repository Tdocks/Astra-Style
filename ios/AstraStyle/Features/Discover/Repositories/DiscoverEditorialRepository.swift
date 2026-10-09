import Foundation

public protocol DiscoverEditorialRepository: Sendable {
    func fetchPublishedGuides() async throws -> [DiscoverGuide]
}

public struct BundleDiscoverEditorialRepository: DiscoverEditorialRepository {
    private static let resourceName = "discover-guides"
    private static let resourceDirectory = "Discover"

    public init() {}

    public func fetchPublishedGuides() async throws -> [DiscoverGuide] {
        let bundle = Bundle.main
        guard let url = bundle.url(
            forResource: Self.resourceName,
            withExtension: "json",
            subdirectory: Self.resourceDirectory
        ) ?? bundle.url(forResource: Self.resourceName, withExtension: "json") else {
            throw DiscoverEditorialRepositoryError.missingCatalog
        }
        return try Self.decodeCatalog(Data(contentsOf: url))
    }

    static func decodeCatalog(_ data: Data) throws -> [DiscoverGuide] {
        let document = try JSONDecoder().decode(DiscoverEditorialDocument.self, from: data)
        guard document.schemaVersion == 1 else {
            throw DiscoverEditorialRepositoryError.unsupportedSchema(document.schemaVersion)
        }
        var seen = Set<String>()
        return document.entries
            .filter { $0.isPublished && $0.isSafeToPublish }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
            }
    }
}

public actor StaticDiscoverEditorialRepository: DiscoverEditorialRepository {
    private let guides: [DiscoverGuide]
    private let shouldFail: Bool

    public init(guides: [DiscoverGuide], shouldFail: Bool = false) {
        self.guides = guides
        self.shouldFail = shouldFail
    }

    public func fetchPublishedGuides() throws -> [DiscoverGuide] {
        if shouldFail { throw DiscoverEditorialRepositoryError.unavailable }
        return guides
            .filter { $0.isPublished && $0.isSafeToPublish }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.id < rhs.id : lhs.sortOrder < rhs.sortOrder
            }
    }
}

public enum DiscoverEditorialRepositoryError: Error, Equatable {
    case missingCatalog
    case unsupportedSchema(Int)
    case unavailable
    case guideNotFound
}
