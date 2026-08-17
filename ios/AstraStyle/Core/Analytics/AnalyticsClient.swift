//
//  AnalyticsClient.swift
//  AstraStyle
//
//  Protocol-based analytics boundary (spec §18). `LiveAnalyticsClient`
//  batches events into `analytics_events` (`supabase/migrations/
//  20260816120000_analytics_events.sql`) through `AnalyticsEventQueue` +
//  `AnalyticsEventSending`; `NoOpAnalyticsClient` backs previews/tests so
//  no event ever needs network in those contexts.
//
//  WHY `log` / `identify` / `reset` STAY SYNCHRONOUS, NOT `async`. Every
//  call site is a plain, non-`async` line inside a view model action (e.g.
//  `Features/Scanner/ViewModels/ScannerReviewViewModel.swift`) — making
//  this protocol `async` would force every one of those call sites to
//  become `async` themselves, or to spawn their OWN `Task { await ... }`,
//  just to log a tap. Keeping the boundary synchronous means exactly one
//  place (`LiveAnalyticsClient`) owns the "hop onto a background `Task`"
//  decision, instead of it being repeated at every call site — and it is
//  also what makes this ticket's "an analytics write must never delay a
//  screen or fail a user action" true by construction, not by every call
//  site remembering not to `await` it.
//

import Foundation
import Supabase

public protocol AnalyticsClient: Sendable {
    func log(_ event: AnalyticsEvent)

    /// Associates the analytics identity with the signed-in user. Called
    /// once after sign-in; never carries PII beyond the opaque user id —
    /// display name, email, and images are never sent to analytics.
    func identify(userID: UUID)

    /// Clears the analytics identity on sign-out (spec §29 privacy
    /// posture: don't keep correlating events with a signed-out user).
    func reset()
}

/// Production conformance. See this file's header for why `log` stays
/// synchronous, and `AnalyticsEventQueue` / `AnalyticsEventDiskStore` for
/// the batching and offline persistence this delegates to.
///
/// PRIVACY GUARD, SECOND LAYER. `AnalyticsEvent.properties` already
/// excludes images and free text by construction (see that type's
/// header), and the migration's `analytics_event_properties_is_shallow`
/// check constraint is the defense-in-depth backstop below the database.
/// This class deliberately adds nothing further on top of either: a third
/// scrub here would be one more place to keep in sync with the other two,
/// and "in sync with two other things" is exactly how a guard silently
/// stops guarding anything.
public final class LiveAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private let queue: AnalyticsEventQueue
    private let sender: any AnalyticsEventSending
    /// Resolves the current user when `identify(userID:)` hasn't been
    /// called yet. As of this writing NOTHING in the app calls
    /// `identify`/`reset` — wiring them into sign-in/sign-out is outside
    /// this ticket's scope (`docs/17-completion-plan.md` G3 is specifically
    /// "the pipeline doesn't exist," not "the identity call sites are
    /// missing"). Without this fallback the pipeline built here would ship
    /// and still never send a single event, which defeats the point; this
    /// re-reads the live Supabase session per event instead, the same
    /// lookup `LiveOutfitRepository` / `LiveClosetRepository` already do
    /// per write.
    private let sessionUserID: @Sendable () async -> UUID?
    private let backgroundFlush: Task<Void, Never>?

    public convenience init(supabase: SupabaseClient = AstraSupabaseClientFactory.make(environment: .current)) {
        self.init(
            sender: SupabaseAnalyticsEventSender(supabase: supabase),
            sessionUserID: { try? await supabase.auth.session.user.id }
        )
    }

    /// Internal so tests can substitute the sender, session lookup, and
    /// disk persistence, and drive batching/offline behaviour without a
    /// live Supabase project. `autoFlushInterval: nil` disables the
    /// periodic background drain entirely — tests call `handle(_:)`
    /// directly and don't want a detached loop outliving them.
    init(
        queue: AnalyticsEventQueue = AnalyticsEventQueue(),
        sender: any AnalyticsEventSending,
        sessionUserID: @escaping @Sendable () async -> UUID? = { nil },
        autoFlushInterval: Duration? = .seconds(20)
    ) {
        self.queue = queue
        self.sender = sender
        self.sessionUserID = sessionUserID
        if let autoFlushInterval {
            let queue = self.queue
            let sender = self.sender
            // A backstop for events that are already queued but have
            // nothing new triggering `log()` to retry them (e.g. the app
            // regained connectivity in the background). Every `log()` call
            // already attempts a drain of its own — see `handle(_:)` —
            // this is only for the gap between them.
            backgroundFlush = Task.detached(priority: .background) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: autoFlushInterval)
                    await queue.drain { batch in try await sender.send(batch) }
                }
            }
        } else {
            backgroundFlush = nil
        }
    }

    deinit {
        backgroundFlush?.cancel()
    }

    public func log(_ event: AnalyticsEvent) {
        Task { await handle(event) }
    }

    public func identify(userID: UUID) {
        Task { await queue.setIdentity(userID) }
    }

    public func reset() {
        Task { await queue.setIdentity(nil) }
    }

    /// The work `log(_:)` defers onto a `Task`. Split out — rather than
    /// inlined in that closure — so tests can `await` it directly instead
    /// of racing an unstructured `Task`; see `LiveAnalyticsClientTests`.
    ///
    /// "Absent is honest; a confounded reading is not" applies here too:
    /// with no resolvable user id, the event is dropped, not sent under a
    /// placeholder id that would misattribute it once a real user does
    /// sign in.
    func handle(_ event: AnalyticsEvent) async {
        let userID: UUID?
        if let identified = await queue.currentIdentity() {
            userID = identified
        } else {
            userID = await sessionUserID()
        }
        guard let userID else { return }

        await queue.enqueue(QueuedAnalyticsEvent(userID: userID, event: event))
        let sender = self.sender
        await queue.drain { batch in try await sender.send(batch) }
    }
}

/// Used by `AppContainer.preview()` and unit tests — swallows every call.
public struct NoOpAnalyticsClient: AnalyticsClient {
    public init() {}
    public func log(_ event: AnalyticsEvent) {}
    public func identify(userID: UUID) {}
    public func reset() {}
}
