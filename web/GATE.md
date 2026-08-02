# GATE — Marketing site for astra-style.com (Cloudflare Agent)

**Audience:** Cloudflare’s coding / deploy agent (and any human running Pages).
**Domain (purchased):** `astra-style.com` (and `www.astra-style.com`).
**Host:** Cloudflare Workers static assets (or Pages) — domain on Cloudflare.
**This file is the job brief.** The site already lives under `web/dist/` and
deploys with `npx wrangler deploy` from the **repo root** (see root
`wrangler.toml`). Attach **astra-style.com**. Do not touch the iOS app,
Supabase Edge Functions, or flip `AstraLegal.isPublished` unless asked.

If you are an **iOS / Claude Code** agent looking for TestFlight: stop — open
[`../START_HERE.md`](../START_HERE.md) instead.

---

## 0. Mission (done when)

1. A production marketing site is live at **https://astra-style.com**.
2. `www` redirects (or CNAMEs) to apex.
3. Legal draft pages are reachable at pretty paths (see §4) — still clearly
   **draft / unpublished** until counsel clears them; do not claim they are final.
4. Deploy is repeatable via `wrangler pages deploy` (or Pages Git integration)
   from this `web/` directory.
5. Owner can open the URL on a phone and see brand, one clear CTA toward the
   App Store / TestFlight placeholder, and working nav.

---

## 1. Stack (already scaffolded — do not replace)

| Choice | Value |
|---|---|
| Site source | `web/site/` (HTML + CSS) |
| Build output | `web/dist/` (**committed**; rebuild with `cd web && npm run build`) |
| Hosting | Cloudflare Workers **static assets** via root `wrangler.toml` |
| Deploy command | `npx wrangler deploy` from **repository root** |
| Package | `web/package.json` — build copies brand + legal drafts into `dist/` |

Do **not** add Next.js / Vercel. Do **not** put Supabase service-role or OpenAI
keys here. No user auth on the marketing site for v1.

```
wrangler.toml             ← root config assets.directory = ./web/dist
web/
  GATE.md
  site/                   ← edit HTML/CSS here
  scripts/build.mjs
  dist/                   ← what Wrangler uploads (committed)
  wrangler.toml           ← same site if Root directory = web
```

### Cloudflare dashboard / Agent settings that must match

The failing log ran `npx wrangler deploy` with **no static files**. Fix:

| Setting | Required value |
|---|---|
| Deploy command | `npx wrangler deploy` |
| Root / working directory | **repository root** (not empty; needs root `wrangler.toml`) |
| Optional build command | `cd web && npm run build` (before deploy) |
| Do **not** use | `wrangler pages deploy` unless you switch to a Pages project with `pages_build_output_dir` |

If the Agent UI forces a subdirectory of `web`, set Root directory to `web` and
deploy command to `npx wrangler deploy --config ./wrangler.toml` after
`npm run build`.

---

## 2. Deploy + attach domain

### A. Deploy (CLI / Agent)

From repo root (after merge to `main`):

```bash
cd web && npm run build && cd ..
npx wrangler deploy
```

Owner / Agent must be authenticated (`wrangler login` or `CLOUDFLARE_API_TOKEN` +
`CLOUDFLARE_ACCOUNT_ID`).

### B. Custom domain (required — deploy alone does **not** bind astra-style.com)

`npx wrangler deploy` only publishes the Worker to a `*.workers.dev` URL, e.g.:

**https://astra-style.7rff2b9rjf.workers.dev** ← open this now; the site is live there.

`astra-style.com` will not resolve until you attach it. As of 2026-08-02 the zone
uses Cloudflare nameservers (`april` / `tate`) but has **no apex A/AAAA/CNAME**,
so the browser/search bar correctly fails for `https://astra-style.com`.

**In the Cloudflare dashboard (owner click-path):**

