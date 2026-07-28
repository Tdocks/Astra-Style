# 0010. Image storage: private buckets, signed URLs, and retention policy

## Status

Accepted

## Context

Astra Style handles three sensitive categories of image: raw garment scan photos
and their background-removed derivatives (§12, `closet_item_images`), reference
selfies/body images used for Style Studio (§6.7, §13), and generated Style Studio
output images (`studio_generations`). §15 requires storage paths of the form
`users/{user_id}/closet/...`, `users/{user_id}/references/...`,
`users/{user_id}/studio/...`, private buckets, and signed URLs — never public
object URLs. §13 requires storing Studio output "with expiration or permanent-save
choice" and deleting abandoned source images after a configurable retention period.
§29 requires in-app deletion of individual reference and generated images, and
requires that full account deletion remove all storage objects, not just database
rows. §29 also requires a model-training opt-out with training-off as the default.

## Decision

1. **All buckets are private.** No object is ever served from a public URL; every
   client read goes through a short-lived Supabase Storage signed URL minted by an
   Edge Function (or client SDK call scoped by RLS-equivalent Storage policy) after
   confirming the requesting user owns the `user_id` prefix.
2. **Path convention is enforced exactly as §15 specifies**:
   `users/{user_id}/closet/{closet_item_id}/{image_type}.{ext}`,
   `users/{user_id}/references/{reference_id}.{ext}`,
   `users/{user_id}/studio/{generation_id}/{result|source}.{ext}`. The `user_id`
   prefix is the sole authorization boundary Storage policies check, mirroring the
   `user_id = auth.uid()` RLS pattern used for tables (ADR 0002).
3. **Retention policy:**
   - Closet item images (source + background-removed) are retained indefinitely
     while the closet item is not archived, since they are core product data the
     user actively owns and views.
   - Reference selfie/body images used as Style Studio input are retained only as
     long as the user keeps them saved as a reference; an *abandoned* upload (a
     reference image uploaded but never used to complete a generation, or a
     generation session left incomplete) is deleted automatically after a
     configurable retention window, per §13's explicit instruction — default 24
     hours, configurable server-side.
   - Studio *generated* output images default to a configurable retention window
     (default 30 days) unless the user explicitly chooses "save to lookbook," which
     is a permanent-save action per §13 that moves/flags the object out of the
     expiring-retention path.
   - Retention windows are enforced by a scheduled Edge Function / Postgres job that
     deletes both the storage object and its row, not a soft-delete-only flag.
4. **Deletion guarantees per §29:** deleting an individual reference or generated
   image removes the Storage object synchronously (or via a visible, tracked
   deletion job if not synchronous) and removes its row; account deletion cascades
   through every bucket prefix under `users/{user_id}/`, every corresponding table
   row, and every embedding derived from that user's images (§15's deletion list:
   database rows, storage objects, generated images, embeddings, style memories,
   auth identity).
5. **Model-training opt-out:** the default state, for every user, is that provider
   requests are made with training/data-retention opted out wherever the provider's
   API supports that flag; explicit opt-in is required before any user image is
   used for provider-side model improvement, per §29.

## Consequences

### Positive

- Private-bucket-plus-signed-URL is the only pattern consistent with §29's
  deletion and access-control requirements — a public URL, once cached by a CDN or
  scraped, cannot be reliably "deleted" the way a private object with revocable
  signed access can.
- The `users/{user_id}/...` path convention makes the deletion cascade for account
  deletion a single prefix-delete operation per bucket rather than a per-row lookup
  join across tables to find every object a user owns — this is both simpler to
  implement correctly and easier to verify exhaustively (§15 requires deletion
  completeness, and an auditable "delete everything under this prefix" is easier to
  prove correct than "delete everything this query found").
- Automatic deletion of abandoned reference images and expiring Studio outputs
  directly reduces the standing inventory of sensitive personal imagery (selfies)
  at rest — a smaller retained corpus is a smaller breach blast radius and a smaller
  ongoing storage cost.
- Training opt-out defaulting to off is the safer default under §29 and under most
  plausible privacy regulation, and avoids a class of reputational risk (a user
  discovering their selfie was used to train a third-party model without consent).

### Negative (real costs, named)

- **Signed URLs expire, which is a real UX and engineering cost, not just a security
  win.** Every screen that displays a closet item image, an outfit hero image, or a
  Studio result must handle URL refresh — a cached signed URL from an hour ago may
  be expired when the user returns to a screen, requiring either short-lived caching
  logic keyed to expiry time, or a re-fetch-on-view pattern. Getting this wrong
  produces broken/blank images that look like a bug, not a security feature working
  as intended.
- **Automatic deletion of abandoned reference images can surprise users** if the
  retention window is too aggressive or the "abandoned" heuristic is wrong — a user
  who uploads a reference selfie, gets distracted, and returns two days later to
  finish a Style Studio session may find their reference image gone and have to
  re-upload, which reads as data loss even though it is retention policy working as
  designed. This tradeoff (privacy-minimizing retention vs. user convenience) is a
  real, ongoing tuning problem, not a "set it once" decision.
- **The scheduled deletion job is a new piece of infrastructure that can fail
  silently.** If the retention-sweep job stops running (a cron misconfiguration, an
  Edge Function deployment regression), abandoned selfies and expired generations
  simply accumulate indefinitely with no user-facing symptom — this needs its own
  monitoring/alerting, which is easy to omit at MVP and only notice during a
  security review or a storage-cost spike.
- Verifying "account deletion actually removed everything" (§15, §29) requires an
  actual audit process (periodic checks that no orphaned objects remain under a
  deleted user's former prefix) — the prefix-delete pattern makes this *easier* than
  the alternative, but does not make it free; a partial failure mid-deletion (e.g.
  Storage delete succeeds but a downstream embedding delete fails) needs the
  "user-visible status" job pattern §15 calls for, which is meaningfully more
  engineering than a single DELETE statement.
- Training opt-out defaulting to off must be verified per-provider, since providers
  differ in how (or whether) they expose a reliable "do not train on this data" API
  flag — the app's default-off promise is only as strong as each provider's actual
  contractual/technical enforcement, which is outside Astra's direct control and
  must be a contractual term with each AI vendor, not just an API parameter Astra
  hopes is honored (see the provider-data-retention item in
  `docs/11-risk-register.md`).

## Alternatives Considered

- **Public buckets with obscure/unguessable URLs ("security by obscurity").**
  Rejected outright: unguessable is not the same as inaccessible once a URL leaks
  (screenshots, shared links, referrer headers, crawler indexing), and this pattern
  cannot satisfy §29's deletion guarantees since a cached/scraped public URL persists
  independent of the source object's lifecycle.
- **Never auto-delete anything; rely solely on explicit user deletion.** Rejected:
  contradicts §13's explicit "delete abandoned source images after configurable
  retention" requirement, and leaves an unnecessarily large standing corpus of
  sensitive selfie imagery that increases both storage cost and breach exposure for
  images the user never intended to keep.
- **Store all image variants (raw, background-removed, thumbnail) forever with no
  differentiated retention by category.** Rejected: treats low-sensitivity, actively
  useful closet photos the same as high-sensitivity, often-abandoned reference
  selfies, which is both a worse privacy posture and a worse cost posture than the
  category-specific policy adopted above.
