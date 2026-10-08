# `legal/` — user-facing legal documents

Four self-contained HTML documents, plus this file.

| File | Document | Wired to |
|---|---|---|
| `privacy.html` | Privacy Policy | `AstraLegal.privacyURL` → `/privacy` |
| `terms.html` | Terms of Service | `AstraLegal.termsURL` → `/terms` |
| `data-deletion.html` | Deleting your account and your data (§15) | `AstraLegal.dataDeletionURL` → `/privacy/delete` |
| `affiliate-disclosure.html` | Affiliate Disclosure (§17) | `AstraLegal.affiliateDisclosureURL` → `/affiliate-disclosure` |

All four carry a visible **Last updated: 31 July 2026**.

## Plan status: published on astra-style.com, still a draft for counsel

**Updated 2026-10-08.** The four documents are served at `https://astra-style.com`
(`/privacy/`, `/terms/`, `/privacy/delete/`, `/affiliate-disclosure/`).
`AstraLegal.isPublished` is **`true`** and in-app links match those URLs.

**Every `[[NEEDS INPUT]]` below still stands.** Do not invent entity names,
addresses, or governing law to clear them. Counsel review is still required
before these drafts can be treated as in-force legal text.

Implementation facts can and should be updated from verified code and deployed
behavior. Entity, address and governing-law choices require actual owner/counsel
inputs. The reconciliation below separates verified implementation progress from
the older inventory used when the draft was written.

Where things stand, so the deferral is a known state rather than a vague one:

- The four documents exist here and are unreviewed drafts.
- `AstraLegal.isPublished` is **`true`**: the app links to the reachable public drafts.
  This flag describes reachability, not counsel approval.
- Public legal pages are built from this directory into `web/dist/` and served by Cloudflare.
- `astrastyle.app` was never registered. The owner purchased **`astra-style.com`**
  (Cloudflare DNS) for the marketing site — see `web/GATE.md`. That does **not**
  by itself make the drafts counsel-approved.
- **Every `[[NEEDS INPUT]]` below still stands.** They are not resolved, not withdrawn, and not
  replaced by implementation work.

Counsel placeholders and stale descriptions of implemented features remain release work;
changing a reachability flag does not resolve them. Ticket: `P7-PRIVACY-05`. See `docs/03-progress.md`'s blocker
list for the same statement in the project-wide record.

---

## Read this before doing anything with them

**These are unreviewed drafts. They are not legal advice and no one should rely on them.**
They were written to be *accurate to the code* — every factual claim in them was derived from
the migrations in `supabase/migrations/`, the ADRs, `docs/00-master-spec.md`, and the iOS
sources — precisely so that a lawyer reviewing them is arguing about law rather than about
what the software does. That is the whole value of the exercise, and it is destroyed if they
are published as-is.

Two rules were followed throughout and should survive editing:

1. **No compliance claims.** Nothing says "GDPR compliant" or "CCPA compliant". The documents
   describe practices. Which statutes apply, and what they demand, is counsel's call.
2. **Nothing is promised that is not built.** Where the app does less than a normal policy
   would assert — deletion orchestration, retention sweeps, data export, in-app deletion UI,
   per-image deletion, the training opt-out toggle, the affiliate-bias audit — the documents
   say so in plain words. See "Where the app does less" below. A policy promising a control
   the app lacks is worse than one that omits it.

## ⚠️ Biometric privacy — needs specific legal review

`privacy.html` opens with a large HTML comment and a visible red-bordered notice on this, and
it is repeated here because it is the single most consequential item on the page.

The app collects **face images** (reference selfies for Style Studio) and **body
measurements**, and the Style Studio pipeline (spec §13 step 3) explicitly derives a
"face/body identity representation" from a photograph. That may bring it inside
biometric-privacy statutes — notably the **Illinois Biometric Information Privacy Act
(BIPA)**, which requires written notice and written consent *before* collection, a published
retention and destruction schedule, and which carries a **private right of action with
statutory damages per violation**. Texas (CUBI), Washington, and several newer state privacy
laws impose related duties; GDPR Art. 9 treats biometric data processed for unique
identification as special category data.

This draft does not attempt to resolve any of it. It flags it. See also
`docs/11-risk-register.md` risk 7.

---

## How these are published

They are standalone static HTML sources copied by `web/scripts/build.mjs` into
`web/dist/` and served on Cloudflare. The build adds the intentional draft banner.
`ios/AstraStyle/Core/Utilities/AstraLegal.swift` points to those HTTPS routes and
currently has `isPublished = true`, meaning the documents are reachable. The
source still needs factual updates and counsel review; do not remove the draft
banner to imply that approval. See `web/CLAUDE.md` and `web/GATE.md` for publishing.

