# 10. Style Studio Integration — SUPERSEDED IN PART

> ## ⚠️ VENDOR SUPERSEDED — read this before anything below
>
> **The vendor named in this document is wrong and the capability it assumes does not exist.**
> `docs/15-image-provider-evaluation.md` measured it: `soul_2` **silently rewrites the prompt**
> whenever a reference image is attached, discarding the garment list entirely and frequently the
> identity along with it. All 18 test generations returned a head-and-shoulders portrait in a grey
> t-shirt instead of the requested outfit. It is not configurable —
> `enhance_prompt` is rejected as unsupported on that model.
>
> **Style Studio now uses OpenAI `gpt-image-1.5`.** Decision recorded in `docs/15` §5.
>
> ### What in this document is DEAD
>
> - **§0** — the "two paths" premise. The one-off reference path does not work at all.
> - **§3.1–3.3** — Higgsfield client setup, error mapping, `submitGeneration`/`pollStatus`.
> - **§3.4 Soul ID training** — rejected outright, and not only on quality. Souls are
>   account-scoped rather than user-scoped, so thousands of end users' models would share one
>   seat with no isolation; and a trained Soul **is a persistent derived biometric model** of the
>   user held indefinitely by a third party, making it the *worst* option for §29 and for
>   right-to-erasure. See `docs/15` §2.
> - **§4** — all `soul_2` prompt construction and the worked examples.
>
> ### What in this document SURVIVES, because it was never vendor-specific
>
> - **§1** the tiered product design and Kyra's framing of the upgrade.
> - **§2** the architecture: call site, job lifecycle, the queue, the polling contract,
>   results-land-in-Storage-never-hotlinked, disclaimer attachment.
> - **§5** the body-proportion gap — and `docs/15` adds to it: text-to-image models regress
>   hard toward an average male build, so a generated *figure* will not carry a user's frame.
>
> ### Two prompt rules that MUST carry into the replacement
>
> Both were measured, and both fix a real observed failure:
>
> 1. **Colour saturation guard.** `gpt-image-1.5` desaturates toward black — navy renders as
>    black, forest green as near-black. Naming the trap explicitly fixes it, at no cost to
>    identity (`docs/15` §3).
> 2. **Cut must be weighted, not buried.** With "wide-leg" as one adjective among four garments,
>    2 of 18 images honoured it. With cut as the sentence's subject, every image honoured it.
>    This one is load-bearing for `docs/14` — `FitRules` reasons entirely on the cut axis, and if
>    Studio cannot render slim versus wide then Kyra's advice sits beside a picture that
>    contradicts it.
>
> Nothing below this box has been edited. It is kept for the architecture and product design,
> which remain correct, and as the record of a decision that measurement overturned.

---

# 10 (original). Style Studio Integration — Higgsfield Soul 2.0

**Depends on:** `00-master-spec.md` §5.6, §6.7, §6.17, §9, §11, §13, §14, §15, §16, §20, §21, §29;
`08-provider-abstraction.md` §3 (`ImageGenerationProvider`), §8 (Style Studio pipeline mapping);
`04-data-model.md`; `adr/0010-image-storage-and-retention.md`.

**Status:** SUPERSEDED IN PART — see the box above. Originally: vendor decided, resolving `08-provider-abstraction.md` §3.5's
`DECISION PENDING` block: **Higgsfield, model `soul_2` ("Soul 2.0")**. It does not replace
`08`'s protocol definition — `ImageGenerationProvider` stays the interface every Edge Function
codes against — it's the concrete implementation and the product design built on top of it.
Everything in `08` §8 (pipeline-to-provider mapping, prompt template, consent gate) still holds;
this document makes it real for one specific vendor and adds what `08` explicitly deferred:
the tiered product design, worked prompts, the body-proportion gap, and real cost arithmetic.

---

## 0. The central decision: two paths, not one

Soul 2.0 supports generation two ways, and — this is the load-bearing fact the rest of this
document is built on — **they are not mutually exclusive**. `soul_2` accepts up to one reference
image (`medias`, role `image`) *and* an optional `soul_id` in the same request. A trained Soul ID
does not replace the reference image; it augments it. That single fact is what makes a tiered
design possible without forcing a hard tradeoff between "fast and free" and "high fidelity."

| | **Quick Preview** | **Studio Portrait** |
|---|---|---|
| Model call | `soul_2`, no `soul_id` | `soul_2`, `soul_id` set **and** a fresh reference image still attached |
| Setup cost to the user | None — any one photo | One training session: 20+ photos (up to 80), 3–5 min, one-time |
| Who gets it | Free (1 lifetime trial), Premium (part of monthly quota) | Premium only, opt-in |
| What it's good at | Single-shot outfit visualization from whatever photo the user has right now | Identity consistency across many scenes, poses, lighting, and sessions — the thing a single reference image structurally cannot do |
| What it does NOT solve | Cross-session consistency; if the reference photo is a bad angle, everything downstream inherits that | Body proportions beyond the face (§4 below) — training does not fix this, a concurrent reference photo does |
| Cost per generation (verified, §7.6) | $0.05 planning rate (≈$0.006 at the metered rate) — identical on both paths and at both quality tiers | Same $0.05 planning rate, plus a one-time $1.25 training cost |

This is the resolution to the spec's stated tension: §6.7 lists reference selfies as optional,
frictionless onboarding; Soul ID needs a real 20-photo commitment. **Quick Preview never requires
that commitment.** Nobody is asked for 20 photos before their first Style Studio result. Studio
Portrait is offered only after a user has already seen value from Quick Preview and is Premium —
at that point, "teach me your face properly" is an upsell into a feature they've already
experienced a cheaper version of, not a wall in front of the first one.

---

## 1. Tiered design in detail

### 1.1 When each path is offered

```
First Style Studio visit (any tier, including guest, §6.2):
  → Quick Preview only. No mention of Studio Portrait yet — don't sell a feature
    before the user has any basis to want it.

After a Quick Preview generation completes (Free or Premium):
  → Standard result screen (§6.17: viewport, before/after compare, disclaimer).
    Free users who have used their one lifetime trial see an upgrade card instead
    of a "generate again" button.

Premium user, on their 2nd+ Quick Preview generation, OR on first visit to a
saved/favorited outfit, OR when they tap "make this look like me every time":
  → Studio Portrait is offered as an explicit opt-in card, not auto-triggered and
    not a modal that blocks the Quick Preview flow. Declining leaves Quick Preview
    fully available, indefinitely, with no further nagging cadence faster than
    once per week of active Studio use.

Guest mode (§6.2):
  → One Style Studio sample, Quick Preview only, no Studio Portrait (requires an
    account — Soul ID training is tied to `user_id`, and a guest's local-only
    closet already caps functionality). The guest's one sample and a subsequently
    created Free account's "one trial" (§16) are the SAME lifetime allotment, not
    additive — the allotment is keyed to device+identity signals at signup to
    prevent guest-mode farming of free generations (see §7.3 below).
```

### 1.2 How the upgrade is framed — Kyra's voice

Per §2's voice rules (warm, opinionated, direct, no shallow praise, no jargon overuse), the
upgrade card is written as Kyra making a specific, honest claim about what improves — not generic
upsell copy ("Unlock more features!").

**Upgrade card, shown after a Quick Preview generation (Premium user):**

> **Kyra:** "This one's a good likeness, but it's working from a single photo — the angle, the
> light, whatever you had on hand. If you want every future look to hold your face together the
> same way, teach me properly: about fifteen or twenty clear photos, different angles, no
> sunglasses. Takes five minutes to train, and I keep it — you won't do this again."
>
> [Train my Studio Portrait] [Not now]

**Free-tier trial-exhausted card:**

> **Kyra:** "That was your free preview. If Style Studio's useful to you, Premium gives you a real
> monthly allowance — and the option to train a proper portrait of yourself so every look after
> that one holds up, not just the first."
>
> [See Premium] [Not now]

**Studio Portrait capture screen intro copy:**

> "I need to actually learn your face, not just borrow one photo. Give me a real range — straight
> on, both profiles, a couple of candid ones, different light if you have it. Skip anything with
> sunglasses or a big grin — I need your resting features, not a snapshot. Twenty is enough; more
> helps, up to eighty."

**After training completes:**

> "Done. That's yours now — I'll use it for every Style Studio look from here, and it doesn't
> expire or need retraining unless you want to redo it."

Notably absent from all of this: any claim about body accuracy improving. Kyra never says "this
will show you your real body" — because that's not what Soul ID does, and the copy is honest
about scope (see §4).

### 1.3 What the quality difference actually is

Be precise here, because overclaiming is exactly the failure §11 and §6.17 guard against:

- **What improves with Studio Portrait:** facial structure consistency, hairstyle/facial-hair
  consistency, and expression-style consistency *across generations, poses, and lighting
  conditions* — i.e., the thing that's structurally impossible from a single static reference
  image once the model is asked to render a new pose or a different scene. A single-reference
  generation of "you, walking down a lit street at dusk" has to extrapolate your face at an angle
  the reference photo never showed; Soul ID was trained specifically to make that extrapolation
  hold up.
- **What does NOT reliably improve:** body proportions, build, and skin tone beyond the face.
  Soul ID's documented preservation scope is "facial structure, hair, expression style, and
  identity features" — full stop. There is no documented claim about torso length, shoulder
  width, or skin tone matching. Studio Portrait is not sold as a body-accuracy upgrade, and the
  product design in §4 treats that gap the same way regardless of which path generated the image.
- **What's the same either way:** garment rendering fidelity, editorial quality, and — confirmed by
  a live pricing preflight against the real Higgsfield API (§7.6) — **cost per call, regardless of
  quality tier.** `1.5k` and `2k` bill identically, so every generation on both paths now defaults
  to `2k` (§3.3, §7.4); there is no cheaper tier being traded away.

---

## 2. Architecture

