//
//  LiveOutfitRepository+Feedback.swift
//  AstraStyle
//
//  The `style_feedback` write (P4-OUTFIT-14), split into its own file for
//  the same reason `+Brief.swift` is: it shares the repository's client and
//  user scope and nothing else, and it keeps `LiveOutfitRepository.swift`
//  itself under SwiftLint's `type_body_length` ceiling.
//
//  MIRRORS `recordWear` EXACTLY, ON PURPOSE. Same offline shape: try the
//  live insert with a client-minted id, and on failure enqueue the same
//  row for `LiveOutfitRepository+Offline.swift` to replay later. A
//  like/skip/dislike tap while offline is exactly as legitimate as a
//  "mark worn" tap while offline (spec §7 does not carve out an exception
//  for feedback signals), so it gets the same treatment rather than
//  silently failing or blocking on connectivity.
//

import Foundation

public extension LiveOutfitRepository {
    @discardableResult
    func recordFeedback(
        targetType: StyleFeedbackTargetType,
        targetID: UUID,
        signal: StyleFeedbackSignal,
        reasonTags: [String],
        freeText: String?
    ) async throws -> StyleFeedback {
        do {
            let session = try await supabase.auth.session
            let feedback = StyleFeedback(
                id: UUID(),
                userID: session.user.id,
                targetType: targetType,
                targetID: targetID,
                signal: signal,
                reasonTags: reasonTags,
                freeText: freeText
            )
            let recorded = try await writer.createFeedback(feedback)
            await drainPendingMutations()
            return recorded
        } catch {
            let session = try? await supabase.auth.session
            let feedback = StyleFeedback(
                id: UUID(),
                userID: session?.user.id ?? UUID(),
                targetType: targetType,
                targetID: targetID,
                signal: signal,
                reasonTags: reasonTags,
                freeText: freeText
            )
            let payload = try JSONEncoder.astraDefault.encode(feedback)
            await offlineQueue.enqueue(OfflineMutation(entity: .styleFeedback, operation: .create, payloadData: payload))
            return feedback
        }
    }
}
