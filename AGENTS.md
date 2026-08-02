# Agent router

Which instructions you follow depends on who you are:

| You are… | Open this first |
|---|---|
| **Cloudflare Agent** / web / domain deploy | **[`web/GATE.md`](web/GATE.md)** — site is in `web/dist`; from repo root run `npx wrangler deploy` |
| **Claude Code on the owner's Mac** (iOS / TestFlight) | **[`START_HERE.md`](START_HERE.md)** |
| Any agent writing iOS / Supabase code | [`CLAUDE.md`](CLAUDE.md) then [`docs/03-progress.md`](docs/03-progress.md) |

Do not mix the streams: the marketing site does not change the iOS app; TestFlight
does not require the website to be live first.
