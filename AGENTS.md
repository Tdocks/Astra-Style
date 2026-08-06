# Agent router

Which instructions you follow depends on who you are:

| You are… | Open this first |
|---|---|
| **Cold start / “where are we?”** | **[`CLAUDE_HANDOFF.md`](CLAUDE_HANDOFF.md)** — situation brief: what shipped, what works, TestFlight status, next job |
| **Marketing site / astra-style.com / privacy page** | **[`web/CLAUDE.md`](web/CLAUDE.md)** then [`web/GATE.md`](web/GATE.md) — sources in `web/site/` + `legal/`, serve from `web/dist/` |
| **Cloudflare Agent** / deploy only | **[`web/GATE.md`](web/GATE.md)** — `npx wrangler deploy` from repo root |
| **Claude Code on the owner's Mac** (phone smoke / TestFlight) | **[`START_HERE.md`](START_HERE.md)** (brief: [`CLAUDE_HANDOFF.md`](CLAUDE_HANDOFF.md)) |
| **Cursor / any CLI-only agent cutting an iOS build or TestFlight upload** (no Xcode GUI) | **[`ios/CLI_BUILD_AND_TESTFLIGHT.md`](ios/CLI_BUILD_AND_TESTFLIGHT.md)** — exact `xcodebuild archive`/`-exportArchive` commands, the two footguns that will burn you (dead `INFOPLIST_KEY_*` settings, signing dropped by `xcodegen generate`), and a table of errors already hit on this project |
| Any agent writing iOS / Supabase code | [`CLAUDE.md`](CLAUDE.md) then [`docs/03-progress.md`](docs/03-progress.md) |

Do not mix the streams: the marketing site does not change the iOS app; TestFlight
does not require the website to be live first.

## Cloudflare MCP + skills (Cursor / Copilot / etc.)

Official setup: https://developers.cloudflare.com/agent-setup/prompt.md

This repo already includes:

- **Skills:** `.agents/skills/` (wrangler, workers-best-practices, …)
- **MCP config:** `.cursor/mcp.json` → `cloudflare`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability`

After pull: **restart the agent / Cursor** so MCP servers load, then complete Cloudflare OAuth on first tool use. `cloudflare-docs` needs no auth.
