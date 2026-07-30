# Astra Style

**Your style. Your journey. Your best self.**

Astra Style is a native iOS app that acts as a premium personal stylist and
wardrobe operating system for men. Kyra, the app's AI stylist, learns a user's
wardrobe, body, lifestyle, and taste, then tells him what to wear each morning,
why it works, and what — if anything — he should buy next. The core moat is the
Wardrobe Graph: every garment, outfit, occasion, and preference is modeled so the
app can quantify which purchase unlocks the most outfits and build a coherent
wardrobe over months and years, rather than functioning as a generic shopping app
or outfit randomizer.

## Status

**Phase 2 of 7 — Identity — in progress.** Phase 1 (Foundation) is substantively
complete: auth, guest mode, the design system, navigation, the repository layer,
and a Postgres schema with row-level security applied to production. Onboarding
is built through the style-preference quiz. The app does not yet have a closet,
outfit intelligence, Kyra, Style Studio, or subscriptions.

**Per-ticket status for all 178 tickets lives in
[`docs/03-progress.md`](docs/03-progress.md)** — that file, not this section, is
the place to look before starting work. It records what is Done, Partial, Not
started, or genuinely Unverifiable, with evidence for each, and it is enforced by
`scripts/check_progress.py` in CI so it cannot quietly drift from the code.

`docs/01-build-roadmap.md` holds the phase plan and `docs/11-risk-register.md`
the risks being actively tracked.

## Repo layout

```
docs/            Specs, architecture decisions, roadmap, and task breakdown
ios/             The native iOS app (Swift 6, SwiftUI, XcodeGen-generated project)
supabase/        Backend: Postgres migrations and Edge Functions
brand/           Brand assets — logos, reference screenshots, textures
CLAUDE.md        Conventions for AI coding agents working in this repo
README.md        This file
```

## Quick start — iOS

```bash
# 1. Generate the Xcode project from project.yml (the .xcodeproj itself is
#    build output and is not checked in — see docs/adr/0008-xcodegen-project-generation.md)
brew install xcodegen   # if not already installed
cd ios
xcodegen generate

# 2. Configure secrets. Copy the template and fill in your local values —
#    Config/Secrets.xcconfig is gitignored and must never be committed.
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
#    Required: SUPABASE_URL, SUPABASE_ANON_KEY (see docs/00-master-spec.md §25 —
#    the app never receives provider API keys or the Supabase service-role key).

# 3. Open and run.
open AstraStyle.xcodeproj
```

Full setup detail — StoreKit configuration, provisioning, and target-by-target
build settings — lives in `ios/README.md`.

## Quick start — Supabase

```bash
# 1. Install the Supabase CLI if you don't have it.
brew install supabase/tap/supabase

# 2. Start the local stack (Postgres, Auth, Storage, Edge Functions runtime).
cd supabase
supabase start

# 3. Apply migrations. Migrations are append-only — see CLAUDE.md before
#    editing anything under migrations/.
supabase db reset   # applies all migrations to a fresh local database

# 4. Serve Edge Functions locally.
supabase functions serve
```

Full backend setup — environment variables, deploying migrations to a hosted
project, and deploying Edge Functions — lives in `supabase/README.md`.

## Documentation index

| Doc | Description |
|---|---|
| [`docs/00-master-spec.md`](docs/00-master-spec.md) | The authoritative product and technical specification. Every other doc traces back to this. |
| [`docs/01-build-roadmap.md`](docs/01-build-roadmap.md) | Phase-by-phase build plan (Phase 1 Foundation → Phase 7 Monetization and Hardening). |
| [`docs/02-task-breakdown.md`](docs/02-task-breakdown.md) | Concrete tickets per phase, mapped back to the master spec. |
| [`docs/04-data-model.md`](docs/04-data-model.md) | Detailed schema reference for every Supabase table. |
| [`docs/05-wardrobe-graph.md`](docs/05-wardrobe-graph.md) | Compatibility scoring, wardrobe score, and wardrobe graph concepts in depth. |
| [`docs/06-kyra-orchestration.md`](docs/06-kyra-orchestration.md) | Kyra's context packet, tool calls, and structured response schema. |
| [`docs/07-design-system.md`](docs/07-design-system.md) | Full design token reference — color, type, spacing, motion. |
| [`docs/08-provider-abstraction.md`](docs/08-provider-abstraction.md) | The five AI provider protocols and how the provider-neutral layer works. |
| [`docs/11-risk-register.md`](docs/11-risk-register.md) | Product, technical, legal, and business risks, with leading indicators and mitigations. |
| [`docs/adr/`](docs/adr/) | Architecture Decision Records — why the stack and structure are what they are, numbered 0001+. |
| [`CLAUDE.md`](CLAUDE.md) | Repository conventions for AI coding agents (Claude Code and others). |
| [`ios/README.md`](ios/README.md) | iOS project setup, XcodeGen workflow, StoreKit configuration, environment variables. |
| [`supabase/README.md`](supabase/README.md) | Supabase project setup, migrations, Edge Function deployment. |

## Tech stack

- **iOS:** Swift 6, SwiftUI, `@Observable` + structured concurrency, SwiftData
  (offline cache), AVFoundation + Vision (camera/scanning), StoreKit 2
  (subscriptions), WeatherKit, EventKit, AuthenticationServices.
- **Backend:** Supabase — Postgres, Auth, Storage, Realtime, Edge Functions
  (Deno/TypeScript), pgvector. Row Level Security on every user-owned table.
- **AI:** A provider-neutral server layer (`StylistReasoningProvider`,
  `VisionAnalysisProvider`, `ImageGenerationProvider`, `EmbeddingProvider`,
  `ProductExtractionProvider`) so the app is never hardcoded to one vendor. The
  iOS client talks only to Astra Edge Functions, never to a model vendor directly.
- **Project generation:** XcodeGen, from `ios/project.yml` — the `.xcodeproj` is
  generated output and is not committed.

See `docs/adr/` for the reasoning and named trade-offs behind each of these
choices.

## Where to start

**New human contributor:** read `docs/00-master-spec.md` in full first — it's long,
but it's the single source of truth and skipping it produces work that has to be
redone. Then read `CLAUDE.md` for repo conventions, `docs/01-build-roadmap.md` for
what phase the build is in, and `docs/02-task-breakdown.md` for a concrete ticket
to pick up.

**Coding agent (Claude Code or similar):** `CLAUDE.md` is written specifically for
you and is read at the start of every session — it defines the document hierarchy,
Swift and Supabase conventions, the design-token rule, Kyra conventions, testing
expectations, and what not to do. Follow it, then proceed to
`docs/01-build-roadmap.md` and `docs/02-task-breakdown.md` for current-phase work.

**Anyone evaluating an architectural change:** check `docs/adr/` first. If a
decision already exists and you disagree with it, the ADR names the conditions
under which it should be revisited — either those conditions are met, or the
existing decision stands.
