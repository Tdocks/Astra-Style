//
//  KyraConversationViewModel.swift
//  AstraStyle
//
//  State for the Kyra conversation screen (spec §6.20, P5-KYRA-13/-15).
//  No network call happens in the views; everything goes through here.
//
//  OFFLINE IS A STATED CONDITION, NOT A QUEUE. Closet edits queue offline
//  because they are deterministic and idempotent; a Kyra prompt is
//  neither — the answer depends on weather, schedule, and closet state at
//  the moment it runs, and a reply that arrives hours after the question
//  ("what should I wear tonight?") answers a question that has expired.
//  So there is no queue-and-hope: while offline the composer is disabled
//  behind an explicit "Kyra needs a connection" state, and a send that
//  fails mid-flight stays in the transcript marked failed, with a retry
//  that is only offered while retrying can succeed (spec §21). This is
//  the client half of the P5-KYRA-18 decision recorded in
//  AstraModelContainer.swift.
//
//  THE LOCAL ECHO IS APPENDED BEFORE THE REQUEST RETURNS, DELIBERATELY.
//  Waiting for the server's persisted user row before drawing the message
//  would make every send feel like a two-and-a-half-second keyboard
//  freeze. The echo is honest because failure is visible on it: the entry
//  never silently disappears or silently succeeds — it either gains the
//  assistant's reply after it or gains a failure mark and a retry.
//
//  ANALYTICS LOGS THE INTENT AND NOTHING ELSE. Spec §18 is explicit that
//  `kyra_prompt_sent` never carries the free text; the event is logged
//  after the response, when the classified intent exists, and with a nil
//  intent when the turn failed — the send still happened, and counting
//  only successes would make the funnel lie about demand.
//

import Foundation
import Observation

@MainActor
@Observable
public final class KyraConversationViewModel {

    public enum HistoryState: Sendable {
        case loading
        case loaded
        case failed(AstraError)
    }

    /// The five suggested prompts, verbatim from spec §6.20. Real controls,
    /// not decoration: tapping one sends it through the same path as typed
    /// text (P5-KYRA-15's single acceptance criterion).
    public static let suggestedPrompts: [String] = [
        String(localized: "What should I wear tonight?", comment: "Kyra suggested prompt"),
        String(localized: "Does this fit correctly?", comment: "Kyra suggested prompt"),
        String(localized: "Should I buy this?", comment: "Kyra suggested prompt"),
        String(localized: "Build me a $500 capsule.", comment: "Kyra suggested prompt"),
        String(localized: "Pack for a four-day trip.", comment: "Kyra suggested prompt")
    ]

    public private(set) var historyState: HistoryState = .loading
    public private(set) var entries: [KyraTranscriptEntry] = []
    public private(set) var isSending = false
    public private(set) var isOffline = false

    /// Nil until the first reply names the server-created thread; every
    /// later send reuses it so the conversation stays one thread.
    public private(set) var threadID: UUID?

    public var draftText = ""
    public private(set) var attachments: [KyraAttachmentDraft] = []

    /// One-shot completions ("Marked worn"), keyed `entryID.actionID` so
    /// the same action on two messages doesn't share state.
    public private(set) var performedActionKeys: Set<String> = []
    public private(set) var inFlightActionKeys: Set<String> = []

    /// Spoken confirmation/failure for the most recent suggested action —
    /// a tap that silently does nothing is §22's dead button.
    public private(set) var actionNote: String?

    /// Nested paywall when Edge returns 429 on a new thread. Ask Kyra is
    /// already a modal; AppRouter has one slot.
    public private(set) var pendingStudioGenerationID: UUID?

    public func clearPendingStudioPreview() { pendingStudioGenerationID = nil }

    public private(set) var pendingPaywall: PaywallContext?

