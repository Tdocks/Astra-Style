//
//  KyraTranscriptEntry.swift
//  AstraStyle
//
//  One row of the conversation as the SCREEN holds it, which is a
//  different thing from a `kyra_messages` row. A user message exists here
//  before the server has acknowledged it (the local echo, which may yet
//  fail and need retry — so it keeps the material to resend), and an
//  assistant message exists here only after its cards have been hydrated
//  from ids into drawable models. `KyraMessage` is the wire/persistence
//  truth; this is the render truth, and conflating them is how a failed
//  send ends up looking indistinguishable from a delivered one.
//

import Foundation

public struct KyraTranscriptEntry: Identifiable, Sendable {
    /// Everything needed to send this message again if it fails: the text
    /// and the attachment DRAFTS (not the uploaded wire attachments — a
    /// photo whose upload failed has no storage path to reuse).
    public struct PendingSend: Sendable {
        public var text: String
        public var drafts: [KyraAttachmentDraft]

        public init(text: String, drafts: [KyraAttachmentDraft]) {
            self.text = text
            self.drafts = drafts
        }
    }

    public let id: UUID
    public var role: KyraMessageRole
    public var text: String

    /// Composer chips echoed alongside the user's text, so a message sent
    /// with a closet item attached reads that way in the transcript.
    public var attachmentLabels: [String]

    /// The wire cards as decoded, kept so a card whose hydration failed can
    /// be re-hydrated without re-fetching the message.
    public var rawCards: [KyraCard]
    public var cards: [KyraRenderedCard]
    public var suggestedActions: [KyraSuggestedAction]

    /// Contents of the response's `memory_proposals`. The server has
    /// ALREADY persisted these (kyra/README.md: proposals are rebuilt from
    /// what `save_preference` actually wrote), so they render as visible
    /// notes — not as confirm buttons, which would insert a duplicate
    /// `style_memories` row on top of the server's write. Management of
    /// saved memories (inspect/delete) is the P5-KYRA-17 surface.
    public var memoryNotes: [String]

    /// Set when the send failed. The entry stays visible and marked, never
    /// silently dropped — a message that looks sent but wasn't is the
    /// exact failure P5-KYRA-18's acceptance criterion names.
    public var sendFailure: AstraError?
    public var pending: PendingSend?

    public init(
        id: UUID = UUID(),
        role: KyraMessageRole,
        text: String,
        attachmentLabels: [String] = [],
        rawCards: [KyraCard] = [],
        cards: [KyraRenderedCard] = [],
        suggestedActions: [KyraSuggestedAction] = [],
        memoryNotes: [String] = [],
        sendFailure: AstraError? = nil,
        pending: PendingSend? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachmentLabels = attachmentLabels
        self.rawCards = rawCards
        self.cards = cards
        self.suggestedActions = suggestedActions
        self.memoryNotes = memoryNotes
        self.sendFailure = sendFailure
        self.pending = pending
    }
}
