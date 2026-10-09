# ADR 0031 — Server-owned Kyra preview confirmations

Date: 2026-10-08
Status: Accepted; deployment and full acceptance pending

## Decision

Kyra uses a service-role client exclusively for private preview confirmation
records. The verified caller ID and an owned conversation scope every operation.
Caller-JWT clients continue to handle messages, wardrobe reads and reference-photo
consent reads. The model receives eligible reference UUIDs, never private paths
or signed image URLs. A saved path alone is insufficient: the current Studio
consent receipt must also exist.

A confirmation references the exact saved assistant question, normalized preview
selection and expiry. The handler persists a deterministic allowance disclosure
before preparing that record. Affirmative replies use the confirmation UUID as
the Studio submission key across turns; explicit generation commands use their
persisted user-message UUID. Studio's existing atomic ledger enforces deduplication
and quota. Cancellation and successful submission close pending records.

## Reason

Messages and model metadata are client-writable and cannot attest server-owned
cost confirmation. Caller RLS cannot grant writes to this private authority table
without letting a client forge approval context. This is a narrow exception to
Kyra's previous caller-client-only wiring, not a privileged wardrobe access path.

## Verification and remaining work

Scratch SQL verifies owner/thread/prompt binding and denied client preparation.
131 Kyra tests pass, including saved-question-before-preparation ordering,
reference filtering and cross-turn request-key reuse. Full ask/yes/cancel,
concurrency and hosted acceptance remain pending. Native preview-job presentation
and high-resolution support remain separate unfinished work. Deployment must apply
the confirmation migration before publishing the new Kyra function.

## Reservation ordering follow-up

A new unapplied migration adds a row lock and final closed/expiry check for an existing owner-scoped saved confirmation whose UUID is the submission key. The lock is held through allowance/job reservation. A cancellation committed before that check blocks a new submission; an already accepted job remains replayable after closure. The full local SQL suite passed, including cancelled/expired rejection without allowance use and accepted-job replay after closure.

Concurrent cancellation/submission acceptance and deployment remain open. This check identifies existing confirmation records by request key; missing/deleted confirmation records are not distinguished from ordinary native submission keys. An explicit confirmation-origin marker is still needed to reject missing-record chat submissions, rather than claiming every stale proposal is covered.
