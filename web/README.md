# `web/` — astra-style.com

Marketing site for **astra-style.com**, deployed with Cloudflare Workers static assets.

## Live URLs

| URL | Status |
|---|---|
| https://astra-style.7rff2b9rjf.workers.dev | **Live now** (Worker deploy) |
| https://astra-style.com | Needs Custom Domain attach in Cloudflare dashboard — see [`GATE.md`](GATE.md) §2.B |

## Cloudflare Agent

Open **[`GATE.md`](GATE.md)**. Deploy from the **repo root**:

```bash
cd web && npm run build && cd ..
npx wrangler deploy
```

Root config: [`../wrangler.toml`](../wrangler.toml) → `assets.directory = ./web/dist`.
After deploy, the owner still must **Add Custom Domain** `astra-style.com` on the Worker.

## Edit the site

1. Change files under `site/`.
2. Run `npm run build` (copies `site/` → `dist/`, brand assets, legal drafts).
3. Commit `dist/` so deploys with no build step still work.
4. `npx wrangler deploy` from repo root.