    /// What the closet-item and outfit attachment pickers can offer. Kept
    /// as a tri-state rather than `(try? fetch) ?? []` because an empty
    /// closet and a failed fetch are different truths — showing "nothing
    /// in your closet" over a network error is the confounded reading.
    public enum AttachmentChoices: Sendable {
        case loading
        case loaded(closet: [ClosetItem], outfits: [Outfit])
        case failed(AstraError)
    }

    public private(set) var attachmentChoices: AttachmentChoices = .loading

    private let kyraRepository: KyraRepository
    private let outfitRepository: OutfitRepository
    private let closetRepository: ClosetRepository
    private let networkMonitor: NetworkReachabilityMonitoring
    private let analyticsClient: AnalyticsClient
    private let hydrator: KyraCardHydrator
    private let initialPrompt: String?
    private let contextualOutfitID: UUID?
    private let contextualStudioGenerationID: UUID?
    private let autoSendInitialPrompt: Bool
    private var didSendInitialPrompt = false
    private var connectivityTask: Task<Void, Never>?

    public init(
        threadID: UUID?,
        kyraRepository: KyraRepository,
        outfitRepository: OutfitRepository,
        closetRepository: ClosetRepository,
        shoppingRepository: ShoppingRepository,
        imageURLResolver: ClosetImageURLResolving,
        networkMonitor: NetworkReachabilityMonitoring,
        analyticsClient: AnalyticsClient,
        initialPrompt: String? = nil,
        contextualOutfitID: UUID? = nil,
        contextualStudioGenerationID: UUID? = nil,
        autoSendInitialPrompt: Bool = false
    ) {
        self.threadID = threadID
        self.kyraRepository = kyraRepository
        self.outfitRepository = outfitRepository
        self.closetRepository = closetRepository
        self.networkMonitor = networkMonitor
        self.analyticsClient = analyticsClient
        self.initialPrompt = initialPrompt
        self.contextualOutfitID = contextualOutfitID
        self.contextualStudioGenerationID = contextualStudioGenerationID
        self.autoSendInitialPrompt = autoSendInitialPrompt
        self.hydrator = KyraCardHydrator(
            outfitRepository: outfitRepository,
            closetRepository: closetRepository,
            shoppingRepository: shoppingRepository,
            imageURLResolver: imageURLResolver
        )
    }

    // MARK: - Derived state

    /// Prompts show on an empty, ready conversation — they are the empty
    /// state's content (spec §21), not a permanent toolbar.
    public var showsSuggestedPrompts: Bool {
        if case .loaded = historyState { return entries.isEmpty && !isSending }
        return false
    }