## Verifying

```sh
python3 scripts/check_ui_conventions.py     # Swift-only; HTML is not scanned
python3 scripts/check_progress.py
python3 -c "import html.parser,glob,sys;
[html.parser.HTMLParser().feed(open(f).read()) for f in glob.glob('legal/*.html')]"
grep -inE 'https?://' legal/*.html          # must return nothing
```

---

## Every `[[NEEDS INPUT]]` in one place

Placeholders render with a yellow highlight so they cannot ship unnoticed. **Do not invent
values for the first group** — entity, address and jurisdiction are decisions, not drafting.

Per "Plan status" above, **none of these is being worked on now.** The list is a record of what
must be answered before publication, kept complete so that the end-of-project pass is a single
sitting rather than a rediscovery exercise.

### Blocking — the same values appear in several documents

| Item | Appears in |
|---|---|
| Full legal entity name | all four |
| Registered entity address | all four |
| Privacy contact email address | privacy, data-deletion |
| Deletion request email address | data-deletion |
| Support / legal contact email address | terms, affiliate-disclosure |
| Governing law | terms |
| Jurisdiction and venue | terms |
| DPO / Art. 27 representative details, or a positive statement that none is required | privacy |
| Lead supervisory authority, or a statement of which applies | privacy |

### `privacy.html`

- Specific biometric-privacy legal review — BIPA applicability, pre-collection written consent
  flow, published biometric retention/destruction schedule, whether Style Studio should be
  geofenced pending review.
- Confirm whether the single **guest-mode Style Studio sample** transmits a reference image to
  our Edge Functions and to OpenAI. Generation cannot happen on-device, so it almost certainly
  does — which would mean a face image leaving the device before any account exists, and the
  biometric-consent question arising at that point.
- Whether `lifestyle_profiles.religious_service_attire_needs` needs its own consent treatment,
  or should be restructured so religion is not captured at all.
- Legal bases per purpose (GDPR-style table) and the corresponding US state-law disclosures —
  deliberately not drafted.
- Which analytics provider, if any, is used at launch.
- Weather provider — none is selected in the codebase (`WEATHER_PROVIDER_KEY_IF_USED`).
- Affiliate networks / retailer feed providers, once commerce goes live.
- Crash and error reporting service, if one is added.
- Confirm the OpenAI organisation's data-controls settings and retention window, and whether a
  zero-data-retention arrangement and a DPA are in place.
- Confirm final retention windows, and confirm the retention sweep is live before publishing
  §10 as written.
- Response-time commitment for access/export/deletion requests, and whether identity
  verification is required.
- Breach notification commitment and process.
- Supabase project region, OpenAI processing regions, and the international transfer mechanism.
- Confirm 18 is the intended minimum age, that it matches the App Store age rating, and that it
  satisfies age-of-consent rules in every listed market.

### `terms.html`

- Confirm 18 as minimum age against the App Store rating in every market.
- Backup retention window, and whether backups are in scope for deletion requests.
- Final launch prices and plan names, free-trial terms, and any generation-credit product. The
  codebase carries indicative pricing (§16) that must **not** be restated as a commitment.
- Statutory cancellation / withdrawal rights language for the EU, UK and elsewhere.
- **Warranty disclaimer** — not drafted; counsel to write, with consumer-law carve-outs.
- **Limitation of liability** — not drafted; counsel to write, including any cap.
- Whether a user indemnity is appropriate for a consumer app, and its wording.
- Whether to include an arbitration agreement and class-action waiver, with opt-out and
  carve-outs.
- Whether the Apple Standard EULA is relied on or these are submitted as a custom EULA, plus
  the App Store-required clauses (third-party beneficiary, maintenance and support, product
  claims, legal compliance) in Apple's required form.

### `data-deletion.html`

- Identity verification method for a deletion request — particularly for Sign in with Apple
  users whose account email is a private relay address.
- The completion window committed to, and the interim status shown.
- Backup retention window and how deletions propagate into backups.
- Whether tax / chargeback / fraud-audit obligations require retaining an **anonymised billing
  record** after deletion. The schema currently deletes `subscriptions` outright with
  everything else; `20260728101300_account_deletion.sql` flags this for legal and finance and
  no anonymised-retention table exists.
- OpenAI's retention window for API requests under this account.
- Export format and turnaround time.

### `affiliate-disclosure.html`