1. Left nav → **Workers & Pages** → open worker **`astra-style`**.
2. **Settings** → **Domains & Routes** (or **Triggers** → **Custom Domains**).
3. **Add** → **Custom domain** → enter `astra-style.com` → Add domain.
4. Repeat for `www.astra-style.com`.
5. Cloudflare will create the DNS records automatically in the `astra-style.com`
   zone. Wait until status is **Active** (often 1–5 minutes; sometimes longer).
6. **SSL/TLS** for the zone → mode **Full (strict)**. Turn on **Always Use HTTPS**.

**Do not** invent manual `A` records to random IPs. Use **Custom Domains** on the
Worker so Cloudflare wires the proxy correctly.

Verify:

```bash
curl -sI https://astra-style.7rff2b9rjf.workers.dev | head -5   # expect 200
curl -sI https://astra-style.com | head -5                      # 200 after attach
dig +short astra-style.com                                      # should return CF proxied IPs
```

Google / Safari search will **not** list the site until the custom domain works
and search engines crawl it (days). Bookmark the `workers.dev` URL or the domain
after step 5 — do not expect instant SEO.

### C. Git integration

Production branch: `main`. Build command optional (`cd web && npm run build`).
Deploy command: `npx wrangler deploy`.

---

## 3. Brand & visual direction (non-negotiable)

Source of truth for product: `docs/00-master-spec.md` §3 and
`docs/07-design-system.md`. Token reference also in
`design/astra-design-system.html`.

### Colors (dark-first marketing; support light if easy)

| Token | Hex (dark) | Use |
|---|---|---|
| backgroundPrimary | `#0D0D0D` | Page ground |
| backgroundSecondary | `#151515` | Sections |
| surfaceElevated | `#1B1B1B` | Interactive surfaces only |
| textPrimary | `#F7F3EA` | Headlines / body |
| textSecondary | `#B9B3A8` | Supporting |
| textMuted | `#88847C` | Meta |
| accentChampagne | `#D7B46A` | CTAs, rules, emphasis |
| divider | `#2A2927` | Hairlines sparingly |

Light pair exists in the design system if you add a theme toggle; default the
marketing site to the **dark marble** look.

### Type

- Display / titles: **serif** (New York / `"Iowan Old Style"`, Georgia stack) —
  not Inter/Roboto/Arial as the hero voice.
- Body / UI: system sans (SF Pro / system-ui).
- Wordmark: `brand/assets/logo-wordmark-dark.jpg` (on dark) /
  `logo-wordmark-light.jpg` (on light). Prefer SVG later if you trace it; JPG is fine for v1.

### Atmosphere

- Marble / stone texture language — see `brand/assets/app-icon-marble.jpg`,
  `splash-reference.jpg`, and the `.marble` CSS in `design/astra-design-system.html`.
- Full-bleed hero plane. **No** inset hero cards, floating badge stickers, or
  stat strips in the first viewport.

### Hard “don’t” list (owner frontend rules)

- No purple-on-white / purple-indigo AI gradients.
- No warm cream + terracotta “default AI brochure” look.
- No broadsheet dense newspaper columns.
- No emoji as decoration.
- No card grids in the hero.
- First viewport = **brand + one headline + one short sentence + one CTA group +
  one dominant image**. Nothing else.

### Motion

Ship 2–3 intentional motions (e.g. slow marble drift / fade-up of headline /
CTA underline). No particle spam, no glow stacks.

---

## 4. Pages to ship (v1)

| Path | Purpose |
|---|---|
| `/` | Marketing landing (see §5) |
| `/privacy` | Serve `legal/privacy.html` (restyle to site chrome or iframe/embed cleaned HTML) |
| `/terms` | Serve `legal/terms.html` |
| `/privacy/delete` | Serve `legal/data-deletion.html` |
| `/affiliate-disclosure` | Serve `legal/affiliate-disclosure.html` |
| `/robots.txt` | Allow `/`; sitemap optional |

