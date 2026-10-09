# Monthly Review acceptance — 2026-10-09

Scope: P7-HOME-03 and master spec §6.23. This pass finishes Monthly Review;
no new TestFlight build is being cut for it.

## Existing authoring and persistence acceptance

The prior full native suite passed 1,136 tests, including owner-scoped review
cache reuse, invalidation when facts change, failed-cache-read protection,
save-only retry without another provider charge, same-thread continuation,
V6-to-V7 store upgrade, reopening and owner cache purge. The Monthly Review
simulator authoring and conversation flow passed in 38.439 seconds.

One bounded hosted provider request returned HTTP 200 from gpt-5.6-luna,
with no fallback, escalation or tool calls. Its structured summary used the
supplied measured facts, proposed a next priority and challenge, and expressly
acknowledged missing versatility/weather/occasion measurements. Thread and
assistant message persisted. Fixture owner
f6c09551-325c-48a3-ad6d-c22e2cfafbd1 was deleted normally (202; receipt
2b240302-60e8-4518-8975-ba3f29ad6c9f). Root independently confirmed zero Auth,
thread and assistant-message rows. This provider leg verifies authoring from
supplied facts; it alone does not verify the production monthly data queries.

## Completed native pass

Home opens the last completed calendar month. Paginated owner-scoped history
includes archived items and purchases added to the closet after their purchase
month without replacing the active closet cache. Civil purchase dates and
instant-based creation/wear events use their appropriate month boundaries.
Wears use a true exclusive end, retaining sub-millisecond events before midnight.
Repeated outfit wears contribute each recorded event to garment use. Evaluation
selection is bounded by month end, so a later assessment cannot erase the older
assessment for the elapsed month.

Current score measurements are captured only under the current month for future
comparisons. Elapsed reviews read historical scores, reject captures outside the
month they claim, and explicitly state when a comparison is unavailable. They do
not backdate today's score. Account ownership is checked throughout aggregation.
Underuse is derived from recorded wears and the saved outfit's persisted pieces;
this does not reconstruct deleted or changed historical outfit compositions.

All 21 tests across Monthly Review facts, purchase attribution, authored review,
cache and summary persistence passed. The preceding run also passed the Monthly
Review/Kyra simulator flow. Strict lint across the repository, column drift and
progress checks passed. Physical-device acceptance remains separate.

No version bump, archive or TestFlight upload was performed for this pass. Native
changes are newer than TestFlight build 32 and will ship in a later batch.

## Hosted monthly data acceptance

Ordinary authenticated-caller reads against a disposable owner verified September
2026 in America/New_York: `[2026-09-01T04:00Z, 2026-10-01T04:00Z)`. Three new
items and $210 recorded spend included an archived September garment. Three wear
events spanned two outfits. Start-boundary wear was included, while pre-start
and exact next-month-start records were excluded. The next-month purchase was
excluded; an owned purchase joined to its evaluation with five outfit unlocks.
Shared product catalog rows were only read. No provider, media or mail calls
were made. The opt-in hosted Monthly Review harness passes format, lint and type
checks.

Owner 7a441376-4ce6-4cb6-9463-ed6e4565375e was deleted normally (202; receipt
ce067548-f14b-4e88-b340-eab3686eac38). Independent SQL confirmed zero remaining
Auth, closet, outfit, wear and product-evaluation rows. These checks establish
hosted fixture queries and RLS, while the native tests verify the screen's actual
query, aggregation and navigation paths.
