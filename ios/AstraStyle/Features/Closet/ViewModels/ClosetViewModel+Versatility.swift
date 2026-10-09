import Foundation

@MainActor
public extension ClosetViewModel {
    /// The versatility value is a caller-scoped server score, separate from
    /// pure local metrics. A failure degrades this tile only.
    func refreshVersatilityMetric() async {
        let requestID = UUID()
        wardrobeScoreRequestID = requestID
        versatilityMetric = .loading

        let ownerID: UUID?
        if let currentUserID {
            guard let resolvedOwnerID = await currentUserID() else {
                guard wardrobeScoreRequestID == requestID else { return }
                versatilityMetric = .unavailable
                return
            }
            ownerID = resolvedOwnerID
        } else {
            ownerID = nil
        }

        do {
            let snapshot = try await closetRepository.fetchWardrobeScoreSnapshot()
            guard wardrobeScoreRequestID == requestID else { return }
            if let currentUserID, await currentUserID() != ownerID {
                versatilityMetric = .unavailable
                return
            }
            guard let score = snapshot.score else {
                versatilityMetric = snapshot.activeItemCount == 0 ? .noData : .unavailable
                return
            }
            versatilityMetric = .score(
                score.versatility,
                degraded: snapshot.degradedComponents.contains(.versatility)
            )
        } catch {
            guard wardrobeScoreRequestID == requestID else { return }
            versatilityMetric = .unavailable
        }
    }
}
