# Scanner durability and Studio recovery — 2026-10-09

## Changes

Offline scanner queue enqueue now throws when reading, encoding or saving its SwiftData record fails. The review screen keeps the prepared photo and shows a retry action; it only reports pending analysis after the durable write succeeds. The queue rolls back failed context changes. A regression injects a failed queue write, verifies no false queued state, then retries successfully.

Studio detail reappearance resumes status lookup/polling when its retained state is queued or generating. The existing cancellation behavior remains intact; reopening the same detail reconciles the latest server state instead of leaving a pending image stuck.

## Evidence

A coordinated signed simulator batch passed 45 tests with zero failures, covering offline scanner persistence failure/retry, scanner review/batch behavior, Studio recovery/export, Monthly Review and closet caps. Result bundle: `/Users/tylerdockswell/Library/Developer/Xcode/DerivedData/AstraStyle-dgrnukigkbeplfeyrjfubkcjccfv/Logs/Test/Test-AstraStyle-2026.10.09_17-57-34--0400.xcresult`.

Root recheck passed 15 focused tests and the first-party compiler-warning gate. Strict SwiftLint passed. The direct Supabase SDK is pinned to the verified 2.54.0 version to eliminate local/CI API drift; GitHub CI acceptance remains pending. No new TestFlight build or image-provider render was performed.

## Open

Actual disk failure/relaunch recovery and the new error screen on a physical device remain unverified. Batch enqueue/poll transport uncertainty still needs stable owner/request-to-job replay; simply deleting uploads on an uncertain failure can break an accepted server job, while merely retaining them does not give the user a reliable retry. That follow-up is separate from this patch. Studio live image quality, edits/fidelity and provider acceptance remain open.
