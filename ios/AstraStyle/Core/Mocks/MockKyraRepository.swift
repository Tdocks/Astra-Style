//
//  MockKyraRepository.swift
//  AstraStyle
//
//  In-memory `KyraRepository` for previews/tests (spec §31).
//

import Foundation

public actor MockKyraRepository: KyraRepository {
    private var threads: [KyraThread] = []
    private var messagesByThread: [UUID: [KyraMessage]] = [:]
    public private(set) var sentMessages: [KyraOutgoingMessage] = []
    public private(set) var sentThreadIDs: [UUID?] = []
    private var nextSendError: AstraError?
    private var nextReplyMessage: String?
    private var nextFallbackReason: String?
    private var memories: [StyleMemory] = [
        StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: .preference, content: "Prefers tapered trousers over slim-straight.", confidence: 0.86),
        StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: .dislike, content: "Dislikes busy logo branding.", confidence: 0.91),
        StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: .fitNote, content: "Runs slightly long in the torso; prefers cropped jacket lengths.", confidence: 0.74)
    ]

    private let previewGenerationID: UUID?

    public init(previewGenerationID: UUID? = nil) { self.previewGenerationID = previewGenerationID }

    public func failNextSend(with error: AstraError) { nextSendError = error }

    public func setNextReplyMessage(_ message: String) { nextReplyMessage = message }

    public func setNextFallbackReason(_ reason: String) { nextFallbackReason = reason }

    public func fetchThreads() async throws -> [KyraThread] { threads }

    public func fetchMessages(threadID: UUID) async throws -> [KyraMessage] {
        messagesByThread[threadID] ?? []
    }

    public func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        sentMessages.append(message)
        sentThreadIDs.append(threadID)
        if let error = nextSendError {
            nextSendError = nil
            throw error
        }
        let resolvedThreadID = threadID ?? UUID()
        if !threads.contains(where: { $0.id == resolvedThreadID }) {
            threads.append(KyraThread(id: resolvedThreadID, userID: SampleData.userID, title: String(message.text.prefix(40)), lastMessageAt: .now))
        }

        let userMessage = KyraMessage(id: UUID(), threadID: resolvedThreadID, role: .user, content: message.text)
        let generatedReply = nextReplyMessage ?? (
            message.text.contains("Write my Monthly Review")
                ? "Your month included the recorded looks and purchases above. Next month, try one new combination with an underused piece."
                : "I'd wear the olive knit polo with stone trousers and the suede chukkas."
        )

        let reply = KyraMessage(
            id: UUID(),
            threadID: resolvedThreadID,
            role: .assistant,
            content: generatedReply,
            structuredPayload: KyraStructuredResponse(
                message: generatedReply,
                intent: .dailyOutfit,
                cards: [.outfit(outfitID: SampleData.heroOutfit.id)],
                suggestedActions: (previewGenerationID.map { [KyraSuggestedAction(id: "studio-preview:\($0.uuidString)", label: "Open preview", kind: .startStudioGeneration)] } ?? []) + [
                    KyraSuggestedAction(id: "wear", label: "Wear This", kind: .wearOutfit),
                    KyraSuggestedAction(id: "alts", label: "See Alternatives", kind: .viewAlternatives)
                ],
                confidence: 0.88
            ),
            modelMetadata: nextFallbackReason.map { .object(["fallback_reason": .string($0)]) }
        )
        nextReplyMessage = nil
        nextFallbackReason = nil

        messagesByThread[resolvedThreadID, default: []].append(contentsOf: [userMessage, reply])
        return reply
    }

    public func send(
        threadID: UUID?,
        message: KyraOutgoingMessage,
        expectedOwnerID: UUID
    ) async throws -> KyraMessage {
        guard expectedOwnerID == SampleData.userID else {
            throw AstraError.auth("Your account changed while preparing the review.")
        }
        return try await send(threadID: threadID, message: message)
    }

    public func fetchMemories() async throws -> [StyleMemory] { memories }

    public func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory {
        let memory = StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: proposal.memoryType, content: proposal.content, confidence: proposal.confidence, sourceMessageID: sourceMessageID)
        memories.append(memory)
        return memory
    }

    public func deleteMemory(id: UUID) async throws {
        memories.removeAll { $0.id == id }
    }
}