Legal HTML files live at repo root `legal/*.html`. They contain `[[NEEDS INPUT]]`
placeholders and are **drafts**. On each legal page, show a discreet banner:
“Draft — not yet in force” until the owner flips publication. Do **not** edit
iOS `AstraLegal.isPublished` from this workstream.

App Store / TestFlight CTA on `/`:

- If no public App Store URL yet: button label **“Get the iOS app”** linking to
  a `#` with `aria-disabled` **or** better: `https://testflight.apple.com/`
  only if the owner provides a public link — otherwise use a mailto /
  “Join the waitlist” form stub that posts nowhere yet, or a simple
  `mailto:admin@astra-style.com` if that mailbox exists. Prefer asking the
  owner once for the real TestFlight public link and hardcoding it.

---

## 5. Landing composition (`/`)

One composition, not a dashboard.

1. **Hero (first viewport)**
   - Full-bleed marble / product atmosphere (`brand/assets/splash-reference.jpg`
     or `ui-reference-daily-brief.jpg` as the dominant plane).
   - Wordmark as hero-level brand (not a tiny nav-only mark).
   - Headline (serif): something in the voice of
     *“Your style. Your journey. Your best self.”* — do not invent a louder
     competing slogan that overpowers the brand.
   - One supporting sentence: personal stylist for men; Kyra; wardrobe that
     compounds.
   - CTA group: primary champagne button (Get the iOS app / Join TestFlight) +
     optional text link to `#how-it-works`.
   - **No** overlays, chips, or promo stickers on the hero image.

2. **How it works** (one job) — Closet → Kyra’s daily pick → Wardrobe Graph.
   Short. Real imagery from `brand/` / `design/shot-*.png` if useful.

3. **Why it isn’t another shopping app** (one job) — unlock count / coherent
   wardrobe over time. No fake metrics.

4. **Footer** — wordmark, Privacy, Terms, Affiliate disclosure, © year,
   “Astra Style”.

Keep sections to one headline + one short supporting sentence each.

---

## 6. SEO / social basics

- `<title>`: `Astra Style`
- Meta description: one sentence from the product README.
- Open Graph image: use `brand/assets/app-icon-marble.jpg` or a 1200×630 crop
  you generate into `web/public/og.jpg`.
- Favicon: from app icon marble.
- Canonical: `https://astra-style.com/`

---

## 7. What you must not do

- Do not deploy secrets from `ios/Config/Secrets.xcconfig`.
- Do not call Supabase Edge Functions from the marketing site in v1.
- Do not publish legal docs as “effective” while `[[NEEDS INPUT]]` remains.
- Do not rewrite `docs/00-master-spec.md` or change iOS tokens to match the web —
  web copies the tokens, not the other way around.
- Do not add a dependency ADR for the iOS app; this `web/` package is separate.
  Keep JS deps minimal (Astro or Vite only if possible).

---

## 8. Verification checklist (report back)

- [ ] `npm run build` succeeds locally
- [ ] `wrangler pages deploy` (or Git Pages build) succeeded
- [ ] https://astra-style.com loads over HTTPS
- [ ] www → apex (or both serve the same site)
- [ ] `/privacy`, `/terms`, `/privacy/delete`, `/affiliate-disclosure` return 200
- [ ] Mobile viewport: hero is one composition; CTA tappable
- [ ] Lighthouse performance not catastrophic on mobile (no multi‑MB uncompressed heroes — compress images)

---

## 9. Owner facts

| Item | Value |
|---|---|
| Product | Astra Style — iOS personal stylist for men (Kyra) |
| Domain | `astra-style.com` |
| DNS / CDN | Cloudflare |
| iOS bundle id | `com.astrastyle.app` |
| Backend | Supabase (out of scope for this site) |
| Brand assets | `brand/assets/` |
| Design reference | `design/astra-design-system.html` |
| Legal drafts | `legal/*.html` |

When finished, paste the live URL and the Pages project name into your reply to
the owner. If DNS is not yet on Cloudflare, stop after the `*.pages.dev`
deploy and tell the owner the exact Custom Domains clicks remaining.
