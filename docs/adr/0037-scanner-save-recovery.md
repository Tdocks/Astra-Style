# ADR 0037: Durable scanner save recovery

Status: Accepted implementation direction; implementation and acceptance pending.
Date: 2026-10-08
References: master spec offline behavior; ADR 0005 conflict resolution.

## Context

CaptureDraftStore and scanner retry identities currently live only in memory.
A process exit around a database write can lose the identity needed to establish
whether that garment was already saved. Offline mutation enqueue now throws on
persistence failure, but that does not cover a crash before the enqueue happens.

## Decision

Persist an owner-scoped scanner save journal before the first garment write.
Store stable garment/photo IDs, encoded garment/photo metadata, source and
optional cutout paths, and creation time. Keep photo bytes in their existing
owner-scoped local file or private Storage object; do not duplicate them in
SwiftData. Persist final cutout metadata before writing image rows.

After session restoration, reconcile only journal records owned by the active
account. Recheck account identity around suspended work. Use a direct remote
read that distinguishes absent rows from network failure; cached reads cannot
prove a remote commit. If the garment exists, ensure its stable photo records
without overwriting newer remote garment fields. If it is absent, replay the
same IDs. If the result is uncertain, retain the journal for another attempt.

Clear a journal only after confirmed remote persistence or successful durable
offline enqueue, which then becomes the recovery authority. Failed persistence
must remain visible and must not discard the draft or referenced photos.
Guest-local paths require canonical owner validation and an existing local file.
No recovery operation may process another account's journal or bypass caps.

## Acceptance

Verify restart round-trip, lost-response reconciliation without duplicate IDs,
pre-write crash recovery, preservation of newer remote edits, queue persistence
failure, account isolation/switching, guest file absence, and idempotent image
replay. Include a real persisted-container relaunch check in addition to mocks.
This decision does not establish offline remote-image rendering or camera/device
acceptance; those remain separate requirements.