    public var canSendDraft: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending && !isOffline
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        if connectivityTask == nil {
            isOffline = await networkMonitor.isOffline()
            startConnectivityWatch()
        }
        guard case .loading = historyState else { return }
        await loadHistory()
        guard autoSendInitialPrompt, !didSendInitialPrompt, threadID == nil,
              entries.isEmpty, let initialPrompt else { return }
        didSendInitialPrompt = true
        await send(text: initialPrompt, drafts: [], contextualOutfitID: contextualOutfitID)
    }

    public func onDisappear() {
        connectivityTask?.cancel()
        connectivityTask = nil
    }

    public func reloadHistory() async {
        historyState = .loading
        await loadHistory()
    }

    private func startConnectivityWatch() {
        connectivityTask = Task { [weak self] in
            guard let stream = self?.networkMonitor.connectivityUpdates() else { return }
            for await isOnline in stream {
                self?.isOffline = !isOnline
            }
        }
    }

    private func loadHistory() async {
        // A new conversation has no history to fetch — and must not touch
        // the network to become usable, or the modal would show a spinner
        // before an empty screen.
        guard let threadID else {
            historyState = .loaded
            return
        }
        do {
            let messages = try await kyraRepository.fetchMessages(threadID: threadID)
            var loaded: [KyraTranscriptEntry] = []
            for (index, message) in messages.enumerated() {
                let previousUserPrompt = messages[..<index].last(where: { $0.role == .user })?.content
                loaded.append(await entry(for: message, retryPrompt: previousUserPrompt))
            }
            entries = loaded
            historyState = .loaded
        } catch {
            historyState = .failed(asAstraError(error))
        }
    }

    // MARK: - Composer

    public func attach(_ payload: KyraAttachmentDraft.Payload) {
        attachments.append(KyraAttachmentDraft(payload: payload))
    }

    /// Loads what the closet-item/outfit pickers can offer. Called when a
    /// picker opens, not on appear — most sends never attach anything, and
    /// two fetches at open would tax the common case for the rare one.
    public func loadAttachmentChoices() async {
        attachmentChoices = .loading
        do {
            let closet = try await closetRepository.fetchItems()
            let outfits = try await outfitRepository.fetchOutfits()
            attachmentChoices = .loaded(closet: closet, outfits: outfits)
        } catch {
            attachmentChoices = .failed(asAstraError(error))
        }
    }

    public func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    public func sendDraft() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, !isOffline else { return }
        let drafts = attachments
        draftText = ""
        attachments = []
        await send(text: text, drafts: drafts, contextualOutfitID: contextualOutfitID)
    }

    /// P5-KYRA-15: a tapped prompt IS a message, through the same path as
    /// typed text — not a pre-fill the user must re-confirm.
    public func send(prompt: String) async {
        guard !isSending, !isOffline else { return }
        await send(text: prompt, drafts: [], contextualOutfitID: contextualOutfitID)
    }

    /// Re-sends a failed message. The failed echo is removed and the send
    /// path re-runs from the drafts, so a photo whose UPLOAD failed is
    /// re-uploaded rather than replayed as a dangling storage path.
    public func retrySend(entryID: UUID) async {
        guard !isSending, !isOffline,
              let index = entries.firstIndex(where: { $0.id == entryID }),
              let pending = entries[index].pending,
              entries[index].sendFailure != nil else { return }
        entries.remove(at: index)
        await send(
            text: pending.text,
            drafts: pending.drafts,
            contextualOutfitID: pending.contextualOutfitID
        )
    }

    /// A provider fallback is a persisted assistant row, not a transport
    /// failure. Retry it as a new turn on the same server-created thread.
    public func retryAssistantFailure(entryID: UUID) async {
        guard !isSending, !isOffline,
              let entry = entries.first(where: { $0.id == entryID }),
              let prompt = entry.assistantRetryPrompt else { return }
        await send(text: prompt, drafts: [], contextualOutfitID: contextualOutfitID)
    }

    private func send(text: String, drafts: [KyraAttachmentDraft], contextualOutfitID: UUID? = nil) async {
        isSending = true
        defer { isSending = false }

        let localID = UUID()
        entries.append(KyraTranscriptEntry(
            id: localID,
            role: .user,
            text: text,
            attachmentLabels: drafts.map(\.label) + (contextualOutfitID == nil ? [] : [String(localized: "Current outfit")]) + (contextualStudioGenerationID == nil ? [] : [String(localized: "Studio inspiration")]),
            pending: KyraTranscriptEntry.PendingSend(
                text: text,
                drafts: drafts,
                contextualOutfitID: contextualOutfitID
            )
        ))

        do {
            let outgoing = try await outgoingMessage(
                text: text,
                drafts: drafts,
                contextualOutfitID: contextualOutfitID
            )
            let reply = try await kyraRepository.send(threadID: threadID, message: outgoing)
            threadID = reply.threadID
            markSendDelivered(entryID: localID)
            entries.append(await entry(for: reply, retryPrompt: text))
            analyticsClient.log(.kyraPromptSent(intent: reply.structuredPayload?.intent))
        } catch {
            markSendFailed(entryID: localID, error: asAstraError(error))
            analyticsClient.log(.kyraPromptSent(intent: nil))
        }
    }

    /// Uploads photo drafts and maps everything to the wire attachment
    /// shape. Throws rather than dropping a failed upload: a message sent
    /// with fewer attachments than the user chose would be a silent edit
    /// of what he said.
    private func outgoingMessage(
        text: String,
        drafts: [KyraAttachmentDraft],
        contextualOutfitID: UUID?
    ) async throws -> KyraOutgoingMessage {
        var wireAttachments: [KyraOutgoingMessage.Attachment] = []
        for draft in drafts {
            switch draft.payload {
            case .photo(let data):
                let path = try await closetRepository.uploadCapturedImage(data)
                wireAttachments.append(.photo(storagePath: path))
            case .productLink(let url):
                wireAttachments.append(.productLink(url))
            case .closetItem(let item):
                wireAttachments.append(.closetItem(closetItemID: item.id))
            case .outfit(let outfit):
                wireAttachments.append(.outfit(outfitID: outfit.id))
            }
        }
        if let contextualOutfitID { wireAttachments.append(.outfit(outfitID: contextualOutfitID)) }
        if let contextualStudioGenerationID { wireAttachments.append(.studioInspiration(generationID: contextualStudioGenerationID)) }
        return KyraOutgoingMessage(text: text, attachments: wireAttachments)
    }

    // MARK: - Entry construction

    private func entry(for message: KyraMessage, retryPrompt: String? = nil) async -> KyraTranscriptEntry {
        guard message.role == .assistant, let payload = message.structuredPayload else {
            return KyraTranscriptEntry(id: message.id, role: message.role, text: message.content)
        }
        let fallbackReason = providerFallbackReason(message)
        let providerFailed = fallbackReason != nil
        return KyraTranscriptEntry(
            id: message.id,
            role: .assistant,
            // The payload's `message` is Kyra's voice (docs/06 §2); the
            // row's `content` duplicates it and is the fallback when a
            // historical row predates structured payloads.
            text: payload.message.isEmpty ? message.content : payload.message,
            rawCards: payload.cards,
            cards: await hydrator.hydrate(payload.cards),
            suggestedActions: payload.suggestedActions,
            memoryNotes: payload.memoryProposals.map(\.content),
            assistantFailureMessage: providerFailed
                ? (fallbackReason == "provider_not_configured"
                    ? String(localized: "Kyra's styling service hasn't been connected yet.", comment: "Kyra provider configuration failure")
                    : String(localized: "Kyra couldn't reach her styling service just now.", comment: "Kyra provider failure"))
                : nil,
            assistantRetryPrompt: providerFailed ? retryPrompt : nil
        )
    }

    private func providerFallbackReason(_ message: KyraMessage) -> String? {
        guard case .object(let metadata)? = message.modelMetadata,
              case .string(let reason)? = metadata["fallback_reason"],
              reason == "provider_error" || reason == "provider_not_configured" else { return nil }
        return reason
    }

    /// Re-runs hydration for one message's cards — the retry behind an
    /// `.unavailable` card. Retries the whole array rather than one card
    /// because hydration shares the closet fetch across cards.
    public func rehydrateCards(entryID: UUID) async {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              !entries[index].rawCards.isEmpty else { return }
        entries[index].cards = await hydrator.hydrate(entries[index].rawCards)
    }

    private func markSendDelivered(entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].sendFailure = nil
        entries[index].pending = nil
    }

    private func markSendFailed(entryID: UUID, error: AstraError) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].sendFailure = error
        if error.category == .rateLimited {
            pendingPaywall = .kyraDailyLimit
        }
    }

    public func clearPendingPaywall() {
        pendingPaywall = nil
    }

    private func asAstraError(_ error: Error) -> AstraError {
        (error as? AstraError) ?? AstraError(category: .unknown, message: error.localizedDescription)
    }
}

