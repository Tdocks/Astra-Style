# 0006. `@Observable` and structured concurrency over Combine

## Status

Accepted

## Context

§8 specifies "Observation framework using `@Observable`" and "structured concurrency
with async/await" as the state-management approach, with feature-level state living
in `@Observable` view models and local ephemeral UI state in `@State`. The app
targets iOS 18+ exclusively (§0 platform line), so there is no need to support OS
versions that predate the Observation framework (introduced iOS 17) or to bridge to
older `ObservableObject`/Combine-based patterns for backward compatibility.

Combine remains a fully supported, mature Apple framework and is the incumbent
pattern in most existing SwiftUI codebases (`ObservableObject`, `@Published`,
`.sink`), including for async event streams, debounced search, and network response
pipelines.

## Decision

Use `@Observable` (the Observation framework) for all feature-level and shared view
model state, and structured concurrency (`async`/`await`, `Task`, `AsyncSequence`)
for all asynchronous work — networking, Supabase calls, Edge Function polling
(e.g. Studio generation status), camera capture pipelines, and sync queue draining.
Combine is not used as the app's general-purpose reactive/async substrate. Combine
may still appear only where a specific Apple system API's most direct integration
point is a Combine publisher (rare, and to be wrapped at the boundary into an
`AsyncSequence` rather than propagated through the app).

## Consequences

### Positive

- `@Observable` view models only trigger SwiftUI view updates for properties a view
  actually reads, unlike `ObservableObject`/`@Published`, which invalidates a view on
  any `@Published` change regardless of whether that property is used — a real,
  measurable win for the Closet grid and Home Daily Brief's §20 60fps/500ms targets
  where over-invalidation is a common source of scroll jank.
- `async`/`await` reads linearly for the exact workflows this app has a lot of:
  "capture image → upload → poll analysis status → update UI" (§12) and
  "submit Studio job → poll `/studio/status/:id` → update UI" (§13) are naturally
  sequential async operations, not event streams — Combine's operator chains
  (`flatMap`, `debounce`, `catch`) add ceremony here that async/await avoids.
  Structured concurrency's automatic cancellation propagation (a `Task` cancelled
  when its view disappears) maps directly onto "user navigated away mid-generation,"
  which is exactly the failure mode Studio polling needs to handle cleanly.
- One concurrency/reactive paradigm in the codebase, not two, is a real onboarding
  and code-review simplification — a contributor does not need to know both Combine
  operator semantics and async/await to read any given file.
- `@Observable` composes more naturally with Swift 6 strict concurrency's actor
  isolation model (types conform to `Observable` without needing to also reason
  about `Published`'s thread-hop behavior).

### Negative (real costs, named)

- **This forecloses backward compatibility below iOS 17/18 permanently** — a
  Combine/`ObservableObject` fallback is not something that can be quietly added
  later without touching every view model; if a future business decision requires
  supporting older iOS versions, this is a significant rewrite, not a flag flip.
  (The spec's iOS 18+ floor makes this an accepted, not hidden, cost.)
- **Debounced/throttled continuous input (live search-as-you-type in Discover or
  product search, for example) is a place Combine's operators are genuinely more
  ergonomic than hand-rolled `AsyncSequence` + `Task` debouncing.** The team will
  need a small, deliberately-built debounce utility over `AsyncSequence` (or
  `Task.sleep`-based cancellation) for these cases; this is real code that Combine
  would have provided off the shelf.
- Some third-party SDKs (payment, analytics, or a future affiliate feed SDK) may
  expose Combine publishers as their primary or only async interface; every such
  integration point requires a small adapter to bridge into async/await
  (`AsyncStream`/`withCheckedContinuation`), which is boilerplate that a
  Combine-native app would not need.
- `@Observable`'s selective-invalidation behavior can occasionally *hide* a bug
  where a view was expected to update but doesn't, because the view happens not to
  read the changed property in its `body` — this failure mode is different from, and
  can be less obvious than, Combine's "everything updates, maybe too often" failure
  mode, and engineers used to `ObservableObject` semantics need to actively unlearn
  the assumption that any state change on the object always refreshes any view
  holding a reference to it.
- Observation framework tooling (Instruments support, third-party debugging
  libraries) is younger and less battle-tested industry-wide than Combine's, which
  has several release-years of accumulated tooling and community troubleshooting
  content.

## Alternatives Considered

- **Combine + `ObservableObject` throughout, as most existing SwiftUI codebases still
  do.** Rejected: no compatibility need (iOS 18+ floor removes the main reason to
  prefer the older pattern), and the selective-invalidation performance win for
  scroll-heavy screens (Closet grid) is concrete and measurable, not theoretical.
- **RxSwift or another third-party reactive framework.** Rejected: adds a
  third-party dependency for a problem Apple's own frameworks now solve natively;
  would also need an ADR of its own per CLAUDE.md's "no dependency without an ADR"
  rule and there is no capability gap here that justifies the cost.
- **Redux-style unidirectional state (TCA/Composable Architecture or similar).**
  Rejected for v1: valuable for very large, highly-shared-state apps, but adds a
  steep learning curve and significant boilerplate (actions, reducers, stores) that
  is not justified by this app's per-feature `@Observable` view model boundaries
  (§8's feature-first modular architecture already gives most of the isolation
  benefit TCA would provide, at much lower ceremony cost).
