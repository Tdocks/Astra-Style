# CLAUDE.md — Repository conventions for AI coding agents

This file is read by Claude Code and similar agents at the start of every session
working on this codebase. It is a set of binding conventions, not background
reading — follow it by default, and deviate only with a documented reason (an ADR
for architectural deviations, a code comment for local ones).

> ## ▶ CURRENT TASKS (pick the file that matches you)
>
> | Agent | Open first |
> |---|---|
> | **Website / privacy / astra-style.com** | **[`web/CLAUDE.md`](web/CLAUDE.md)** — sources in `web/` + `legal/` (not under `ios/`) |
> | **Cloudflare deploy** | **[`web/GATE.md`](web/GATE.md)** |
> | **Claude Code on the owner's Mac (iOS)** | **[`START_HERE.md`](START_HERE.md)** — internal TestFlight cut |
>
> Also see root [`AGENTS.md`](AGENTS.md). Do not hunt through `HANDOFF.md` first.
> `cc7923cf` ("Pre-build groundwork…") is an **old** ancestor, not unfinished tip work.

## What Astra Style is

Astra Style is a native iOS app (Swift 6, SwiftUI, iOS 18+) that acts as a premium
personal stylist for men, built around a companion named Kyra who tells the user
what to wear, why, and what to buy next. The core moat is the Wardrobe Graph — every
garment, outfit, occasion, and preference the user has, modeled so the app can
quantify which purchase unlocks the most outfits and build a coherent wardrobe over
time. The backend is Supabase (Postgres, Auth, Storage, Edge Functions, pgvector),
and the app talks only to Astra's own Edge Functions, never directly to an AI
provider.

## Document hierarchy — read this before touching anything

0. **Right now:** Cloudflare → [`web/GATE.md`](web/GATE.md) (astra-style.com).
   Mac/iOS → [`START_HERE.md`](START_HERE.md) (TestFlight). See [`AGENTS.md`](AGENTS.md).
1. **`docs/00-master-spec.md` is the source of truth.** Every screen, data model,
   endpoint, and requirement in this codebase traces back to it. If you're unsure
   what a feature should do, the answer is in there — read the relevant section
   before guessing.
2. **`docs/adr/*.md` record decisions that override a naive reading of the spec** —
   not the product requirements, but the *how*. Example: the spec says "Use
   relational tables plus computed compatibility, not a graph database" (§10);
   `docs/adr/0003-relational-wardrobe-graph.md` is the fuller record of why, and the
   conditions under which that decision should be revisited. Read the relevant ADR
   before proposing an architectural change that contradicts one — either follow
   the ADR or write a new one that supersedes it. Don't silently drift from a
   documented decision.
3. **If the spec and the code disagree, the spec wins and the code is a bug.** Do
   not treat existing code as de facto correct just because it's there. If you find
   code that contradicts `docs/00-master-spec.md` or an ADR, flag it and fix the
   code (or raise the conflict if you believe the spec itself needs to change — that
   requires a human decision, not a silent code-side deviation).
4. **`docs/11-risk-register.md`** names the risks this build is actually exposed
   to, with leading indicators and mitigations per phase — useful context for why
   certain things (correction UX, feedback instrumentation, cost rate-limiting) are
   treated as load-bearing rather than optional polish.

## Repo layout

```
docs/                    Specs, ADRs, roadmap, task breakdown — read before writing code
  00-master-spec.md       Authoritative product/technical spec
  01-build-roadmap.md      Phase-by-phase build plan (in progress, written in parallel)
  02-task-breakdown.md     Concrete tickets per phase (in progress, written in parallel)
  04-data-model.md         Detailed schema reference
  05-wardrobe-graph.md     Compatibility scoring, wardrobe score, graph concepts
  06-kyra-orchestration.md Kyra's context packet, tool calls, response schema
  07-design-system.md      Full design token reference
  08-provider-abstraction.md  The five AI provider protocols in detail
  11-risk-register.md     Risk register — read this before shipping anything Kyra-facing
  adr/                     Architecture Decision Records, numbered 0001+
ios/                      The Xcode project (generated — see ios/README.md)
  project.yml              XcodeGen source of truth; DO NOT hand-edit the .xcodeproj
  Config/                  .xcconfig files (Base/Debug/Release) — secrets live in
                           Config/Secrets.xcconfig, which is gitignored
  AstraStyle/              App source, organized feature-first (see §8 of the spec)
supabase/                 Backend
  migrations/              Append-only SQL migrations — see rules below
  functions/               Edge Functions (Deno/TypeScript) — the only place
                           provider API keys and service-role keys live
brand/                    Brand assets — logos, reference screenshots, marble textures
CLAUDE.md                 This file
README.md                 Repo front door
```