### 2.1 Where Higgsfield is called from

Per §8/§25 and `08-provider-abstraction.md` §5 (owner surface), the iOS client **never** holds a
Higgsfield API key and never calls `api.higgsfield.ai` directly. Every call — generation submit,
status poll, Soul ID training, Soul ID status — is proxied through a Supabase Edge Function.
`HIGGSFIELD_API_KEY` lives only in Edge Function secrets.

```
iOS client
   │  POST /studio/generate, GET /studio/status/:id,
   │  POST /studio/identity/train, GET /studio/identity/status/:id
   ▼
Supabase Edge Function (Deno)
   │  - validates JWT, ownership, consent (§6 below)
   │  - reads/writes studio_generations / studio_identity_profiles rows
   │  - the ONLY thing that holds HIGGSFIELD_API_KEY
   ▼
Higgsfield API (soul_2 generation, soul training)
```

### 2.2 Job lifecycle

Matches §6.17's four states exactly, with one added state for Studio Portrait training that the
UI surfaces separately (training is not a "generation," it doesn't consume generation quota, and
it has a materially longer duration budget):

```
Generation:  Queued → Generating → Complete
                              └──→ Failed (retry, §21 — see §8 of this doc)

Training:    Queued → Training → Ready
                              └──→ Failed (retry — different failure taxonomy, §8.4)
```

`studio_generations.status` and `studio_identity_profiles.status` are the source of truth; the
client never polls Higgsfield directly (see §2.4).

### 2.3 The queue

`studio_generations` (and the new `studio_identity_profiles`, §10 below) rows **are** the queue,
per `08-provider-abstraction.md` §3.3's explicit design — no separate queueing infrastructure at
this scale. A scheduled Edge Function (`studio-worker`, invoked every 3s via `pg_cron` + `pg_net`)
does two passes each invocation:

```typescript
// supabase/functions/studio-worker/index.ts
// Invoked on a schedule (pg_cron: "*/3 * * * * *" — every 3s), not per-request.

export async function runStudioWorker() {
  const provider = new HiggsfieldImageGenerationProvider();

  // Pass 1: submit anything queued (respecting the per-tier rate limiter, §7.2)
  const queued = await db.studioGenerations.selectWhere({ status: "queued" }).limit(20);
  for (const row of queued) {
    if (!(await withinRateLimit(row.userId))) continue; // stays queued; retried next tick
    try {
      const request = await buildGenerationRequest(row);       // §4 prompt builder
      const { providerJobId } = await provider.submitGeneration(request, ctxFor(row));
      await db.studioGenerations.update(row.id, {
        status: "generating",
        provider_job_id: providerJobId,
      });
    } catch (err) {
      await handleSubmitFailure(row, err); // §8 — never debits quota here
    }
  }

  // Pass 2: poll anything generating
  const generating = await db.studioGenerations.selectWhere({ status: "generating" }).limit(50);
  for (const row of generating) {
    const result = await provider.pollStatus(row.provider_job_id, ctxFor(row));
    if (result.status === "complete") {
      await db.studioGenerations.update(row.id, {
        status: "complete",
        result_image_path: result.resultStoragePath, // already re-hosted, §2.5
      });
      await debitQuota(row.userId, row.generation_path); // §8 — debited on success only
    } else if (result.status === "failed") {
      await handleGenerationFailure(row, result); // §8
    }
    // "generating"/"queued" from the provider: no-op, poll again next tick
  }
}
```

### 2.4 The polling contract behind `GET /studio/status/:id`

This endpoint is a **cheap read of Astra's own database**, not a proxy to Higgsfield — that
decoupling is deliberate: client poll frequency never translates into provider API load, and the
client can poll aggressively without Astra worrying about Higgsfield rate limits on its side.

```typescript
// supabase/functions/studio-status/index.ts
export async function handleStudioStatus(req: Request, generationId: string, userId: string) {
  const row = await db.studioGenerations.selectOne({ id: generationId, user_id: userId });
  if (!row) return json({ error: "not_found" }, 404);

  switch (row.status) {
    case "queued":
      return json({ status: "queued", queuePosition: await estimateQueuePosition(row) });
    case "generating":
      return json({ status: "generating", etaSeconds: estimateEtaSeconds(row) });
    case "complete":
      return json({
        status: "complete",
        resultUrl: await mintSignedUrl(row.result_image_path, { expiresIn: 3600 }),
        disclaimer: STUDIO_DISCLAIMER_TEXT, // attached at storage time, §2.6 — never composed here
      });
    case "failed":
      return json({
        status: "failed",
        retryable: row.is_retryable_failure,
        errorMessage: userFacingMessage(row.error_code), // never the raw provider error, §14
      });
  }
}
```

