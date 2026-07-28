# 0007. Hand-rolled `AppContainer` over a DI framework

## Status

Accepted

## Context

§8 specifies "protocol-based dependency injection with a root `AppContainer`" and
explicitly says to "avoid a heavy third-party DI framework," naming repository
protocols (`AuthRepository`, `ClosetRepository`, `OutfitRepository`,
`KyraRepository`, `StudioRepository`, `ShoppingRepository`,
`SubscriptionRepository`, `WeatherService`, `CalendarService`). §27 sketches the
root app wiring: `AppContainer.live()` constructed once and injected via
`.environment(appContainer)`. §31 requires every mock implementation to sit behind
the same protocol as its production counterpart, which is a dependency-injection
concern by construction.

Third-party DI frameworks exist for Swift (e.g. reflection-based container
frameworks, or macro-based DI libraries) that offer features like automatic
dependency graph resolution, scoped lifetimes, and compile-time or runtime
validation of the graph.

## Decision

Implement a single `AppContainer` type (or small family of container types — e.g.
a `live` container and a `preview`/`test` container) that holds concrete instances
conforming to the repository and service protocols listed in §8, constructed
explicitly in Swift code with no reflection, code generation, or property-wrapper
magic beyond what `@Observable`/`@Environment` already provide. Every feature
depends on protocols, injected through the container or through explicit
initializer parameters — never on concrete types reached via a service locator
pattern, and never on a third-party DI framework's container or registration API.

## Consequences

### Positive

- Zero dependency risk from a third-party DI library going unmaintained, changing
  its API, or gaining a security advisory — this is a real, if unglamorous,
  reliability property for a solo/small-team codebase's long-term maintainability.
- The entire dependency graph is visible by reading `AppContainer.live()` — there is
  no runtime reflection step or generated code to inspect when a contributor asks
  "what actually implements `ClosetRepository` in production." This is a genuine
  debuggability win over frameworks that resolve dependencies via annotations and
  runtime scanning.
- Compile-time safety: a missing or mistyped dependency is a compiler error at the
  `AppContainer` initializer, not a runtime crash from a DI framework failing to
  resolve a registration.
- Trivially easy to build a `preview`/`test` container substituting mocks for any
  subset of protocols, directly satisfying §31's mock-behind-the-same-protocol
  requirement and SwiftUI preview needs, with no framework-specific test-scoping API
  to learn.
- No macro-expansion or code-generation build step for DI specifically, which keeps
  build times and Xcode's occasionally-fragile macro tooling out of the critical
  path for this particular concern.

### Negative (real costs, named)

- **This is real code the team must write and maintain, not a solved problem
  someone else maintains.** As the number of protocols and features grows, manually
  wiring `AppContainer.live()` becomes a large, flat initializer that is tedious to
  extend and easy to get subtly wrong (e.g. forgetting to wire a new service into
  the `preview` container, silently leaving previews on a stale mock).
- **No automatic lifetime/scoping management.** A DI framework typically offers
  singleton/scoped/transient lifetime semantics out of the box; here, lifetime is
  whatever the hand-written container code does, and getting scoping wrong (e.g.
  accidentally sharing a session-scoped repository instance across two
  authenticated users after a sign-out/sign-in cycle) is a bug the team has to avoid
  by discipline and code review, not by a framework enforcing scope boundaries.
- **No automatic dependency-graph validation.** A misconfigured graph (a
  service depending on another that was never constructed) is caught only by the
  Swift compiler for missing arguments, or at runtime for logic errors — there is no
  framework-level "validate the graph on startup" check to lean on.
- As the app grows past the current ~10 protocols, a flat container can become
  unwieldy; the team will likely need to introduce sub-containers or
  factory functions per feature area to keep `AppContainer` readable, which is
  additional design work a framework might have structured by convention.
- Onboarding a contributor who has used a framework like a reflection-based
  container elsewhere may need a short explanation that "there is no magic here,"
  since the explicit-wiring pattern is less immediately discoverable than framework
  documentation/tutorials for a newcomer used to that ecosystem.

## Alternatives Considered

- **A third-party reflection/macro-based Swift DI framework.** Rejected per §8's
  explicit instruction, and because it would add a dependency (requiring an ADR of
  its own under CLAUDE.md's dependency policy) for a problem that, at this app's
  scale (order of ten protocols, one process, no plugin architecture), does not need
  automatic graph resolution to stay manageable.
- **Global singletons (`ClosetRepository.shared`) instead of injected protocols.**
  Rejected: singletons defeat §31's mock-behind-protocol testability requirement,
  make SwiftUI previews depend on live network/Supabase state unless carefully
  special-cased, and make Swift 6 strict concurrency isolation harder to reason
  about (a global mutable singleton is exactly the shape strict concurrency is
  designed to catch problems in).
- **SwiftUI `@Environment`-only injection with no container type at all** (every
  protocol injected as its own separate environment value). Rejected as the sole
  mechanism: works for view-level access but loses the single obvious place
  (`AppContainer.live()`) to construct and reason about the whole graph at once,
  which the container pattern in §27 explicitly provides.