## Swift conventions

- **Swift 6 strict concurrency is on.** Code must compile clean under strict
  concurrency checking — no reaching for `@unchecked Sendable` or
  `@preconcurrency` to silence a warning you haven't actually reasoned through.
- **View models are `@Observable`, not `ObservableObject`/Combine.** See
  `docs/adr/0006-observation-over-combine.md`. Combine only appears at the narrow
  boundary of a system API that has no other integration point, wrapped into
  `AsyncSequence` immediately, never propagated through app code.
- **`@MainActor` rules:** anything that touches SwiftUI view state or a view model
  observed by a view is `@MainActor`. Repository/service implementations that do
  network or disk I/O are not `@MainActor` by default — they hop to the main actor
  only for the final state update, not for the I/O itself. Don't mark a whole
  repository `@MainActor` just to make the compiler stop complaining; isolate
  correctly instead.
- **No force unwraps, no `try!`, no `as!`.** If a value is genuinely guaranteed
  non-nil by a prior check, express that with `guard let`/`if let`, not `!`. A
  crash from a force unwrap in production is always a bug, never acceptable
  "shouldn't happen" code.
- **No network calls in views.** Views call into `@Observable` view models; view
  models call repository protocols (§8); repositories talk to Supabase/Edge
  Functions. A `URLSession` call, a Supabase client call, or an Edge Function
  invocation directly inside a `View`'s body or a `.task {}` block bypassing the
  view model layer is a structural violation, not a style nit — fix it, don't wait
  for review to catch it.
- **Protocol-first for anything crossing a module/feature boundary.** Every
  repository and service listed in §8 of the master spec (`AuthRepository`,
  `ClosetRepository`, `KyraRepository`, `WeatherService`, etc.) is consumed as a
  protocol everywhere outside its own implementation file. This is what makes
  mocking possible (see Testing below) and what keeps `AppContainer`
  (`docs/adr/0007-protocol-di-no-framework.md`) the single place concrete wiring
  happens.

## Design system rule — read this twice

**Never hardcode a color, font, spacing value, or corner radius. Always use the
`Astra*` design tokens.** This is the single most-violated rule in practice on
projects like this one, because a hardcoded `Color(hex: "#0D0D0D")` or `.padding(20)`
compiles fine, looks correct in the moment, and then silently breaks dark/light mode
parity, Dynamic Type, or a future token rename — and nobody notices until a snapshot
test or a design review catches it much later, if ever. Treat every hardcoded value
as a bug at review time, not a style preference.

```swift
// WRONG — hardcoded values, will drift from the design system the moment
// backgroundPrimary or the spacing scale changes, and breaks light-mode parity
// (§3's dark-mode/light-mode token pairs) since there is no equivalent lookup.
struct WrongCard: View {
    var body: some View {
        Text("Kyra's Pick")
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(Color(red: 0.84, green: 0.71, blue: 0.42)) // champagne, guessed
            .padding(20)
            .background(Color(hex: "#1B1B1B"))
            .cornerRadius(18)
    }
}

// RIGHT — every value is a design-system token; light/dark mode, Dynamic Type,
// and any future token change (e.g. retuning accentChampagne) propagate for free.
struct RightCard: View {
    var body: some View {
        Text("Kyra's Pick")
            .font(AstraFont.headline)
            .foregroundStyle(AstraColor.accentChampagne)
            .padding(AstraSpacing.pagePadding)
            .background(AstraColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card))
    }
}
```

If a value you need doesn't exist as a token yet, add it to the design system
(`Core/DesignSystem/`) and reference it from there — don't inline it "just this
once." Every text style, color, spacing unit, and radius in `docs/07-design-system.md`
(sourced from §3 of the master spec) has a corresponding token; there should never
be a legitimate reason to reach for a raw literal in a view.

## Supabase conventions

- **Every user-owned table needs Row Level Security**, enforcing
  `user_id = auth.uid()` at minimum. A new table without an RLS policy is not
  "TODO later" — it does not ship. See `docs/00-master-spec.md` §15 and
  `docs/adr/0002-supabase-as-backend.md`.
- **Migrations are append-only.** Once a migration has been applied (to any shared
  environment, not just production), it is never edited — write a new migration to
  change or correct it. Editing an already-applied migration file produces drift
  between environments that ran it before the edit and environments that run it
  after, which is exactly the kind of bug that's invisible until it corrupts data.
- **Service-role keys exist only in Edge Functions.** Never reference
  `SUPABASE_SERVICE_ROLE_KEY` (or any provider API key from §25 of the spec) from
  iOS code, a client-side config file, or anything that ships in the app bundle. The
  app receives only `SUPABASE_URL` and `SUPABASE_ANON_KEY` — if you find yourself
  needing a privileged key on-device, the operation belongs in an Edge Function
  instead.