**Client poll contract:** 2s interval for the first 10s, backing off to 4s, capped at a 90s total
poll window before switching to a "taking longer than usual, we'll notify you" state (ties to
§20's 30s draft target plus queue-wait margin). Training status (`GET /studio/identity/status/:id`)
polls far less aggressively — every 15s — since the expected duration is minutes, and the client
should stop polling in the foreground and rely on a push notification for completion once the app
backgrounds.

### 2.5 Results land in Storage, never hotlinked

`persistResultToStorage` in the provider implementation (§3.4 below) is the one place a
Higgsfield-hosted URL is ever fetched server-side. The Edge Function downloads the bytes and
re-uploads them into Astra's own private bucket at the §15 path convention
(`users/{user_id}/studio/{generation_id}/result.{ext}`), then discards the provider URL entirely.
The client is only ever handed a short-lived Supabase Storage signed URL for that path. This
matters for three independent reasons: (1) §15/ADR 0010 require private-bucket-only, and a
provider-hosted URL is by definition outside that control; (2) provider-hosted result URLs are
typically themselves time-limited and would break the "permanent-save to lookbook" feature the
moment they expire; (3) it makes account/image deletion (§29) a single-prefix operation under
Astra's own storage, not a request to a third party whose deletion guarantees Astra doesn't
control.

### 2.6 Disclaimer attachment

Per `08` §8.1 step 6: the disclaimer is attached to the `studio_generations` row at the moment
`status` flips to `complete` inside the worker, not composed client-side at render time. This is
what makes "every generated image is labeled" (§6.17, §29) structurally guaranteed rather than a
per-screen discipline the client has to remember.

---

## 3. The `ImageGenerationProvider` implementation

Wraps Higgsfield behind the exact interface `08-provider-abstraction.md` §3 defines. Nothing in
this section changes that interface; it fills it in.

### 3.1 Client setup and shared types

```typescript
// supabase/functions/_shared/providers/higgsfield/client.ts

const HIGGSFIELD_API_BASE = "https://api.higgsfield.ai/v1"; // confirm exact base path at
                                                              // integration time against
                                                              // current API docs
const HIGGSFIELD_API_KEY = mustGetEnv("HIGGSFIELD_API_KEY"); // Edge Function secret only

interface HiggsfieldGenerateRequest {
  model: "soul_2";
  prompt: string;
  quality: "1.5k" | "2k";
  aspect_ratio: "1:1" | "16:9" | "9:16" | "4:3" | "3:4" | "3:2" | "2:3";
  medias: Array<{ role: "image"; url: string }>; // exactly 0 or 1 entries for soul_2
  soul_id?: string;                              // present only on the Studio Portrait path
}

interface HiggsfieldJobStatus {
  job_id: string;
  status: "queued" | "processing" | "completed" | "failed";
  output_url?: string;          // present when status === "completed"
  failure_reason?: string;      // present when status === "failed"
  failure_category?: "content_policy" | "capacity" | "invalid_input" | "unknown";
}

interface HiggsfieldTrainRequest {
  name: string;                 // internal label, not user-facing
  images: string[];             // signed, time-limited URLs to the training photos
}

interface HiggsfieldTrainStatus {
  soul_id: string;
  status: "training" | "ready" | "failed";
  failure_reason?: string;
}
```

### 3.2 Error mapping

```typescript
// supabase/functions/_shared/providers/higgsfield/errors.ts
import { ProviderError, ProviderErrorCode } from "../../../../core/providers/types.ts";

function mapHiggsfieldError(httpStatus: number, body: unknown): ProviderError {
  const category = (body as any)?.failure_category ?? (body as any)?.error_category;

  if (httpStatus === 401 || httpStatus === 403) {
    return new ProviderError("AUTH_FAILED", false, "Higgsfield rejected credentials", httpStatus);
  }
  if (httpStatus === 400 || category === "invalid_input") {
    return new ProviderError("INVALID_INPUT", false, "Higgsfield rejected the request payload", httpStatus);
  }
  if (httpStatus === 422 && category === "content_policy") {
    return new ProviderError(
      "CONTENT_MODERATION_REJECTED", false,
      "Higgsfield content moderation rejected the reference image or prompt", httpStatus,
    );
  }
  if (httpStatus === 402) {
    // Astra's own Higgsfield account balance/quota, NOT the user's Astra quota —
    // distinct failure mode, see §8.3.
    return new ProviderError("PROVIDER_QUOTA_EXCEEDED", false, "Higgsfield account balance exhausted", httpStatus);
  }
  if (httpStatus === 429) {
    return new ProviderError("RATE_LIMITED", true, "Higgsfield rate limit hit", httpStatus);
  }
  if (httpStatus >= 500) {
    return new ProviderError("PROVIDER_UNAVAILABLE", true, "Higgsfield returned a server error", httpStatus);
  }
  if (httpStatus === 408) {
    return new ProviderError("TIMEOUT", true, "Higgsfield request timed out", httpStatus);
  }
  return new ProviderError("UNKNOWN", false, `Unmapped Higgsfield error (HTTP ${httpStatus})`, httpStatus);
}
```

### 3.3 `submitGeneration` and `pollStatus`

```typescript
// supabase/functions/_shared/providers/higgsfield/HiggsfieldImageGenerationProvider.ts
import {
  ImageGenerationProvider, StudioGenerationRequest, StudioGenerationResult, ProviderRequestContext,
  ProviderError,
} from "../../../../core/providers/types.ts";
import { buildStudioPrompt } from "../../studio/promptBuilder.ts";
import { mapHiggsfieldError } from "./errors.ts";

export class HiggsfieldImageGenerationProvider implements ImageGenerationProvider {
  async submitGeneration(
    request: StudioGenerationRequest,
    ctx: ProviderRequestContext,
  ): Promise<{ providerJobId: string }> {
    const prompt = buildStudioPrompt(request);

    // soul_2 accepts at most one reference image. Studio Portrait mode still
    // attaches one — see §4's body-proportion mitigation for why this is not
    // optional even when soul_id is set.
    const referenceUrl = await mintProviderReadableUrl(request.referenceImageStoragePath, ctx);

    const payload: HiggsfieldGenerateRequest = {
      model: "soul_2",
      prompt,
      // Always request the best available quality. A live `get_cost` preflight against the
      // real Higgsfield API (§7.6) confirmed 1.5k and 2k bill identically (0.12 credits exact /
      // 1 credit billed, either way) — there is no cost reason left to ever request 1.5k, so
      // the abstract `resolution` field on StudioGenerationRequest (kept for §08 protocol
      // compatibility, in case a future/alternate vendor DOES price by quality tier) is
      // intentionally ignored here rather than threaded through to Higgsfield's `quality` param.
      quality: "2k",
      aspect_ratio: "3:4", // portrait editorial default matching §6.17's viewport; 9:16 offered
                            // as an explicit "share to story" export variant, not the default
      medias: [{ role: "image", url: referenceUrl }],
      soul_id: request.identityRepresentation ?? undefined,
    };

    const res = await fetch(`${HIGGSFIELD_API_BASE}/images/generations`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${HIGGSFIELD_API_KEY}`,
        "Content-Type": "application/json",
        "Idempotency-Key": ctx.idempotencyKey ?? crypto.randomUUID(), // required, §0.1 of `08`
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(ctx.timeoutMs),
    });

    if (!res.ok) throw mapHiggsfieldError(res.status, await safeJson(res));
    const body = (await res.json()) as { job_id: string };
    return { providerJobId: body.job_id };
  }

  async pollStatus(
    providerJobId: string,
    ctx: ProviderRequestContext,
  ): Promise<StudioGenerationResult> {
    const res = await fetch(`${HIGGSFIELD_API_BASE}/jobs/${providerJobId}`, {
      headers: { Authorization: `Bearer ${HIGGSFIELD_API_KEY}` },
      signal: AbortSignal.timeout(ctx.timeoutMs),
    });
    if (!res.ok) throw mapHiggsfieldError(res.status, await safeJson(res));
    const body = (await res.json()) as HiggsfieldJobStatus;

    if (body.status === "queued" || body.status === "processing") {
      return {
        status: body.status === "queued" ? "queued" : "generating",
        resultStoragePath: null, providerJobId, errorMessage: null, isRetryableFailure: false,
      };
    }
    if (body.status === "completed") {
      const resultStoragePath = await this.persistResultToStorage(body.output_url!, providerJobId, ctx);
      return { status: "complete", resultStoragePath, providerJobId, errorMessage: null, isRetryableFailure: false };
    }
    // status === "failed"
    const isModeration = body.failure_category === "content_policy";
    return {
      status: "failed",
      resultStoragePath: null,
      providerJobId,
      errorMessage: body.failure_reason ?? "unknown_provider_failure",
      isRetryableFailure: !isModeration, // §8.1's rule from `08` §3.2, restated concretely
    };
  }

  handleWebhook(_payload: unknown): StudioGenerationResult {
    // Higgsfield's job API is poll-based for soul_2 as of integration time — no documented
    // signed webhook callback for image generation jobs. This method exists to satisfy the
    // ImageGenerationProvider interface (which normalizes both delivery modes into one shape
    // per `08` §3) without forcing a redesign if webhook delivery becomes available later.
    // Wiring an actual webhook route to this method is future work, not present functionality.
    throw new ProviderError("UNKNOWN", false, "Webhook delivery not implemented for Higgsfield; use pollStatus.");
  }

  private async persistResultToStorage(
    providerOutputUrl: string, providerJobId: string, ctx: ProviderRequestContext,
  ): Promise<string> {
    const bytes = await fetchProviderAsset(providerOutputUrl, ctx.timeoutMs);
    const path = `users/${ctx.userId}/studio/${providerJobId}/result.jpg`;
    await storage.upload(path, bytes, { contentType: "image/jpeg", isPrivate: true });
    return path; // never the providerOutputUrl itself — §2.5
  }
}
```

### 3.4 Soul ID training

Not part of the `ImageGenerationProvider` interface as defined in `08` (that interface is
generation-only), so this lives as a sibling class the Edge Function layer calls directly for the
two new endpoints in §2.2 above. It follows the same request-context/error-mapping conventions as
every other provider call so it's uniform with the rest of the codebase, without forcing an
interface change onto the four other provider protocols that don't have an analogous "train an
identity" concept.

```typescript
// supabase/functions/_shared/providers/higgsfield/HiggsfieldIdentityTrainer.ts
export class HiggsfieldIdentityTrainer {
  async train(
    trainingImageStoragePaths: string[], // validated to be 20–80 in the Edge Function, §6.2
    ctx: ProviderRequestContext,
  ): Promise<{ providerJobId: string }> {
    const imageUrls = await Promise.all(
      trainingImageStoragePaths.map((p) => mintProviderReadableUrl(p, ctx)),
    );
    const payload: HiggsfieldTrainRequest = {
      name: `astra-user-${ctx.userId}`, // internal label only, never shown to the user
      images: imageUrls,
    };
    const res = await fetch(`${HIGGSFIELD_API_BASE}/souls/train`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${HIGGSFIELD_API_KEY}`,
        "Content-Type": "application/json",
        "Idempotency-Key": ctx.idempotencyKey ?? crypto.randomUUID(),
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(ctx.timeoutMs),
    });
    if (!res.ok) throw mapHiggsfieldError(res.status, await safeJson(res));
    const body = (await res.json()) as { job_id: string };
    return { providerJobId: body.job_id };
  }

  async pollTrainingStatus(providerJobId: string, ctx: ProviderRequestContext): Promise<HiggsfieldTrainStatus> {
    const res = await fetch(`${HIGGSFIELD_API_BASE}/souls/train/${providerJobId}`, {
      headers: { Authorization: `Bearer ${HIGGSFIELD_API_KEY}` },
      signal: AbortSignal.timeout(ctx.timeoutMs),
    });
    if (!res.ok) throw mapHiggsfieldError(res.status, await safeJson(res));
    return (await res.json()) as HiggsfieldTrainStatus;
  }

  /** Called from account deletion (§29) and the explicit "forget my Studio Portrait" control. */
  async revoke(providerSoulId: string, ctx: ProviderRequestContext): Promise<void> {
    const res = await fetch(`${HIGGSFIELD_API_BASE}/souls/${providerSoulId}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${HIGGSFIELD_API_KEY}` },
      signal: AbortSignal.timeout(ctx.timeoutMs),
    });
    // NOTE — must verify at integration time whether Higgsfield's API actually supports
    // soul deletion. If it does not, this is not an implementation gap Astra can code around;
    // it becomes a contractual requirement in Higgsfield's data-processing agreement
    // (mirrors risk-register #7's "provider retention terms" gate) and Astra's own privacy
    // policy must not overclaim deletion completeness until that's confirmed in writing.
    if (!res.ok && res.status !== 404) throw mapHiggsfieldError(res.status, await safeJson(res));
  }
}
```

---

## 4. Prompt construction

### 4.1 From structured outfit to `soul_2` prompt

The prompt builder consumes exactly the same `closet_items` attributes that drive compatibility
scoring (`05-wardrobe-graph.md`) — garment `category`, `primary_color`/`secondary_colors`,
`material`, `pattern`, `fit` — never a free-text re-description of the outfit. This is the same
principle `08` §8.2 established; this section extends it with the full advanced-control mapping
and worked presets.

```typescript
// supabase/functions/_shared/studio/promptBuilder.ts

interface GarmentInput {
  role: "top" | "bottom" | "outerwear" | "shoes" | "accessory";
  normalizedTitle: string;     // e.g. "knit crewneck sweater"
  colorDescription: string;    // resolved from primary_color (LCh) to a natural-language name
  material: string[];
  pattern: string;             // "solid" | "stripe" | "check" | ...
  fit: string;                 // "slim" | "regular" | "relaxed" | ...
}

interface AdvancedControls {
  preserveFace: boolean;               // default true
  preserveBodyProportions: boolean;    // default true
  preserveHairFacialHair: boolean;     // default true
  background: string;                  // enum, see §4.3
  pose: string;                        // enum, see §4.3
  formality: string;                   // "casual"|"smart_casual"|"business"|"black_tie" etc.
  season: string;                      // "spring"|"summer"|"autumn"|"winter"|"year_round"
  colorPalette: string;                // "tonal_neutrals"|"warm_earth"|"monochrome"|... (§4.4)
}

function describeGarment(g: GarmentInput): string {
  const patternFrag = g.pattern === "solid" ? "" : `, ${g.pattern}`;
  return `${g.role}: ${g.fit} ${g.colorDescription} ${g.normalizedTitle}${patternFrag}, ${g.material.join("/")}`;
}

export function buildStudioPrompt(
  garments: GarmentInput[],
  controls: AdvancedControls,
): string {
  const garmentList = garments.map(describeGarment).join("; ");

  const identityClauses: string[] = [];
  if (controls.preserveFace) {
    identityClauses.push(
      "Preserve his exact facial identity, bone structure, and natural expression style — do not idealize, smooth, or restyle the face.",
    );
  }
  if (controls.preserveHairFacialHair) {
    identityClauses.push("Preserve his current hairstyle and facial hair exactly as shown in the reference.");
  }
  if (controls.preserveBodyProportions) {
    identityClauses.push(
      "Preserve his exact build, shoulder width, torso length, and proportions as shown in the reference photo — do not slim, bulk, lengthen, or otherwise idealize his physique.",
    );
  }

  const paletteFrag = PALETTE_FRAGMENTS[controls.colorPalette] ?? "";

  return [
    "Create a realistic editorial menswear photograph using the provided authorized reference image.",
    ...identityClauses,
    `Dress him in: ${garmentList}.`,
    `Pose: ${POSE_FRAGMENTS[controls.pose] ?? controls.pose}.`,
    `Setting: ${BACKGROUND_FRAGMENTS[controls.background] ?? controls.background}.`,
    `Styling formality: ${FORMALITY_FRAGMENTS[controls.formality] ?? controls.formality}.`,
    `Season/light: ${SEASON_FRAGMENTS[controls.season] ?? controls.season}.`,
    paletteFrag ? `Overall color mood of lighting and setting (not garment recoloring): ${paletteFrag}.` : "",
    "Shot on a full-frame camera, shallow depth of field, magazine-quality retouching restraint — natural skin texture, no beauty filter smoothing.",
    "This image is a visual styling estimate, not an exact representation of garment fit, color, or body proportions.",
  ].filter(Boolean).join(" ");
}
```

**Note on `colorPalette`:** it deliberately affects only lighting/background/atmosphere framing,
never the garments themselves. Garment color comes from `closet_items.primary_color` and must
render as specified — a "tonal neutrals" palette control choosing to recolor a red sweater would
contradict the entire "exact garments from `closet_items`" design principle `08` establishes.

### 4.2 Advanced-control mapping table (§6.17)

| Control | Default | Prompt effect | Model-parameter effect |
|---|---|---|---|
| Preserve face | `true` | Identity-preservation clause (§4.1) | None — always the same `soul_2` call shape; `false` only reachable via an explicit secondary confirmation (rare, see §4.5) |
| Preserve body proportions | `true` | Proportion-honesty clause (§4.1); this is the primary lever discussed in §5 | Forces a reference image to be attached even in Studio Portrait mode (§5.2) |
| Preserve hair/facial hair | `true` | Hair/facial-hair clause | None |
| Background | preset-driven | `BACKGROUND_FRAGMENTS` lookup | None (`soul_2` has no separate background parameter — it's prompt-only) |
| Pose | preset-driven | `POSE_FRAGMENTS` lookup | None |
| Formality | preset-driven | `FORMALITY_FRAGMENTS` lookup | Also informs which `05-wardrobe-graph.md` formality-anchor garments are eligible to be selected into the outfit upstream of this call — the prompt builder receives an already-formality-consistent garment list, it doesn't reconcile a mismatch itself |
| Season | preset-driven | `SEASON_FRAGMENTS` lookup (lighting/atmosphere, e.g. "crisp autumn daylight" vs. "bright summer midday") | None |
| Color palette | preset-driven, optional | `PALETTE_FRAGMENTS` lookup — background/lighting mood only | None |

### 4.3 Pose / background fragment vocabulary (partial)

```typescript
const POSE_FRAGMENTS: Record<string, string> = {
  three_quarter_stance: "three-quarter standing stance, weight on the back foot, hands relaxed at his sides",
  walking_candid: "walking candid, mid-stride, slight turn toward camera",
  seated_relaxed: "seated, relaxed posture, forearms resting on his knees, three-quarter angle",
  hand_in_pocket: "standing, one hand in trouser pocket, confident open posture, direct gaze",
};

const BACKGROUND_FRAGMENTS: Record<string, string> = {
  studio_charcoal: "minimalist charcoal studio backdrop with a soft gradient, no props",
  city_dusk: "a dim, warm-lit city street at dusk, soft background bokeh",
  marble_interior: "a black marble interior with restrained architectural lines, matching Astra's own visual language",
  outdoor_daylight: "an outdoor setting in soft, overcast daylight, minimal background clutter",
};
```

### 4.4 Formality / palette fragment vocabulary (partial)

```typescript
const FORMALITY_FRAGMENTS: Record<string, string> = {
  casual: "relaxed, off-duty ease",
  smart_casual: "smart casual, elevated but unstructured",
  business: "business formal, boardroom-ready structure",
  black_tie: "formal eveningwear precision",
};

const PALETTE_FRAGMENTS: Record<string, string> = {
  tonal_neutrals: "tonal neutrals with a warm undertone",
  warm_earth: "warm earth tones",
  monochrome: "monochrome charcoal-to-white range with one restrained accent",
  deep_tonal: "deep tonal darks with a single warm highlight",
};
```

### 4.5 Worked examples — three of §6.17's eight presets

Each preset is a *default* `AdvancedControls` bundle a user can further override — not a
hardcoded prompt string. Garments below are the kind of structured input a real `closet_items`
row set would produce.

**Smart Casual**

```
garments = [
  { role: "top", normalizedTitle: "crewneck sweater", colorDescription: "navy", material: ["merino wool"], pattern: "solid", fit: "regular" },
  { role: "bottom", normalizedTitle: "chino trousers", colorDescription: "stone", material: ["cotton twill"], pattern: "solid", fit: "tapered" },
  { role: "shoes", normalizedTitle: "derby shoes", colorDescription: "brown", material: ["suede"], pattern: "solid", fit: "regular" },
  { role: "accessory", normalizedTitle: "watch", colorDescription: "brushed steel", material: ["steel", "leather"], pattern: "solid", fit: "regular" },
]
controls = { pose: "three_quarter_stance", background: "studio_charcoal", formality: "smart_casual",
             season: "autumn", colorPalette: "tonal_neutrals", preserveFace: true,
             preserveBodyProportions: true, preserveHairFacialHair: true }
```

Resulting prompt:

> "Create a realistic editorial menswear photograph using the provided authorized reference image.
> Preserve his exact facial identity, bone structure, and natural expression style — do not
> idealize, smooth, or restyle the face. Preserve his current hairstyle and facial hair exactly as
> shown in the reference. Preserve his exact build, shoulder width, torso length, and proportions
> as shown in the reference photo — do not slim, bulk, lengthen, or otherwise idealize his
> physique. Dress him in: top: regular navy crewneck sweater, merino wool; bottom: tapered stone
> chino trousers, cotton twill; shoes: regular brown derby shoes, suede; accessory: regular brushed
> steel watch, steel/leather. Pose: three-quarter standing stance, weight on the back foot, hands
> relaxed at his sides. Setting: minimalist charcoal studio backdrop with a soft gradient, no
> props. Styling formality: smart casual, elevated but unstructured. Season/light: crisp autumn
> daylight. Overall color mood of lighting and setting (not garment recoloring): tonal neutrals
> with a warm undertone. Shot on a full-frame camera, shallow depth of field, magazine-quality
> retouching restraint — natural skin texture, no beauty filter smoothing. This image is a visual
> styling estimate, not an exact representation of garment fit, color, or body proportions."

**Date Night**

```
garments = [
  { role: "top", normalizedTitle: "polo shirt", colorDescription: "black", material: ["silk-cotton blend"], pattern: "solid", fit: "slim" },
  { role: "outerwear", normalizedTitle: "unstructured blazer", colorDescription: "navy", material: ["wool"], pattern: "solid", fit: "slim" },
  { role: "bottom", normalizedTitle: "dress trousers", colorDescription: "charcoal", material: ["wool"], pattern: "solid", fit: "slim straight" },
  { role: "shoes", normalizedTitle: "chelsea boots", colorDescription: "black", material: ["leather"], pattern: "solid", fit: "regular" },
]
controls = { pose: "walking_candid", background: "city_dusk", formality: "smart_casual",
             season: "year_round", colorPalette: "deep_tonal", preserveFace: true,
             preserveBodyProportions: true, preserveHairFacialHair: true }
```

Resulting garment/scene fragment (identity clauses identical to above, omitted for brevity):

> "...Dress him in: top: slim black polo shirt, silk-cotton blend; outerwear: slim navy
> unstructured blazer, wool; bottom: slim straight charcoal dress trousers, wool; shoes: regular
> black chelsea boots, leather. Pose: walking candid, mid-stride, slight turn toward camera.
> Setting: a dim, warm-lit city street at dusk, soft background bokeh. Styling formality: smart
> casual, elevated but unstructured. Season/light: year-round evening. Overall color mood of
> lighting and setting (not garment recoloring): deep tonal darks with a single warm highlight..."

**Executive**

```
garments = [
  { role: "top", normalizedTitle: "dress shirt", colorDescription: "white", material: ["cotton poplin"], pattern: "solid", fit: "spread collar, slim" },
  { role: "outerwear", normalizedTitle: "suit jacket", colorDescription: "charcoal", material: ["wool"], pattern: "solid", fit: "notch lapel, slim" },
  { role: "bottom", normalizedTitle: "suit trousers", colorDescription: "charcoal", material: ["wool"], pattern: "solid", fit: "matching, tapered" },
  { role: "shoes", normalizedTitle: "oxford shoes", colorDescription: "black", material: ["leather"], pattern: "solid", fit: "regular" },
  { role: "accessory", normalizedTitle: "tie", colorDescription: "burgundy", material: ["silk"], pattern: "solid", fit: "regular" },
]
controls = { pose: "hand_in_pocket", background: "marble_interior", formality: "business",
             season: "year_round", colorPalette: "monochrome", preserveFace: true,
             preserveBodyProportions: true, preserveHairFacialHair: true }
```

Resulting garment/scene fragment:

> "...Dress him in: top: spread collar, slim white dress shirt, cotton poplin; outerwear: notch
> lapel, slim charcoal suit jacket, wool; bottom: matching, tapered charcoal suit trousers, wool;
> shoes: regular black oxford shoes, leather; accessory: regular burgundy tie, silk. Pose: standing,
> one hand in trouser pocket, confident open posture, direct gaze. Setting: a black marble interior
> with restrained architectural lines, matching Astra's own visual language. Styling formality:
> business formal, boardroom-ready structure. Season/light: year-round. Overall color mood of
> lighting and setting (not garment recoloring): monochrome charcoal-to-white range with one
> restrained accent..."

---

## 5. The body-proportion gap

### 5.1 What's actually verified vs. what's assumed

To be precise about the evidence, not just the conclusion: Higgsfield's documentation for Soul ID
states its preservation covers "facial structure, hair, expression style, and identity features."
It does not claim to preserve body proportions or skin tone beyond the face. That's a real,
specific, vendor-documented gap — not an inference from "generative image models are unreliable in
general." Meanwhile §13 step 5 requires "preserve proportions; do not beautify or alter body unless
explicitly requested," and §11's guardrail is explicit: "Do not promise garment fit from imagery
alone." Those two requirements sit directly on top of a capability the vendor has not documented
as guaranteed.

**Options considered and why each alone is insufficient:**

1. **Prompt-level constraints only** ("preserve his build and proportions exactly"). Cheap, already
   included (§4.1), and worth keeping — but it's asking the model to do something in the *absence*
   of any mechanism verified to make it reliable. A prompt instruction is a bias on generation, not
   a constraint the model is guaranteed to honor, and it is the weakest lever available here. Using
   it alone would be treating a documented gap as a prompting problem, which it isn't.
2. **Encode `body_profiles` measurements descriptively** (height, chest, waist, inseam). Adds
   signal but not photorealistic grounding — a text description like "6'1", 42" chest" cannot drive
   accurate proportion rendering from a diffusion-style image model the way an actual photo can.
   Worth doing as a *supplementary* bias (see §5.2), not a primary mitigation, and it raises its own
   sensitivity question (body measurements are the kind of data §29 says to minimize collection of
   — only send what's already been explicitly provided for fit purposes elsewhere, never solicit
   additional measurements specifically to feed a prompt).
3. **Require a full-body reference instead of a headshot.** Directionally correct and the strongest
   single lever available (see §5.2) — but insufficient by itself for the Studio Portrait path,
   where the entire point is treating a trained `soul_id` as reusable across sessions; if that
   reusability implicitly also means "reuse for body shape," the gap reappears every session that
   doesn't separately supply a fresh photo.
4. **Post-generation validation.** Useful as a sampled quality-assurance signal (§5.3), not viable
   as a synchronous per-generation gate at MVP given the existing 30s draft-generation latency
   budget (§20) is already tight without adding another model call in the critical path.
5. **Narrow the product promise to face-only.** The most conservative option, and the one to reject
   — it throws away the actual product value (seeing an outfit on your own body, not just your
   face) that §5.6/§6.17 are built around. Astra doesn't need to abandon body visualization; it
   needs to be honest that it's an estimate specifically on that axis, which is exactly what §6.17
   already requires it to disclose.

### 5.2 Recommended mitigation — layered, not single-lever

**Primary: a reference image is always attached, even on the Studio Portrait path.** This is the
one fact from §0 that makes the rest of this tractable: `soul_2` accepts `soul_id` *and* a
reference image in the same call. The design decision is to make that combination the norm, not
an edge case:

- **Quick Preview:** reference image only, no `soul_id`. Body proportions come entirely from
  whatever photo the user supplied for that session — as good or as limited as that one photo is.
- **Studio Portrait:** `soul_id` stabilizes facial identity across poses/scenes the training set
  never explicitly covered; the *concurrently supplied* reference image — a current photo the user
  attaches for that specific session, not one of the 20–80 training photos — is what grounds body
  proportions and skin tone for that particular generation. Soul ID is never asked to carry body
  information it was never documented to hold; a real photo is asked to do that job every time.

**Secondary: require the per-session reference to show the body, not just the face.** When
`preserveBodyProportions` is `true` (the default), the reference-image picker nudges toward a
half-to-full-body photo. This is enforced as a soft check, not a hard block — a lightweight
person-bounding-box pass (cheap relative to generation itself; can reuse the on-device Vision
framework detection already run for garment scanning, §12, applied instead to a person) flags a
tight headshot with: *"This looks like a close-up — for a proportion-accurate preview, use a photo
that shows more of you."* The user can proceed anyway (never a hard block on a personal photo the
user has consent over), but the default guidance pushes toward the input that actually helps.

**Tertiary: descriptive bias from `body_profiles`, only when already present.** If the user has
already provided height/build data elsewhere in the app (§6.6/§9's `body_profiles`), a short
directional clause is appended — e.g., "he is tall and broad-built; do not render him as slight or
short" — framed as bias correction against egregious errors, not a precision claim. Astra does not
prompt the user to provide new measurements specifically for this purpose (§29's data-minimization
principle).

**Quaternary: sampled post-generation QA, not a synchronous gate.** A scheduled process (not
per-generation, per §20's latency budget) pulls a random sample of completed generations weekly and
runs a coarse proportion-consistency check (shoulder-to-hip ratio, apparent height-to-width ratio
via a lightweight pose-keypoint pass) between each sampled generation's reference photo and its
output. This doesn't block any individual user's result; it feeds the quality-bar process in §9 and
the provider-evaluation loop in risk-register #4. A synchronous per-generation gate is worth
revisiting once this offline process has established the heuristic's false-positive rate — shipping
an unvalidated automated gate risks silently discarding good generations as often as it catches bad
ones.

**Quinary — and this is the one that actually satisfies §11/§6.17's disclosure requirement — a
body-specific disclaimer, not just a generic one.** The standard "visual styling estimate" language
(§13's prompt template, attached to every result per §2.6) is necessary but not sufficient here,
because it doesn't tell the user *which* axis is uncertain. The first time any user views a Style
Studio result (both paths), an additional, specific line appears, once, dismissible thereafter:

> "This preview keeps your face and general build recognizable, but exact body proportions, muscle
> definition, and skin tone can drift from your real photo — treat it as a styling and color idea,
> not a mirror."

That sentence is doing real work: §11 forbids implying exact fit or a guaranteed body outcome, and
§6.17 requires labeling output as an approximation — this converts a generic compliance disclaimer
into an accurate description of *where* the approximation is weakest, which is both more honest and
more useful to the user than a boilerplate "AI-generated, results may vary" line would be.

### 5.3 What Astra can and cannot promise — stated plainly

Astra can promise: a recognizable face, consistent across sessions if the user opts into Studio
Portrait; garments rendered faithfully to their actual color, material, and silhouette as recorded
in `closet_items`; an editorial-quality image, not a catalog cutout. Astra cannot promise: that the
generated body matches the user's actual body with any precision, that skin tone renders exactly,
or that the same outfit will look identical to how it fits in reality. That is a narrower promise
than "see yourself in the outfit," and the product design and copy above are built to say exactly
that narrower thing, not the broader one the underlying capability can't back up.

---

## 6. Consent and safety

Builds directly on `08-provider-abstraction.md` §8.3's consent-gate design; this section makes the
gate concrete: what's stored, what's checked, and what happens on a violation.

### 6.1 What the user affirms, and when

```
Captured once per reference image, at upload/import time (§6.7's onboarding capture, or the
Style Studio flow's "add a reference photo" action) — not a one-time global ToS checkbox:

  "This is a photo of me, or of someone who has given me clear permission to use their photo
   here." [I understand and agree]

Captured once per Studio Portrait training session (§1.2's capture screen), IN ADDITION to the
per-image attestation above, since training aggregates many photos in one action:

  "All of these photos are of me. I'm training a private model of my own face that Astra will
   use only for my own Style Studio generations." [I understand and agree]
```

Both are explicit, specific statements about what's being attested — not generic Terms-of-Service
boilerplate — per `08` §8.3's judgment call that specificity is the actual technical/product
backstop available here, since the attestation itself cannot be cryptographically verified.

### 6.2 How it's recorded

```sql
create table studio_consent_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  reference_image_id uuid references reference_images(id), -- null for a training-session-level record
  scope text not null check (scope in ('single_reference', 'soul_training_batch')),
  attested_at timestamptz not null default now(),
  terms_version text not null,
  attestation_text_hash text not null, -- hash of the exact copy shown, so a later copy change
                                        -- is auditable against what the user actually agreed to
  device_id text,
  created_at timestamptz not null default now()
);

alter table studio_consent_records enable row level security;
create policy studio_consent_records_owner on studio_consent_records
  using (user_id = auth.uid());
```

### 6.3 Enforcement in practice — the gate is server-side, at the Edge Function

```typescript
// supabase/functions/_shared/studio/consentGate.ts
export async function assertStudioConsent(
  userId: string, referenceImageId: string, currentTermsVersion: string,
): Promise<void> {
  const record = await db.studioConsentRecords.selectOne({
    user_id: userId, reference_image_id: referenceImageId, scope: "single_reference",
  });
  if (!record) {
    throw new EdgeFunctionError("CONSENT_MISSING", "This reference photo hasn't been confirmed yet.");
  }
  if (record.terms_version !== currentTermsVersion) {
    // Terms changed since attestation — re-required, not silently carried forward, per `08` §8.3.
    throw new EdgeFunctionError("CONSENT_STALE", "Please confirm the updated terms before generating.");
  }
  const image = await db.referenceImages.selectOne({ id: referenceImageId, user_id: userId });
  if (!image || image.deleted_at) {
    throw new EdgeFunctionError("REFERENCE_UNAVAILABLE", "That reference photo is no longer available.");
  }
  if (image.moderation_status !== "approved") {
    throw new EdgeFunctionError("MODERATION_PENDING_OR_REJECTED", "That photo can't be used for a generation.");
  }
}
```

This runs before `submitGeneration` is ever called — inside the `studio-worker`'s submit pass
(§2.3), not just at the point the user taps "generate" client-side, so there is no path (retry,
cached job resubmission, a client bug) that reaches Higgsfield without it. A missing or stale
consent record fails fast with a specific message and — critically — **does not consume quota**
(§8 below).

### 6.4 Content-safety check and its failure path

Server-side, on the reference image, **before** it is ever sent to Higgsfield:

```
1. Image uploaded → moderation_status = "pending"
2. Async moderation call (Higgsfield's built-in input moderation if its coverage is sufficient
   at integration time, per `08` §8.3 step 3, else a dedicated moderation provider call) checks
   for: apparent minors, non-consensual/exploitative content categories, and content outside
   "an authorized personal reference photo" (e.g., a screenshot of someone else's public social
   media post, a stock photo, a public figure).
3. On reject → moderation_status = "rejected", the image is NOT eligible as a generation
   reference, and the user sees a direct, non-accusatory message: "This photo can't be used for
   Style Studio. Try a clear photo of yourself in good lighting." — the copy does not accuse the
   user of anything (false positives happen), it just states the outcome and the fix.
4. On approve → moderation_status = "approved", eligible for generation per §6.3.
```

### 6.5 What happens if a user uploads someone else's photo

This is the honest limit: **there is no reliable technical proof that a photo is or isn't "of the
uploader, or someone who gave them permission."** The design doesn't pretend otherwise (per `08`
§8.3's judgment call). The actual layered response:

1. **The explicit, specific attestation** (§6.1) — not a generic ToS checkbox — creates a clear
   record of what was represented, which matters for account-level enforcement and for Astra's own
   Terms-of-Service position, even though it can't stop the upload itself.
2. **Content moderation** (§6.4) catches the categories it's actually capable of catching (minors,
   non-consensual content categories, public-figure/celebrity likeness where the provider's
   moderation supports that detection) — this is a real backstop for the worst cases, not a
   complete solution for "any unauthorized photo of an ordinary adult," which no automated system
   can reliably detect from image content alone.
3. **A report path**, distinct from the "this doesn't look right" quality-report flow already
   specified in risk-register #4: `POST /studio/generations/:id/report` with a `reason` field
   including `"unauthorized_photo"`. Any generation (not just the uploader's own) can be reported —
   this matters because the person most likely to know a photo was used without permission is
   often not the uploader.
4. **Progressive enforcement** on a confirmed violation (human-reviewed report, or a moderation
   rejection pattern): warning → temporary Style Studio suspension → account-level review, with the
   `studio_consent_records` attestation history as the audit trail for that review. This is a
   process/policy control, consistent with how `08` §8.3 frames the whole gate — not something a
   single algorithmic check can fully replace.

---

## 7. Cost control

> **Pricing correction, verified via live API preflight.** An earlier version of this section
> priced `soul_2` generations from a flagged, explicitly-unverified assumption (4–6 credits,
> $0.20–$0.30/generation). A live `get_cost` preflight run directly against the Higgsfield API —
> not an estimate — returned the real figures used throughout this section: **0.12 credits exact
> per generation, billed as 1 credit** (the API appears to round up per job), and **`1.5k` and `2k`
> quality tiers cost identically** (checked explicitly, both return 0.12 credits exact / 1 credit
> billed). At the verified $0.05/credit rate (25-credit training ≈ $1.25, unchanged and consistent
> with the earlier assumption), that's **$0.05/generation at the conservative, rounded-billing
> rate, or $0.006/generation at the exact metered rate** — against the earlier $0.20 (draft) /
> $0.30 (hi-res) assumption, that's roughly 4–6× too pessimistic at the conservative rate and
> roughly 30× too pessimistic at the exact rate. $0.05 is used as the planning number throughout
> this section (conservative, assumes Astra is billed per-job at the rounded rate); $0.006 is
> noted as the likely floor. This correction changes the quota design (§7.2), invalidates the
> draft-then-export cost rationale as originally stated (§7.4), and changes the conclusion of
> the monthly cost model (§7.7 and `11-risk-register.md` §5).

### 7.1 Queue design

Covered in §2.3 — `studio_generations`/`studio_identity_profiles` rows are the queue; a scheduled
worker submits and polls, respecting the rate limiter below before every submit. This is what makes
the rest of this section possible at all: nothing calls Higgsfield synchronously from a user
request.

### 7.2 Per-tier rate limits — re-derived, since spend is no longer the binding constraint

**The original 15/month Premium quota was sized to contain a cost that turned out to be wrong by
roughly an order of magnitude.** At $0.05/generation (planning rate), even a generous 60/month
quota costs Astra $3.00 — trivial against $12.99 gross. Spend is no longer a reason to keep the
quota tight. What's actually binding now:

- **Queue latency/throughput (§20's 30s draft-generation target, §2.3–2.4).** The `studio-worker`
  processes a bounded number of jobs per pass; Higgsfield's own account-level rate limit on
  Astra's API key (unknown until load-tested, but real) is a hard ceiling regardless of what
  per-user quota Astra sets. A single account generating in a tight loop can degrade the
  queue-wait ETA for every other concurrent user (§2.4) even though it costs almost nothing.
  This argues for a **burst/concurrency limiter independent of the monthly total** — the actual
  operational control — not for keeping the monthly number small.
- **Storage cost and volume**, not modeled in dollar terms in this document but real: every
  generation is a stored image (30-day default retention, ADR 0010) regardless of how cheap the
  provider call was. A materially larger quota means materially more standing storage and a
  larger surface for the deletion/retention job (ADR 0010) to process correctly. Worth monitoring,
  not worth gating the whole feature on.
- **Product positioning (§3: "a luxury stylist's editorial notebook").** An effectively-unlimited
  "generate as many images of yourself as you want" feature reads as a novelty AI image toy, not a
  considered styling tool — at odds with the product's stated differentiation from a generic
  AI-image app. A quota that's generous but still present preserves Style Studio as a deliberate,
  curated action tied to an actual outfit decision, not an infinite content faucet.
- **Moderation/consent review load (§6)** scales with generation volume regardless of unit cost —
  more generations means more content moving through the consent and content-safety pipeline,
  which has a real (if currently unquantified) operational cost distinct from the Higgsfield bill.

Re-derived quota:

| Tier | Monthly generation quota | Resolution | Studio Portrait training |
|---|---|---|---|
| Guest | 1 lifetime (not monthly), Quick Preview only | `2k` (always, §7.4) | Not available |
| Free | 1 lifetime (not monthly), Quick Preview only | `2k` (always, §7.4) | Not available |
| Premium | **60/month**, pooled across Quick Preview and Studio Portrait, no resolution-based sub-limit (there is no cheaper tier to gate behind, §7.4) | `2k` (always) | Available; one active trained identity per user; retraining allowed but not separately rate-limited |

A token-bucket limiter keyed on `(user_id, subscription_tier)` still enforces the monthly ceiling,
but it's now explicitly a **backstop against abuse and unbounded operational load, not a spend
control** — the honest framing, now that the numbers are known. A secondary **burst limiter**
(e.g., max 5 concurrent in-flight generations per user, independent of the monthly pool) protects
the §20 latency target under load, which the monthly ceiling alone doesn't address.

Guest and Free still share a **single lifetime allotment**, not two separate ones — keyed at
signup to device/identity signals available at that point (§7.3). This remains a
**conversion-funnel and abuse-prevention gate, not a cost-containment one** — worth stating
explicitly now that the two used to be conflated: "one free taste, then subscribe" is a
monetization decision independent of what that one generation costs Astra.

Studio Portrait access remains gated on **active** Premium — but the justification changes with
this correction. At $1.25 one-time (still ~25× a single generation's cost, but trivial against a
$12.99/month subscription — under 10% of one month's revenue, once), **cost no longer justifies
the gate on its own.** The real reasons to keep it Premium-only: (1) the 20–80 photo capture is
real user effort, and offering it to a not-yet-committed user risks wasting that effort on someone
who churns before getting value from it; (2) a trained, reusable identity is a genuine retention
lever — it's a reason to stay subscribed, which is a product argument, not a cost one; (3)
routing 20–80 personal photos through consent/moderation/storage for an unproven user is
operational overhead worth reserving for users who've already shown intent, independent of the
dollar cost being small; (4) the existing "offer it only after a Quick Preview" sequencing (§1.1)
already assumes a demonstrated-interest gate ahead of the training ask, and Premium-only is
consistent with that logic. A lapsed subscriber's `studio_identity_profiles` row and
`provider_soul_id` are still retained (so a resubscribe doesn't require retraining), but
generation using that identity is blocked while the subscription is inactive, same as any other
Premium-gated feature.

### 7.3 Cache key

Extends `08` §3.3's cache-key design to cover the identity-token path, since the Studio Portrait
path doesn't have a single stable "reference image" the way Quick Preview does:

```typescript
function studioCacheKey(req: StudioGenerationRequest & { identityRepresentation?: string }): string {
  const identityComponent = req.identityRepresentation ?? req.referenceImageStoragePath;
  return sha256([
    identityComponent,
    JSON.stringify(req.structuredGarmentList),
    req.pose, req.background, req.lighting ?? "", req.formality,
    req.preserveFace, req.preserveBodyProportions, req.preserveHairFacialHair,
    req.resolution,
  ].join("|"));
}
```

Cache TTL: 90 days, matching `08` §3.3. A hit returns the stored `result_image_path` and does not
debit quota or call Higgsfield — this is the single highest-value cost control for a UI pattern
like "compare this outfit against last week's," where the same identity+outfit combination is
genuinely likely to recur.

### 7.4 Draft vs. export — the spec's stated rationale doesn't hold for this vendor

§13's cost controls call for "lower-cost draft generation before high-resolution export." **That
rationale does not hold against Higgsfield's actual pricing: `1.5k` and `2k` cost identically
(§7.6, verified via live preflight), so generating a `1.5k` draft before a `2k` export saves
Astra nothing and, under the original two-call design (a separate `submitGeneration` call for the
export step), would have *doubled* the credit spend on any outfit a user chose to keep — the
opposite of a cost control.** This section says so plainly rather than silently keeping a
two-step flow whose stated justification is false for this provider.

**What changed:** every generation — Quick Preview or Studio Portrait — now requests `2k` directly
(§3.3). There is no lower-cost tier being traded away, so there's nothing to gate behind a preview
step on cost grounds. The `resolution` field remains on `StudioGenerationRequest` for `08`'s
protocol generality (a future or alternate vendor that genuinely prices by quality tier can still
use it as a real lever), but the Higgsfield implementation ignores it and always requests best
quality.

**What "draft vs. export" now means instead — repurposed, not removed:** the two-step feel §13
was reaching for (show something cheap and provisional, let the user decide whether it's worth
keeping) is still a reasonable product idea — it just isn't a *generation-resolution* distinction
anymore. It's re-justified as a **storage-retention** distinction, which ADR 0010 already has
infrastructure for: every completed generation is `2k` by default and expires after 30 days
(§7.5) unless the user takes the explicit "save to lookbook" action, which flips a flag on the
*same* row rather than triggering a second, more-expensive provider call. This preserves the
"nobody commits to a result before seeing it" spirit of §13 without the false cost pretense, and
it's cheaper than the original two-call design, not more expensive: **one generation call per
outfit, always at best quality, ever.**

**Latency, not cost, is the one open question worth validating before removing the two-step UI
pattern entirely.** It's plausible — though not verified by the preflight, which checked cost
only — that `2k` generation takes measurably longer than `1.5k` given the larger pixel count
(2000px vs. 1500px longest edge is roughly 1.8× the pixel area), which would interact with the
§20 30-second draft-generation target. Recommendation: measure real generation latency at both
quality tiers before finalizing that every path always requests `2k` with no faster preview
option. If `2k` latency is statistically indistinguishable from `1.5k`, this document's "always
request `2k`" design (§3.3) stands as-is. If `2k` is meaningfully slower, a low-resolution preview
step is worth reintroducing — justified explicitly on latency/perceived-responsiveness grounds,
never again on cost, and the UI copy should not imply "draft" means "worse" so much as "fast look
before the full-quality one finishes."

### 7.5 Retention

Per ADR 0010, restated with the Studio-Portrait-specific addition:

- Reference images used as generation input: retained only while attached to an active/eligible
  session; abandoned uploads deleted after 24h.
- Generated outputs: 30-day default retention unless the user saves to lookbook (permanent).
- **Soul ID training photos (new, this document): deleted immediately after training completes or
  fails** — the 20–80 raw photos are the highest-volume, highest-sensitivity input in the entire
  pipeline, and there is no product reason to retain them past the training call itself. Only the
  `provider_soul_id` token and a single small cover thumbnail (for the user's own "your Studio
  Portrait is ready" UI, not used as generation input) persist in `studio_identity_profiles`.

### 7.6 Per-generation cost — verified via live API preflight

**Verified, not assumed — a live `get_cost` preflight was run directly against the real Higgsfield
API, both for a standard generation and explicitly for both quality tiers:**

```
soul_2 generation, 1.5k:  0.12 credits exact, billed as 1 credit
soul_2 generation, 2k:    0.12 credits exact, billed as 1 credit   (identical to 1.5k)
Soul ID training:         25 credits ≈ $1.25  →  $0.05/credit (verified, unchanged)
```

Quality tier does not affect cost — confirmed by checking both explicitly, not inferred. Two
readings follow from the billed-vs-exact distinction:

```
Conservative planning rate (per-job billing rounds up to 1 credit):
  1 credit × $0.05/credit = $0.05/generation — used throughout this document

Likely floor (exact metered rate, if any future billing arrangement bills the exact figure
rather than the rounded-up per-job credit):
  0.12 credits × $0.05/credit = $0.006/generation
```

The earlier version of this document flagged this as the single most important unverified
number in the whole integration — it no longer is. **§7.2's quota and §7.7's monthly figure below
use $0.05/generation as the planning number; the $0.006 floor is noted for completeness but not
relied on for any commitment, since it depends on a billing-rounding behavior ("bills exact" vs.
"bills rounded-up per job") that hasn't itself been separately confirmed.**

```
Any generation, either tier: 1 credit × $0.05/credit = $0.05/generation  (planning rate)
Soul ID training:            25 credits × $0.05/credit = $1.25 (one-time, "reusable indefinitely")
```

### 7.7 Monthly cost of a Premium user at the proposed quota

At the re-derived §7.2 quota (60/month), full utilization — the worst-realistic-case framing this
document has used throughout, not a typical-usage estimate:

```
60 generations × $0.05/generation (planning rate) = $3.00/month  (full quota utilization)
60 generations × $0.006/generation (floor rate)    = $0.36/month  (full quota utilization)
```

A more realistic "actively engaged, not quota-maxing" usage assumption — roughly one generation
per weekday, ~20/month, consistent with the "engaged subscriber" volumes used elsewhere in this
model (`11-risk-register.md` §5):

```
20 generations × $0.05/generation (planning rate) = $1.00/month
```

Amortized one-time training cost, over an assumed 6-month average retention window before a
hypothetical retrain:

```
$1.25 / 6 months ≈ $0.21/month amortized
```

**Realistic engaged-subscriber total: $1.00 + $0.21 ≈ $1.21/month** (planning rate) — down from
the earlier, incorrectly-priced $3.61/month, and now a genuinely minor line item rather than the
largest one. Even the worst-case full-quota-utilization figure ($3.00–3.21/month including
training) is smaller than the earlier steady-state estimate. This figure feeds directly into the
revised per-subscriber cost model in `11-risk-register.md` §5, which restates the conclusion:
**Style Studio is no longer the dominant or least-certain cost line — Kyra conversation volume is,
again, as it was before the (incorrect) intermediate revision of this document.**

---

## 8. Failure handling

### 8.1 The accounting that makes "no credit consumed on provider failure" actually true

Per §21 and `08` §3.2: quota is **debited on `status === "complete"`, never on submission**. The
worker code in §2.3 makes this literal — `debitQuota` is called exactly once, in the branch that
handles a completed poll result, and nowhere else in the submit/poll/failure paths. A row that
never reaches `complete` — regardless of how many times it's retried — never touches the user's
`(user_id, subscription_tier)` token bucket.

```typescript
async function handleGenerationFailure(row: StudioGenerationRow, result: StudioGenerationResult) {
  const isModeration = result.errorMessage?.includes("content_policy");
  await db.studioGenerations.update(row.id, {
    status: "failed",
    error_message: result.errorMessage,
    is_retryable_failure: !isModeration,
    // prompt_payload is untouched — it was written once at submission time and is never cleared
    // on failure, which is what makes "retry without reconfiguring anything" (§21) possible.
  });
  // No quota debit call anywhere in this path. Nothing to undo — nothing was ever charged.
}
```

A retry from the client re-submits by creating a **new** `studio_generations` row that copies
`prompt_payload` from the failed one verbatim (never asking the user to reselect the outfit,
reference photo, or advanced controls) — the failed row stays in the table as an audit record with
`status = "failed"`, not deleted.

### 8.2 Full failure taxonomy

| Failure | Detected how | Retryable? | Quota impact | User-facing message |
|---|---|---|---|---|
| **Provider timeout** | `submitGeneration`/`pollStatus` exceeds `ctx.timeoutMs`; §0.1 baseline applies (1 automatic retry, jittered backoff) | Yes, automatically once, then surfaced with a manual retry option | None — never reached `complete` | "That took longer than expected. Try again?" |
| **Content rejection** | `failure_category === "content_policy"` from Higgsfield, or Astra's own pre-submission moderation gate (§6.4) rejects first | No — not retried automatically, per `08` §3.2 | None | Specific, non-accusatory message per §6.4 — never "your photo violated our policy" in a way that reads as an accusation when it may be a false positive |
| **Training failure** | `HiggsfieldTrainStatus.status === "failed"` — typically insufficient photo variety/quality (per Higgsfield's stated guidance: sunglasses, masks, extreme expressions hurt training) | Yes — training is retried by re-submitting a (possibly improved) photo set; the original photo set is NOT auto-retried blindly, since a training failure is often a signal the input needs to change, not that it was transient | No quota impact — training doesn't consume the generation quota in the first place | "I had trouble learning from those photos — try a wider mix of angles and lighting, and skip anything with sunglasses or a big grin." |
| **Quota exhaustion (Astra's own Higgsfield account, not the user's)** | `PROVIDER_QUOTA_EXCEEDED` (HTTP 402 from Higgsfield, §3.2) | No — this is an operational/billing problem on Astra's side, not the user's request | Does not consume the user's quota — the row stays `queued`, retried by the worker once Astra's own balance is topped up, or explicitly fails with an apologetic message if the outage is prolonged | "Style Studio is briefly at capacity — you haven't lost your turn, we'll pick this back up shortly." (Distinct from the user hitting *their own* monthly cap, which is a different, expected, non-error state with its own upsell-to-Premium or "resets on [date]" messaging.) |
| **Degraded output (subjectively bad but technically "complete")** | Not automatically detected at generation time (§5.2's post-generation validation is sampled/offline, not synchronous) — surfaced via the user-initiated "this doesn't look right" report path (risk-register #4) | User-initiated regeneration after reporting does not consume additional quota — a reported generation's retry is treated the same as a provider-side failure for quota purposes, since the point of the report path is exactly to not penalize the user for a result Astra's own pipeline produced | "Thanks — that one's on us, not your quota. Want me to try again?" |

---

## 9. Quality bar and evaluation

### 9.1 Why this needs a real bake-off, not a vendor demo review

Higgsfield/`soul_2` is the decided vendor for this integration, but `08` §3.5 lists real
alternatives on the same platform (`nano_banana_pro`, `nano_banana_2`, `gpt_image_2`) specifically
because identity-preservation quality "is the hardest thing to fake with prompting alone" and
varies by vendor in ways a spec sheet doesn't capture. This section is the evaluation protocol to
run before broad launch, and again any time Higgsfield changes model behavior underneath a fixed
name (risk-register #9e).

### 9.2 Protocol

```
Test set: 12–15 internal, consented staff/contractor identities, deliberately diverse across
  build (slim/athletic/heavier-set), height, skin tone, age range, and hair/facial-hair style —
  the diversity axis matters specifically because identity-preservation and proportion-honesty
  failures are not uniformly distributed across appearance.

Per identity, capture: 1 headshot, 1 half-body, 1 full-body reference photo (tests reference-
  image robustness across framing) — and for a 5-identity subset, a full Soul ID training set
  (20–30 photos) to test the trained path specifically.

Matrix: 15 identities × 3 presets (Smart Casual, Date Night, Executive — the ones with worked
  prompts in §4.5) × 4 candidates (soul_2 without soul_id, soul_2 with soul_id, nano_banana_pro,
  gpt_image_2) = 180 generations. At the §7.6 verified per-generation cost, the soul_2 legs of
  this matrix cost on the order of $4.50 (90 generations × $0.05 planning rate) — cheaper still
  than the earlier, incorrectly-priced $35–55 estimate; the two non-Higgsfield candidates' cost
  depends on their own pricing, not covered by this document's preflight. Cheap enough to re-run
  per model-version change, not just once.

Blind scoring: 2–3 reviewers with real styling judgment (per risk-register #1's precedent —
  "real stylists, not just engineers") score every generation with model identity hidden.
```

### 9.3 Scoring rubric

| Criterion | Scale | What it's actually checking |
|---|---|---|
| Identity fidelity | 1–5 | Does this read as the same person's face as the reference — not just "a plausible face"? |
| Garment accuracy | fraction correct (e.g. 4/5) | For each item in the structured garment list: present, correct color, correct silhouette/fit — checked item-by-item against the exact input, not a vibe check on "does it look dressed" |
| Proportion honesty | 1–5 | Does the rendered build match the reference photo's proportions, or has it been idealized/distorted? Directly tests §5's gap |
| Editorial quality | 1–5 | Lighting, composition, retouching restraint — does it read as fashion editorial (§3 brand positioning) or as a cheap AI render / catalog cutout? |
| Artifact absence | pass/fail checklist | Extra/missing fingers, garments blending into skin, texture warping, facial asymmetry, background artifacts |

**Composite:** identity fidelity 30%, garment accuracy 25%, proportion honesty 20%, editorial
quality 15%, artifact-absence pass-rate 10% — with an override rule: any generation with an
artifact-checklist failure caps its composite score regardless of other criteria, since an
egregious artifact is disqualifying on its own for a premium-positioned product, not just a minor
deduction.

**Decision gate:** a candidate ships (or stays shipped, on a re-run) only if its composite clears a
set minimum **and** its artifact-free rate exceeds 90% across the full matrix — not just on
average, since a model that's excellent on easy cases and bad on hard ones (e.g., specific builds
or skin tones) is exactly the failure mode the diverse test set exists to catch.

### 9.4 Ongoing, not one-time

The same rubric backs the sampled proportion-consistency QA in §5.2 and the internal quality-review
process risk-register #4 already calls for before enabling a new provider or prompt-template
version in production. This bake-off is the structured version of that process, run before launch
and re-run on provider/model change — not a separate, one-off exercise.

---

## 10. Data model additions

New tables and columns needed beyond §9's existing `studio_generations`, to support the tiered
design. Written for a future migration, not yet applied.

```sql
-- New table: trained identities. One row per user's active Soul ID (at most one "ready" row
-- per user in the product design, though the schema doesn't hard-enforce that in case of a
-- deliberate retrain-and-compare flow later).
create table studio_identity_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  provider text not null default 'higgsfield',
  provider_soul_id text,                    -- null until training completes
  provider_job_id text,                     -- Higgsfield's training job id, for status polling
  status text not null check (status in ('queued','training','ready','failed','revoked')),
  training_image_count int not null,
  training_started_at timestamptz,
  training_completed_at timestamptz,
  consent_record_id uuid not null references studio_consent_records(id),
  cover_thumbnail_path text,                -- small, UI-only; never used as generation input
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table studio_identity_profiles enable row level security;
create policy studio_identity_profiles_owner on studio_identity_profiles
  using (user_id = auth.uid());

-- Extends studio_generations (§9 of the master spec) with the fields the tiered design needs:
alter table studio_generations
  add column identity_profile_id uuid references studio_identity_profiles(id),
  add column generation_path text not null default 'quick_preview'
    check (generation_path in ('quick_preview', 'studio_portrait')),
  -- `resolution` kept for `08` protocol generality (a future/alternate vendor may genuinely
  -- price by quality tier); the Higgsfield provider implementation always requests '2k'
  -- regardless of this value, since 1.5k/2k are cost-identical for soul_2 (§7.4, §7.6,
  -- verified via live preflight) — there is no vendor-side reason left to request 1.5k.
  add column resolution text not null default 'hi_res' check (resolution in ('draft', 'hi_res')),
  -- "save to lookbook" (§7.4, §7.5) is a retention-flag flip on THIS row, not a second,
  -- separately-billed generation — replaces the earlier draft_generation_id two-call design,
  -- which the pricing correction showed would have doubled credit spend for no benefit.
  add column saved_to_lookbook_at timestamptz,
  add column cache_key text,
  add column is_retryable_failure boolean,
  add column quota_debited boolean not null default false; -- explicit flag backing §8.1's accounting

create index idx_studio_generations_cache_key on studio_generations(cache_key)
  where cache_key is not null;

-- Consent, per §6.2:
create table studio_consent_records ( -- (full definition in §6.2 above)
  ...
);
```

`identity_profile_id` is nullable and only ever set for `generation_path = 'studio_portrait'` rows
— it is the concrete implementation of `ImageGenerationProvider.StudioGenerationRequest`'s
`identityRepresentation` field (`08` §3) for the Higgsfield case specifically.

### 10.1 Deletion propagation (§15, §29)

```
Deleting an individual reference image (§29's explicit user control):
  → invalidates the associated studio_consent_records row's eligibility (§6.3 checks image
    deleted_at), removes the image from the eligible-reference list. Does NOT delete a
    studio_generations row that already completed using it — the output is an independent,
    already-generated asset with its own retention lifecycle (§7.5).

Deleting/revoking a Studio Portrait identity (user-initiated "forget my face" control, new,
this document — a natural extension of §29's individual-deletion requirement to the identity
feature this document adds):
  → HiggsfieldIdentityTrainer.revoke() called (§3.4)
  → studio_identity_profiles.status = 'revoked', revoked_at set (soft delete — retains the
    audit trail of consent/training history; the provider_soul_id itself, however, is expected
    to be unusable post-revocation per the revoke() call)
  → studio_generations.identity_profile_id is NOT nulled retroactively on past rows — those
    generations already happened and their output images are unaffected; revocation only
    prevents FUTURE generations from referencing this identity
  → Future submitGeneration() calls check identity_profile_id.status = 'ready' before including
    soul_id in the request; a revoked identity simply can't be selected in the UI going forward

Account deletion (§15, §29 — full cascade):
  → every studio_identity_profiles row for the user: HiggsfieldIdentityTrainer.revoke() called,
    row hard-deleted (not soft, since the user no longer exists to retain an audit trail for)
  → every studio_generations row: hard-deleted, storage objects under
    users/{user_id}/studio/... hard-deleted via the prefix-delete pattern (ADR 0010)
  → every studio_consent_records row: hard-deleted
  → reference images under users/{user_id}/references/...: hard-deleted
  → this is the existing §15 deletion-job pattern (user-visible status if not synchronous) —
    this document adds studio_identity_profiles and studio_consent_records to that job's
    table list, it doesn't change the job's shape
```

---

## 11. Open items for Tyler

- ~~Confirm real Higgsfield per-generation credit cost~~ — **resolved.** A live `get_cost`
  preflight against the real Higgsfield API confirmed 0.12 credits exact / 1 credit billed per
  generation, identical at `1.5k` and `2k` (§7.6). §7.2's 60/month quota and §7.7's monthly cost
  figure are built on this verified number, not an assumption. This is no longer the
  highest-leverage unknown in the document — see the next two items for what is.
- **Validate whether `2k` generation latency meaningfully exceeds `1.5k`** (§7.4) — the cost
  preflight checked cost only, not latency. This now matters more than the old cost question:
  it determines whether "always request `2k`, no draft-resolution preview step" (§3.3) is safe
  against the §20 30-second target, or whether a latency-justified (not cost-justified) preview
  step should be reintroduced.
- **Load-test Higgsfield's own account-level rate limit against the new 60/month Premium quota**
  (§7.2) — now that spend doesn't bound the quota, the queue-throughput/latency constraint
  (§2.3–2.4) is the real ceiling, and it hasn't been measured. Confirm the burst/concurrency
  limiter's threshold empirically rather than as a placeholder "5 concurrent" guess.
- **Confirm whether Higgsfield's API supports Soul ID deletion** (§3.4's `revoke()`) — if it
  doesn't, this becomes a data-processing-agreement requirement with Higgsfield (mirrors
  risk-register #7), not something Astra's Edge Function code can guarantee on its own, and the
  privacy policy language (§29) must not overclaim deletion completeness until that's resolved.
- **Confirm the exact Higgsfield API base path and endpoint shapes** used in §3 — written against
  the researched capability facts, not a live API reference; verify at integration time.
- **Decide the exact base aspect ratio default** (§3.3 assumes `3:4` portrait) against final §6.17
  viewport mockups once those exist.
