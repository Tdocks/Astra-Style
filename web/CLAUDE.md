# Claude — marketing site (`astra-style.com`)

**You are in the right repo.** The site is **not** under `ios/`.

| What | Path |
|---|---|
| Landing HTML/CSS (edit here) | `web/site/` |
| Built output (what Cloudflare serves) | `web/dist/` |
| Privacy / Terms / etc. **source drafts** | `legal/*.html` (repo root) |
| Build (copies site + legal → dist) | `cd web && npm run build` |
| Deploy | from **repo root**: `npx wrangler deploy` |
| Full brief | `web/GATE.md` |
| Worker name | `astra-style` |
| Live | https://astra-style.com |

## Privacy / draft banner

- Live `/privacy` is built from `legal/privacy.html` by `web/scripts/build.mjs`, which
  injects a **“Draft — not yet in force”** banner into `<body>`.
- That banner is **intentional** while `[[NEEDS INPUT]]` placeholders remain and
  `AstraLegal.isPublished` is `false` in the iOS app. Do **not** remove it or flip
  `isPublished` unless the owner explicitly says the drafts are counsel-cleared.
- To change privacy **content**, edit `legal/privacy.html`, then:

```bash
cd web && npm run build
cd .. && npx wrangler deploy
```

- To change only the banner chrome, edit `draftBanner` in `web/scripts/build.mjs`,
  then rebuild + deploy.

## Do not

- Search only under `ios/` for the website.
- Invent a second Next.js/Vercel app.
- Treat https://developers.cloudflare.com/agent-setup/prompt.md as a reason to
  abandon App Store / TestFlight work mid-stream — finish the owner’s current ask first.
