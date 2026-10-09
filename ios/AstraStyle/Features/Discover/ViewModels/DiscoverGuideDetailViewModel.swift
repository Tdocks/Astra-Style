import Foundation
import Observation

@MainActor
@Observable
public final class DiscoverGuideDetailViewModel {
    public enum State: Sendable {
        case loading
        case loaded(DiscoverGuide)
        case unavailable
        case failed
    }

    public private(set) var state: State = .loading

    private let slug: String
    private let repository: DiscoverEditorialRepository

    public init(slug: String, repository: DiscoverEditorialRepository) {
        self.slug = slug
        self.repository = repository
    }

    public func load() async {
        state = .loading
        do {
            let guides = try await repository.fetchPublishedGuides()
            guard let guide = guides.first(where: { $0.id == slug }) else {
                state = .unavailable
                return
            }
            state = .loaded(guide)
        } catch {
            state = .failed
        }
    }
}