- Whether any sponsored or paid placement will exist at launch. If none will, say so plainly.
- Audit cadence and owner for the affiliate-bias audit, once commerce ships.
- The affiliate networks and retailer programmes participated in, by name. Several — Amazon
  Associates among them — mandate specific disclosure wording that must be reproduced verbatim.
- Exactly what identifiers are appended to outbound affiliate links, and whether any are tied
  to the user's account.

---

## Implementation reconciliation — 2026-10-08

Several HTML descriptions still reflect the July implementation state. They must
be reconciled before release; the historical table below is not current truth.

| Capability | Current evidence / remaining work |
|---|---|
| Account deletion | Profile Edge Function and in-app flow exist. Disposable-account live requests completed after the Storage API repair; see `docs/studio-comparison-live-acceptance.md`. |
| Data export | Profile export is deployed, now returning 27 owned tables, including Studio allowances and private collections. Large populated exports and attachments still need completeness acceptance. |
| Generated-image deletion | Owned terminal Studio previews can remove their image and row. Deletion preserves consumed trial accounting. |
| Analytics | `analytics_events` exists in production after the append-only schema repair. Two-user export isolation was verified. |
| Studio / Kyra | Native screens and live providers are implemented; internal build 14 includes comparison and labeled image-file sharing. Device acceptance remains. |
| Retention sweeps | ADR 0010's scheduled image expiration remains unimplemented; saved-look retention must be implemented with collections. |
| Counsel inputs | Entity, contact details, governing law and other `[[NEEDS INPUT]]` decisions remain unresolved. No counsel approval is asserted. |

## Historical implementation inventory — 2026-07-31

Each of these is stated in the documents themselves rather than glossed. Check them against
reality again before publishing, because several are one ticket away from changing.

| Thing | Reality at 2026-07-31 | Ticket |
|---|---|---|
| Account deletion | SQL half is built and hardened (`account_deletions`, `request_account_deletion()`, `finalize_account_deletion()`, the `auth.users` cascade). **The Edge Function that orchestrates it — storage blob deletion, then `auth.admin.deleteUser` — does not exist.** No deletion can currently complete end to end. | `P7-PRIVACY-01` |
| In-app deletion UI | Does not exist. Documents say deletion is by email. | `P7-PRIVACY-02` |
| Data export | Does not exist. Documents say so. | `P7-PRIVACY-03` |
| Per-image deletion (reference / generated) | Does not exist. | `P7-PRIVACY-04` |
| Model-training opt-out toggle | Does not exist; no column, no UI. The privacy policy states the intended default and explicitly does *not* offer a control. | `P7-PRIVACY-06` |
| ATT / tracking | Not implemented, and no tracking exists to justify it. The policy says the prompt is absent for that reason. | `P7-PRIVACY-06` |
| Analytics | No `analytics_events` table, no SDK, `LiveAnalyticsClient.log()` is a debug-print stub. `AnalyticsEvent` excludes PII by construction — verified in `Core/Analytics/AnalyticsEvent.swift`. | `P7-PRIVACY-07` |
| Retention sweeps (abandoned reference images at 24h, Studio outputs at 30d) | ADR 0010 policy; **no scheduled job exists**. Nothing expires on its own today. | — |
| Style-memory inspect/delete UI | Not built. | — |
| Shopping / affiliate features | No affiliate network integrated, catalogue empty, `Features/Shopping/` has no Swift files. | — |
| Feature UI maturity (for counsel / reviewers) | **Built and shipping in-app:** Onboarding → Style DNA, Home, Closet (overview/metrics/filters/detail/manual form), guest Profile. **Groundwork only:** Scanner (`Services/` — no camera/review UI). **README-only (zero Swift):** Outfits, Studio, Kyra, Shopping, Discover, Subscription. The documents describe the service as designed; a reviewer should know how much of it is not yet shipping. | — |

## Source of every factual claim

`supabase/migrations/` (schema — the authority on what data exists), `docs/adr/0010` (image
retention), `docs/adr/0011` (guest mode is local-only),
`supabase/migrations/20260728101300_account_deletion.sql` (deletion cascade and its documented
orchestration), `docs/00-master-spec.md` §§6.2, 6.6–6.9, 6.17, 6.22, 7, 12, 13, 15, 16, 17, 18,
25, 29, `docs/08-provider-abstraction.md` §§1.5, 2.5, 3.5, 4, 5 (OpenAI is the only model
vendor; `gpt-image-1.5` for Style Studio, `gpt-image-2` for quiz imagery),
`docs/16-quiz-imagery-bakeoff.md`, `docs/11-risk-register.md` risks 7 and 8,
`ios/AstraStyle/Core/Analytics/`, and `docs/03-progress.md` for what is actually built.
