# `web/` — astra-style.com

Marketing site for **astra-style.com**, deployed with Cloudflare Workers static assets.

## Cloudflare Agent

Open **[`GATE.md`](GATE.md)**. Deploy from the **repo root**:

```bash
cd web && npm run build && cd ..
npx wrangler deploy
```

Root config: [`../wrangler.toml`](../wrangler.toml) → `assets.directory = ./web/dist`.

## Edit the site

1. Change files under `site/`.
2. Run `npm run build` (copies `site/` → `dist/`, brand assets, legal drafts).
3. Commit `dist/` so deploys with no build step still work.
4. `npx wrangler deploy` from repo root.
