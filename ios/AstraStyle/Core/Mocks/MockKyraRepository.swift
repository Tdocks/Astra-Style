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
    private var memories: [StyleMemory] = [
        StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: .preference, content: "Prefers tapered trousers over slim-straight.", confidence: 0.86),
        StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: .dislike, content: "Dislikes busy logo branding.", confidence: 0.91),
        StyleMemory(id: UUID(), userID: SampleData.userID, memoryType: .fitNote, content: "Runs slightly long in the torso; prefers cropped jacket lengths.", confidence: 0.74),
    ]

    public init() {}

    public func fetchThreads() async throws -> [KyraThread] { threads }

    public func fetchMessages(threadID: UUID) async throws -> [KyraMessage] {
        messagesByThread[threadID] ?? []
    }

    public func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage {
        let resolvedThreadID = threadID ?? UUID()
        if !threads.contains(where: { $0.id == resolvedThreadID }) {
            threads.append(KyraThread(id: resolvedThreadID, userID: SampleData.userID, title: String(message.text.prefix(40)), lastMessageAt: .now))
        }

        let userMessage = KyraMessage(id: UUID(), threadID: resolvedThreadID, role: .user, content: message.text)

        let reply = KyraMessage(
            id: UUID(),
            threadID: resolvedThreadID,
            role: .assistant,
            content: "I'd wear the olive knit polo with stone trousers and the suede chukkas — it reads put-together without looking like you tried too hard.",
            structuredPayload: KyraStructuredResponse(
                message: "I'd wear the olive knit polo with stone trousers and the suede chukkas.",
                intent: .dailyOutfit,
                cards: [.outfit(outfitID: SampleData.heroOutfit.id)],
                suggestedActions: [
                    KyraSuggestedAction(id: "wear", label: "Wear This", kind: .wearOutfit),
                    KyraSuggestedAction(id: "alts", label: "See Alternatives", kind: .viewAlternatives),
                ],
                confidence: 0.88
            )
        )

        messagesByThread[resolvedThreadID, default: []].append(contentsOf: [userMessage, reply])
        return reply
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
