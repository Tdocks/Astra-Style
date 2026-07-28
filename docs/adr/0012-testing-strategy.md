# 0012. Testing strategy: Swift Testing, pyramid shape, snapshot approach

## Status

Accepted

## Context

§22 specifies four categories of test (unit, integration, UI, snapshot) with
concrete required coverage: compatibility scoring, wardrobe score, cost-per-wear,
subscription entitlement logic, offline queue, API-to-local model mapping, and Kyra
structured-response parsing at the unit level; auth lifecycle, closet upload/sync,
Daily Brief generation, product evaluation, Studio job polling, and StoreKit sandbox
purchase at the integration level; full onboarding, add-a-garment, generate-outfit,
mark-worn, ask-Kyra, paywall/restore, and delete-account at the UI level; and major
screens across light/dark mode, Dynamic Type sizes, and empty/loading/error states
at the snapshot level. §22 also states an acceptance quality bar (no lorem ipsum, no
dead buttons, no hardcoded user name, no exposed secrets, no unhandled network
failure, no permission requested before context) that is a review checklist as much
as a test suite.

Apple ships two test frameworks usable in a Swift 6/iOS 18+ project: the long-
standing XCTest, and Swift Testing (the `import Testing` / `@Test` macro-based
framework introduced alongside Swift 6), which XCTest UI testing (`XCUIApplication`)
still underlies for actual UI automation.

## Decision

Use **Swift Testing** (`@Test`, `#expect`, `@Suite`) as the default framework for
unit and integration tests. Use **XCUITest** (`XCUIApplication`-based, which Swift
Testing does not replace) for the UI test category, since Swift Testing does not
provide its own UI automation driver. Use snapshot testing via a lightweight,
protocol-first snapshot library wrapping SwiftUI view rendering, run in Swift
Testing's harness.

### Test pyramid shape for this app

The pyramid is deliberately unit-heavy but not unit-only, reflecting where this
app's actual risk concentrates:

- **Unit tests (widest layer):** the compatibility scoring formula (§10's weighted
  sum), wardrobe score composite (§10), cost-per-wear math, subscription entitlement
  resolution (ADR 0009's reconciliation logic), the SwiftData offline queue
  (ADR 0005), API↔local model mapping, and Kyra structured-response JSON parsing
  (§11's response schema) — all pure or near-pure logic, cheap to test exhaustively,
  and exactly the logic where a silent bug produces a wrong recommendation without
  any crash to signal it (the core product-risk failure mode named in
  `docs/11-risk-register.md`). This layer should have the deepest, most exhaustive
  test coverage in the codebase, including adversarial/edge-case inputs (empty
  closet, single-item closet, malformed Kyra JSON, expired subscription mid-session).
- **Integration tests (middle layer):** repository implementations against a real
  local Supabase stack (via the Supabase CLI, not a hosted project) — auth
  lifecycle, closet upload/sync round-trips, Daily Brief generation, product
  evaluation, Studio job polling state machine, StoreKit sandbox purchase flow.
  These exercise real network/serialization boundaries and RLS policies, which pure
  unit tests cannot validate (an RLS policy bug is invisible to a unit test that
  mocks the repository protocol).
- **UI tests (thin layer, expensive, flakiness-prone):** exactly the flows §22
  lists — full onboarding, add a garment, generate an outfit, mark worn, ask Kyra,
  paywall + restore, delete account — as end-to-end smoke tests confirming the
  screens are wired together and no button is dead (§22's "no dead buttons" bar).
  This layer is intentionally kept to the specific flows §22 names, not expanded
  to cover every screen permutation, because UI tests are the slowest and most
  flaky layer and over-investing here has poor ROI relative to unit coverage of the
  same logic.
- **Snapshot tests (orthogonal to the pyramid, not a layer within it):** cover
  visual regression across the matrix §22 requires (light/dark × Dynamic Type sizes
  × empty/loading/error states) for major screens (Home Daily Brief, Closet grid,
  Item detail, Outfit detail, Style Studio, Paywall). This is the layer that most
  directly guards the design-system discipline in `CLAUDE.md` (no hardcoded colors
  breaking dark mode, no layout collapse at accessibility text sizes).

### Snapshot testing approach for §22

Snapshot tests render each covered screen's SwiftUI view tree to an image (or a
deterministic serialized layout representation) under a fixed set of trait
combinations — light/dark appearance × at minimum the default, `.accessibility3`,
and `.accessibility5` Dynamic Type sizes × the state variants that screen supports
(loading/skeleton, empty, populated, error/offline per §21) — and diff against a
committed reference image per combination. A snapshot test failure on an
unintentional visual change is expected and required to fail CI; an intentional
visual change requires explicitly re-recording the reference snapshot as part of
that PR, which keeps snapshot changes visible in code review rather than silently
auto-accepted. Snapshot tests use mock repositories/`AppContainer` (ADR 0007), never
live network calls, so they are deterministic and runnable offline.

### CI versus local

- **Runs in CI on every PR:** all unit tests, all integration tests against a local
  Supabase CLI stack spun up in the CI job (not the hosted project — no CI job ever
  touches production Supabase or real provider API keys), and all snapshot tests.
  These are fast and deterministic enough to gate merges.
- **Runs locally, not gated in CI by default:** the full UI test suite, because
  simulator-based `XCUIApplication` runs are slow and comparatively flaky in shared
  CI runners; UI tests are run locally before a release-candidate build and in a
  scheduled (not per-PR) CI job, so they still exist as a safety net without
  blocking every merge on their flakiness. StoreKit sandbox purchase testing
  specifically also requires local Xcode + StoreKit configuration file testing that
  is impractical to fully automate in headless CI.
- **Provider-backed tests (real vendor calls to reasoning/vision/image-gen
  providers) never run in CI at all** — they run manually/locally against a
  developer's own provider sandbox credentials, or against recorded fixtures
  replayed in CI, because real provider calls in CI would be slow, costly (see the
  cost-risk arithmetic in `docs/11-risk-register.md`), non-deterministic, and would
  require provider secrets to exist in CI, which is itself a risk (§14, §25's secret
  handling requirements) the team should not accept for a use case (regression
  testing) that fixture replay serves just as well.

## Consequences

### Positive

- Swift Testing's `#expect`/`#require` macros produce clearer failure output
  (showing the actual expression and values) than XCTest's `XCTAssert*` family,
  which is a real day-to-day productivity and debuggability win given how much of
  this app's correctness lives in numeric scoring logic (compatibility, wardrobe
  score) where seeing the actual computed values on failure matters.
- Parameterized tests (`@Test(arguments:)`) are a natural fit for the compatibility
  scoring formula and Kyra response-parsing tests, which need to run the same
  assertion across many input combinations (different weight configurations,
  malformed JSON shapes) — Swift Testing supports this natively where XCTest
  requires more boilerplate.
- The unit-heavy pyramid puts the deepest test investment exactly where a bug is
  both cheap to catch and most damaging if missed: a wrong compatibility weight or
  a wardrobe-score bug ships a silently-mediocre recommendation with no crash, no
  error state, nothing to signal the failure short of a human noticing the app's
  taste is off — which is the core product risk this app faces.
- Keeping provider-backed tests out of CI protects both CI cost and CI
  determinism, and keeps provider secrets out of CI's secret store entirely for the
  test suite's sake (secrets that must exist in CI only for deployment/Edge
  Function publishing, per §25, is a smaller, more auditable surface).