## Kyra conventions

- **Kyra returns structured JSON payloads to the client, never raw prose.** The
  response schema (§11 of the master spec: `message`, `intent`, `cards`,
  `suggested_actions`, `memory_proposals`, `confidence`) is the contract. The iOS
  client renders structured cards; it does not parse or reformat free-text model
  output client-side.
- **Guardrails (§11 of the master spec) are not optional and are not client-side.**
  Never imply exact fit from imagery, never give medical body-change advice, never
  let affiliate availability influence a verdict (see
  `docs/11-risk-register.md` risk 8 for how this is audited), and always disclose
  affiliate relationships. These are enforced server-side in the Edge Functions, so
  a compromised or modified client cannot bypass them (see
  `docs/adr/0004-provider-neutral-ai-layer.md`).
- **Every generated image carries the estimate badge.** Any Style Studio output
  rendered anywhere in the app — hero view, comparison view, lookbook, share sheet —
  must display the generated-image disclaimer/label. Do not add a new surface that
  displays a `studio_generations` result without it.

## Testing expectations before a change is considered done

See `docs/adr/0012-testing-strategy.md` for the full rationale. In short, before
calling a change complete:

- New pure logic (scoring, cost-per-wear, entitlement resolution, response parsing)
  has Swift Testing unit tests, including edge cases, not just the happy path.
- A new or changed repository has integration tests against the local Supabase CLI
  stack, not just mocked unit tests — an RLS policy bug is invisible to a test that
  mocks the repository protocol.
- A new or visually-changed major screen has snapshot tests across light/dark mode
  and at least one non-default Dynamic Type size.
- If the change touches one of the seven flows in §22's UI test list (onboarding,
  add a garment, generate outfit, mark worn, ask Kyra, paywall/restore, delete
  account), the corresponding UI test still passes.
- The change meets the §22 acceptance quality bar, verbatim:

  > No placeholder lorem ipsum. No dead buttons. No hard-coded user name. No
  > exposed API secrets. No unhandled network failure. No required permission
  > requested before context.

  Treat every item in that list literally. "No dead buttons" means every control
  you add does something, including in states you didn't focus on (loading, empty,
  error). "No hardcoded user name" means don't write `"Good morning, Alex"` as a
  placeholder and move on — wire it to the actual profile. "No unhandled network
  failure" means every network call your change adds has a visible error/retry
  state, not just a happy-path implementation.

## How to pick up work

1. Check `docs/01-build-roadmap.md` for the current phase — the build is
   sequenced (Phase 1 Foundation through Phase 7 Monetization and Hardening, per
   §24 of the master spec), and work should follow that order rather than jumping
   to whichever feature looks most interesting.
2. Check `docs/02-task-breakdown.md` for the concrete ticket describing the work —
   it should map back to a phase and, ultimately, to a section of
   `docs/00-master-spec.md`. If a task doesn't trace back to the spec, ask before
   building it.
3. If you're touching architecture (new dependency, new data flow pattern, new
   provider integration), check `docs/adr/` for an existing decision first. If none
   exists and the change is architecturally significant, write a new ADR rather
   than making the change undocumented.

## What NOT to do

- **Don't add a dependency without an ADR.** This includes SPM packages, not just
  vendored code. A new dependency is a new maintenance and security surface; it
  needs the same "what are the real downsides" treatment every ADR in this repo
  gets, not a one-line justification in a PR description.
- **Don't change the compatibility scoring weights in code.** The weights in §10 of
  the master spec (color 0.25, formality 0.20, silhouette 0.15, etc.) are
  server-configurable by design — see `docs/adr/0003-relational-wardrobe-graph.md`.
  If a weight needs to change, it's a server-side config change, not a client or
  Edge Function code change with a new hardcoded constant.
- **Don't put admin functionality in the iOS app.** §28 of the master spec is
  explicit: curated product management, editorial content, style identity
  definitions, prompt versioning, compatibility weight tuning, feature flags, user
  support lookup, and affiliate disclosure management all belong in a separate
  admin surface, never in the consumer app or its credentials.
- **Don't request a permission outside its triggering context.** Camera only when
  scanning, Photos only when importing, Location only when enabling weather,
  Calendar only when enabling occasion-aware recommendations, Notifications only
  after the user has seen value, Microphone only when using voice input (§7 of the
  master spec). A permission prompt that fires on launch, or on a screen unrelated
  to what it's for, is exactly the failure mode §22's acceptance bar calls out by
  name — fix it before it ships, don't defer it as polish.
