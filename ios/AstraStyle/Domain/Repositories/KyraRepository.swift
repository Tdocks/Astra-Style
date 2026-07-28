//
//  KyraRepository.swift
//  AstraStyle
//
//  Owns `kyra_threads` / `kyra_messages` / `style_memories` (spec §9) and
//  the conversation orchestration call (spec §14 `kyra/respond`).
//

import Foundation

public protocol KyraRepository: Sendable {
    func fetchThreads() async throws -> [KyraThread]
    func fetchMessages(threadID: UUID) async throws -> [KyraMessage]

    /// Sends a message to Kyra. Pass `threadID: nil` to start a new
    /// thread. Calls `POST /kyra/respond` (spec §14) and always returns a
    /// structured response (spec §11) — never unparsed prose.
    func send(threadID: UUID?, message: KyraOutgoingMessage) async throws -> KyraMessage

    func fetchMemories() async throws -> [StyleMemory]

    /// Confirms a memory Kyra proposed saving mid-conversation
    /// (spec §6.20 "Save durable preferences only when relevant").
    func confirmMemoryProposal(_ proposal: KyraMemoryProposal, sourceMessageID: UUID) async throws -> StyleMemory

    /// Deletes a style memory the user no longer wants Kyra to use
    /// (spec §6.20 "Allow users to inspect and delete style memories").
    func deleteMemory(id: UUID) async throws
}