### Negative (real costs, named)

- **Swift Testing is newer than XCTest and has a smaller surrounding ecosystem** —
  fewer third-party assertion helpers, less Stack Overflow/community troubleshooting
  content at the time of this decision, and some CI/reporting tooling (test result
  parsers, flaky-test dashboards) has better first-class XCTest support than Swift
  Testing support, which may require using XCTest-compatible result bundle
  translation to keep existing CI reporting tooling working.
- **Mixing two frameworks (Swift Testing for unit/integration, XCTest/XCUITest for
  UI) is inherently more complex than picking one framework for everything** — a
  contributor needs to know both `@Test`/`#expect` and `XCTestCase`/`XCTAssert`
  conventions, and shared test helpers/fixtures sometimes need two versions (one
  callable from each framework) rather than one.
- **Snapshot tests are inherently fragile to legitimate, intentional visual
  changes** — every real design-token tweak (a color, spacing, or font change) will
  break snapshot tests by design, and the re-recording workflow, if not disciplined,
  becomes something contributors rubber-stamp without actually reviewing the visual
  diff, defeating the purpose of the check. This requires an actual code-review
  norm (look at the diff image, don't just accept the new snapshot), which is a
  process commitment, not something the tooling itself enforces.
- The matrix specified (light/dark × multiple Dynamic Type sizes × multiple states)
  multiplies quickly — six major screens × 2 appearances × 3 text sizes × ~3 states
  each is over 100 reference images, which is real storage/repo-size overhead and
  real CI time even though each individual snapshot render is fast; this needs
  active curation (not every screen needs every combination) rather than mechanical
  full-matrix generation for every screen in the app.
- Keeping UI tests out of the per-PR CI gate means a UI-breaking regression
  (a genuinely dead button, §22's explicit bar) can land on `main` and only be
  caught by the scheduled run or a local pre-release pass, which is a real
  detection-latency cost traded for CI speed/stability — this is an explicit,
  accepted tradeoff, not a free lunch, and should be revisited if dead-button
  regressions start reaching TestFlight builds.
- Local-only StoreKit sandbox testing means CI cannot fully gate subscription
  correctness; a StoreKit-affecting regression is caught only when a human runs the
  local sandbox flow, which places real weight on release-checklist discipline
  rather than automated gating for one of the app's highest-stakes flows
  (getting entitlement wrong either loses revenue or angers paying users).

## Alternatives Considered

- **XCTest for everything, including unit/integration.** Rejected: Swift Testing is
  Apple's forward-looking framework for exactly this Swift 6/iOS 18+ codebase, and
  its parameterized-test and clearer-assertion ergonomics are a genuine win for the
  scoring-logic-heavy unit layer this app needs most; there is no compatibility
  reason to prefer XCTest here since the app has no legacy test suite to preserve.
- **A UI-test-heavy pyramid (inverted, testing mostly through the UI layer).**
  Rejected: UI tests are the slowest and flakiest layer and, critically, cannot
  economically cover the combinatorial scoring-logic edge cases (many weight
  configurations, many malformed-JSON shapes) that unit tests cover cheaply — an
  inverted pyramid would under-test exactly the silent-mediocrity failure mode that
  is this app's biggest product risk.
- **Running the full test suite including UI tests on every PR in CI.** Rejected for
  now on cost/flakiness/latency grounds (above); revisit if CI infrastructure
  investment (dedicated, less-flaky simulator runners) makes this affordable without
  materially slowing the PR feedback loop.
- **No dedicated snapshot testing; rely on manual QA for visual regressions.**
  Rejected: §22 explicitly requires snapshot tests, and manual QA does not scale to
  catching a design-token regression across every Dynamic Type size and both
  appearance modes on every change — this is exactly the kind of mechanical,
  repetitive check automation is suited for and humans are bad at doing
  exhaustively.