// MARK: - Suggested actions

// WHICH ACTION KINDS RENDER, AND WHY THE OTHERS DO NOT. The server's
// actions carry no payload — `{id, label, kind}` only — so an action's
// Outfit targets come from hydrated cards. A queued Studio preview uses the
// server-produced studio-preview:<UUID> action ID to open its existing result
// screen, whose repository enforces ownership. Unsupported actions stay hidden.
extension KyraConversationViewModel {

    public func canPerform(_ action: KyraSuggestedAction, in entry: KyraTranscriptEntry) -> Bool {
        switch action.kind {
        case .viewAlternatives:
            return true
        case .wearOutfit, .saveOutfit:
            return firstOutfitID(in: entry) != nil
        case .startStudioGeneration:
            return studioPreviewID(action) != nil
        case .openProduct, .scheduleOutfit, .addOccasion:
            return false
        }
    }

    public func actionKey(_ action: KyraSuggestedAction, entryID: UUID) -> String {
        "\(entryID.uuidString).\(action.id)"
    }

    public func perform(_ action: KyraSuggestedAction, in entryID: UUID) async {
        guard let entry = entries.first(where: { $0.id == entryID }),
              canPerform(action, in: entry) else { return }
        let key = actionKey(action, entryID: entryID)
        guard !performedActionKeys.contains(key), !inFlightActionKeys.contains(key) else { return }

        switch action.kind {
        case .wearOutfit:
            await recordOutfitAction(entry: entry, key: key, kind: .wearOutfit)
        case .saveOutfit:
            await recordOutfitAction(entry: entry, key: key, kind: .saveOutfit)
        case .viewAlternatives:
            // A real follow-up turn, not a filter: alternatives are a
            // generative answer, so the request goes to Kyra like any other
            // message. Repeatable by design — never marked performed.
            await send(prompt: String(
                localized: "What else would work instead?",
                comment: "Message sent when the user taps Kyra's see-alternatives action"
            ))
        case .startStudioGeneration:
            pendingStudioGenerationID = studioPreviewID(action)
        case .openProduct, .scheduleOutfit, .addOccasion:
            // Unreachable through the UI (canPerform filters them); listed
            // explicitly so a new kind added to the enum fails compilation
            // here instead of falling into silence.
            return
        }
    }

