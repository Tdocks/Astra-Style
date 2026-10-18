# Agent router

Which instructions you follow depends on who you are:

| You are… | Open this first |
|---|---|
| **Marketing site / astra-style.com / privacy page** | **[`web/CLAUDE.md`](web/CLAUDE.md)** then [`web/GATE.md`](web/GATE.md) — sources in `web/site/` + `legal/`, serve from `web/dist/` |
| **Cloudflare Agent** / deploy only | **[`web/GATE.md`](web/GATE.md)** — `npx wrangler deploy` from repo root |
| **Claude Code on the owner's Mac** (iOS / TestFlight) | **[`START_HERE.md`](START_HERE.md)** |
| **Cursor / any CLI-only agent cutting an iOS build or TestFlight upload** (no Xcode GUI) | **[`ios/CLI_BUILD_AND_TESTFLIGHT.md`](ios/CLI_BUILD_AND_TESTFLIGHT.md)** — exact `xcodebuild archive`/`-exportArchive` commands, the two footguns that will burn you (dead `INFOPLIST_KEY_*` settings, signing dropped by `xcodegen generate`), and a table of errors already hit on this project |
| Any agent writing iOS / Supabase code | [`CLAUDE.md`](CLAUDE.md) then [`docs/03-progress.md`](docs/03-progress.md) |

Do not mix the streams: the marketing site does not change the iOS app; TestFlight
does not require the website to be live first.

## Git hosts

GitHub (`origin`, `Tdocks/Astra-Style`) is the push. Cursor Origin
(`tyler-dockswell/Astra-Style`) is an inbound mirror of GitHub — after a
requested commit, push `origin` and confirm Origin’s `main` matches. See
[`.cursor/rules/git-hosts.mdc`](.cursor/rules/git-hosts.mdc).

## Cloudflare MCP + skills (Cursor / Copilot / etc.)

Official setup: https://developers.cloudflare.com/agent-setup/prompt.md

This repo already includes:

- **Skills:** `.agents/skills/` (wrangler, workers-best-practices, …)
- **MCP config:** `.cursor/mcp.json` → `cloudflare`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability`

After pull: **restart the agent / Cursor** so MCP servers load, then complete Cloudflare OAuth on first tool use. `cloudflare-docs` needs no auth.

## Local Mac storage policy

- Reuse the existing **iPhone 18 Pro / iOS 27.0** simulator. Never create a
  simulator or install a runtime for local tests. Compile-only checks may use
  `generic/platform=iOS Simulator`. Keep the app minimum iOS version unchanged;
  older-OS coverage remains in hosted CI.
- Local container work uses the existing **colima-astra-local-qa** Docker context
  and **astra-local-qa** Colima profile. Never start Docker Desktop, create a
  profile, or silently change engines/context. Explain any engine exception first.
- Reuse **ios/build/DerivedData** for this project's local device and simulator
  builds. Do not allocate per-run DerivedData directories.
- Before deleting any simulator, runtime, Docker image, volume, VM or release
  artifact, identify its owner and contents and ask the owner. Never run broad
  Docker prune commands or delete Docker Desktop files as cache cleanup.
- Proposed retention rule (requires owner approval before deletion): keep release
  archives and final acceptance evidence; keep the latest successful and latest
  failed disposable test bundles per suite, with a seven-day window for other
  disposable outputs. Inventory size/ownership before proposing cleanup. No
  automated deletion is authorized by this proposal.
