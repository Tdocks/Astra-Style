//
//  AccountDeletionStatus.swift
//  AstraStyle
//
//  The wire shape `DELETE /account` answers with (spec §14/§15,
//  `supabase/functions/account/schema.ts`'s `AccountDeletionStatusDTO`) —
//  the id of the `account_deletions` row the request created or found
//  already in flight, and its status at the instant the HTTP response was
//  built.
//
//  WHY `status` HAS ONLY TWO CASES, NOT FOUR. `account_deletions.status`
//  is a four-value Postgres enum (`pending`, `processing`, `completed`,
//  `failed` — see the migration), but this type only ever decodes
//  `pending`/`processing`, matching `schema.ts`'s own comment: the
//  handler answers synchronously, before its background cascade
//  (`runCascade`) has had any chance to reach `completed` or `failed`.
//  Modelling four cases here would let a call site write
//  `if status == .completed` against a value this decode can never
//  actually produce.
//
//  AND WHY THIS APP NEVER POLLS FOR THE OTHER TWO. The obvious next
//  question is "so does the client poll `account_deletions` afterwards to
//  learn when it flips to `completed`?" It cannot, by the migration's own
//  design: `account_deletions.user_id` is `on delete set null`, and that
//  foreign key fires in the SAME statement that deletes the `auth.users`
//  row (step 5 of the cascade in the migration's header comment) —
//  BEFORE step 6 sets `status = 'completed'`. The owning-user RLS policy
//  is `user_id = auth.uid()`, so the instant the row could honestly say
//  "completed", it has already stopped being visible to the account that
//  asked. A client polling this table would see the row right up until
//  the moment it succeeds, then see it vanish — which is not a signal any
//  UI can act on as "done" without lying about how it knows. This is why
//  `AccountDeletionViewModel`/`AccountDeletionView` never claim
//  completion: they report the request as accepted and irreversible, then
//  sign out, which is the only honest thing this DTO's shape supports.
//

import Foundation

/// A successful `DELETE /account` response. Only ever seen when the
/// server accepted the request; network/auth/rate-limit/server failures
/// surface as a thrown `AstraError` instead, per `AstraAPIClient`.
public struct AccountDeletionStatus: Decodable, Equatable, Sendable {
    /// Whether the `account_deletions` job this call points at is brand
    /// new or was already running before this call was made. The two are
    /// indistinguishable on the wire — `schema.ts` sends no such flag,
    /// only the server-internal `AccountDeletionRepository.requestDeletion`
    /// knows `freshlyRequested` — so callers show the same "in progress,
    /// cannot be undone" outcome for both rather than guessing at a
    /// distinction the response cannot support.
    public enum RequestState: String, Decodable, Equatable, Sendable {
        case pending
        case processing
    }

    public let deletionID: UUID
    public let status: RequestState

    enum CodingKeys: String, CodingKey {
        case deletionID = "deletion_id"
        case status
    }

    public init(deletionID: UUID, status: RequestState) {
        self.deletionID = deletionID
        self.status = status
    }
}