    private func studioPreviewID(_ action: KyraSuggestedAction) -> UUID? {
        let prefix = "studio-preview:"
        guard action.id.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(action.id.dropFirst(prefix.count)))
    }

    private func recordOutfitAction(
        entry: KyraTranscriptEntry,
        key: String,
        kind: KyraSuggestedAction.Kind
    ) async {
        guard let outfitID = firstOutfitID(in: entry) else { return }
        inFlightActionKeys.insert(key)
        defer { inFlightActionKeys.remove(key) }
        do {
            switch kind {
            case .wearOutfit:
                _ = try await outfitRepository.recordWear(
                    outfitID: outfitID, wornAt: .now, occasion: nil, rating: nil, feedback: nil
                )
                actionNote = String(
                    localized: "Marked worn — your wear history is updated.",
                    comment: "Confirmation after the wear-this action succeeds"
                )
            case .saveOutfit:
                // A "save" from chat is a durable opinion signal, not a new
                // row: the outfit Kyra cites already exists in `outfits`
                // (her `create_outfit` tool wrote it), so the honest write
                // is `style_feedback.saved` — the signal §10's
                // compatibility term learns from.
                _ = try await outfitRepository.recordFeedback(
                    targetType: .outfit, targetID: outfitID, signal: .saved
                )
                actionNote = String(
                    localized: "Saved — Kyra will weigh this look more.",
                    comment: "Confirmation after the save-outfit action succeeds"
                )
            case .viewAlternatives, .openProduct, .scheduleOutfit, .startStudioGeneration, .addOccasion:
                return
            }
            performedActionKeys.insert(key)
            AstraHaptics.success()
        } catch {
            // The tap failed and says so; the button stays live because the
            // failure is transient (both repositories queue offline writes,
            // so reaching here is rarer than it looks).
            actionNote = asAstraError(error).message
        }
    }

    private func firstOutfitID(in entry: KyraTranscriptEntry) -> UUID? {
        for card in entry.cards {
            if case .outfit(let model) = card { return model.id }
        }
        return nil
    }
}
