import Foundation

extension LiveClosetRepository {
    public func fetchItemInsights(id: UUID) async throws -> ClosetItemInsights {
        try await apiClient.send(.fetchItemInsights(id: id), as: ClosetItemInsights.self)
    }
}
