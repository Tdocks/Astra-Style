//
//  AccountDeletionViewModel.swift
//  AstraStyle
//
//  Drives `AccountDeletionView` — the P7-PRIVACY-02 in-app deletion flow
//  App Store Guideline 5.1.1(v) requires alongside spec §15 "Data
//  deletion". Patterned on
//  `Features/Closet/ViewModels/ClosetItemDetailViewModel.swift`'s
//  destructive-action shape: an explicit phase, an in-flight guard, and a
//  typed failure the view renders inline rather than an alert that can
//  vanish before it is read.
//
//  WHY THIS NEVER SHOWS "DELETED", ONLY "STARTED". `DELETE /account`
//  answers 202 the moment `request_account_deletion()` returns — before
//  the storage purge, the row cascade, or the `auth.users` delete have
//  run (see `supabase/functions/account/handler.ts`'s header). The
//  response this view model receives, `AccountDeletionStatus`, can only
//  ever carry `.pending`/`.processing` — see that type's own header for
//  why the client can never observe `.completed` for its own account, by
//  the migration's design (the RLS row that would say so stops being
//  visible to this user in the same instant it could say it). So `Phase`
//  has a `.started` case, never a `.completed` one: claiming completion
//  here would be exactly the "confounded reading" this codebase's house
//  rule forbids — this view model does not know the deletion finished,
//  only that it began, and says so.
//
//  WHY SIGN-OUT ITSELF IS NOT THIS TYPE'S JOB. `AuthRepository
//  .deleteAccount()` already signs the local session out as its last
//  internal step before this method's `await` even returns — by the time
//  `phase` becomes `.started`, `SessionStore.isSignedIn` is already
//  `false`. What this view model does NOT do is flip `AppRouter
//  .routeState`; that is `AccountDeletionView`'s call, made only once the
//  user taps the closing screen's acknowledgement, so "this can't be
//  undone, you're signed out" is something read, not something that
//  flashes past as the tab shell is torn down underneath it. Routing is a
//  view concern in this codebase (`RootView`, `SignedOutGateView`) and
//  this type has no `AppRouter` dependency to keep it that way.
//

import Foundation
import Observation

@MainActor
@Observable
public final class AccountDeletionViewModel {

    public enum Phase: Equatable {
        /// Reviewing what will be destroyed; nothing has been sent yet.
        case confirming
        /// The `DELETE /account` call is in flight.
        case deleting
        /// The server accepted the request. Terminal — nothing about the
        /// destructive action can be undone or retried from here.
        case started(AccountDeletionStatus)
        /// The call failed before the server could accept it (network,
        /// rate limit, expired session, etc). Retriable when
        /// `error.isRetryable` — the same rule `AstraAPIClient` itself
        /// uses to decide whether a failure is worth a second attempt.
        case failed(AstraError)
    }

    public private(set) var phase: Phase = .confirming

    /// The explicit, separate acknowledgment `AccountDeletionView` gates
    /// its destructive button behind — see that file's header on why one
    /// tap alone is not enough for this action. Public var rather than
    /// `private(set)` because the view's own `Toggle` binds to it
    /// directly.
    public var hasAcknowledgedIrreversibility = false

    private let authRepository: AuthRepository

    public init(authRepository: AuthRepository) {
        self.authRepository = authRepository
    }

    /// Sends `DELETE /account`. Guarded by both the acknowledgment toggle
    /// and `phase`, so a confirmation dialog that somehow fires twice (a
    /// double-tap racing its own dismiss animation) cannot start two
    /// requests in this process — though the endpoint would answer both
    /// identically either way, per `AccountDeletionStatus`'s idempotency
    /// note.
    public func delete() async {
        guard hasAcknowledgedIrreversibility else { return }
        switch phase {
        case .confirming, .failed:
            break
        case .deleting, .started:
            return
        }

        phase = .deleting
        do {
            let status = try await authRepository.deleteAccount()
            phase = .started(status)
        } catch let error as AstraError {
            phase = .failed(error)
        } catch {
            phase = .failed(AstraError(category: .unknown, message: error.localizedDescription))
        }
    }
}
