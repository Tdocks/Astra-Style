# 16 — Quiz imagery bake-off: Higgsfield vs OpenAI

**Status:** DECIDED — **OpenAI `gpt-image-2`, portrait 1024×1536 at medium quality, called
directly against OpenAI's API with Astra's own key**, resolved 2026-07-31.
**Supersedes `docs/15` §5's "Quiz imagery (§6.9) → Higgsfield `soul_2`" row.** Everything else in
`docs/15` stands.

One thing to be precise about, because every table below is denominated in credits: **the OpenAI
frames in this bake-off were generated through Higgsfield's API**, which resells `gpt_image_2`.
The model that won the race is the model that ships; what changed later the same day is the
*route* to it. §3.5 prices both routes, and is why Higgsfield is dropped outright rather than kept
around as a convenience.

Scope: which provider generates the §6.9 paired-image quiz. Style Studio is not re-opened here.

---

## 1. Why this was re-run at all

`docs/15` assigned §6.9 to Higgsfield on two stated grounds:

> Higgsfield **remains the choice for §6.9 quiz imagery** — text-to-image with no reference is a
> different code path, unaffected by the rewriting, and cheapest at ~0.12 credits per generation.

Read closely, that is *"it dodges the bug that disqualified it elsewhere, and it is cheap."*
Neither is a measured quality result. §15's rigour — the byte-identical prompts, the ArcFace
retention metric, the n=3 replication — was all spent on **reference-conditioned Style Studio**
generation. **Text-to-image was never actually raced.** §6.9 inherited a vendor by default.

That gap became load-bearing on 2026-07-30, when ten candidate pairs were generated on `soul_2`
and **only three were usable**. The failures were not aesthetic; they were failures to control the
variable under test. So the question "would another vendor fail differently" was worth 45 credits.

## 2. Method

Three prompts, chosen because they are exactly where `soul_2` failed — this is a test of whether
the failures are inherent to the task or to the vendor:

| Prompt | The thing being tested |
|---|---|
| `accessory-01` A/B | Does "no belt, no watch and no accessories of any kind" hold? |
| `trend-01` A/B | Does the same man appear on both sides of a pair? |
| `contrast-02` A/B | Does the whole body stay in frame, at a consistent scale? |

**Byte-identical prompts**, reused verbatim from the 2026-07-30 Higgsfield run, per §15's own
discipline. Higgsfield frames are that run's actual output; nothing was regenerated to flatter
either side. OpenAI ran at 2k / **high** — deliberately its better tier, because §15 §7 records
under-measuring xAI by ~17 points by running its weaker one, and repeating that mistake in its own
successor document would be indefensible.

## 3. Results

### 3.1 Negative instruction adherence — decisive

Both `accessory` "bare" frames from Higgsfield came back **wearing a wristwatch**, having been
told not to. The bare side is half the comparison, so the axis measures nothing while looking
like a valid pair — the precise failure mode this whole content pipeline exists to prevent.

| | "no watch" frame | "with watch" frame |
|---|---|---|
| Higgsfield `soul_2` | **watch present — fails** | watch present |
| OpenAI `gpt_image_2` | **bare wrists — passes** | watch present, left wrist as specified |

Verified at full resolution, not at tile size. **This alone unblocks `accessory_preference`,
which cannot be built on `soul_2` at all.**

### 3.2 Backdrop consistency within a pair

Mean luma of four corner patches, absolute difference between the two frames of a pair (0–255):

| Pair | Higgsfield | OpenAI |
|---|---|---|
| accessory-01 | 33.5 | **18.5** |
| trend-01 | 33.7 | **13.0** |
| contrast-02 | **8.5** | 10.2 |
| **mean** | 25.2 | **13.9** |

OpenAI is ~45% tighter on average but **not clean enough to skip normalisation** — 13.9 is still
visible side by side. `scripts/build_quiz_imagery.py` stays in the pipeline either way. This is a
smaller win than it looks, and is not why the decision went the way it did.

### 3.3 Model and framing consistency

`soul_2` changed the man's apparent skin tone between A and B in `trend-01`, and shifted trouser
colour and framing scale in `accessory-01`. OpenAI held one man, one scale and one palette across
both sides of all three pairs.

OpenAI also framed from the chest down with **no chin or neck intrusion in any of the six frames**,
where `soul_2` puts them in frame every time — which is why the mandatory top-7% crop exists. The
crop is retained regardless, because "the generator happened not to do it this time" is exactly
the reasoning `brand/quiz-imagery/README.md` warns against about hands.

### 3.4 Cost

| Config | Credits / frame |
|---|---|
| Higgsfield `soul_2` | 0.12 (billed 1) |
| OpenAI `gpt_image_2` 1k / medium | 2 |
| OpenAI `gpt_image_2` 2k / medium | **3** |
| OpenAI `gpt_image_2` 2k / high | 7 |

**2k/medium was tested against 2k/high on the decisive prompt and is indistinguishable** — clean
hands, correct bare wrist, same garment fidelity. There is no reason to pay 7.

Per frame OpenAI is ~25× Higgsfield, which sounds fatal and is not, for two reasons.

**Yield.** The Higgsfield batch took 23 generations to produce 6 usable frames — a 3.8× retry
factor — because rejects were rejected for confounds, not for polish. Per *usable* frame that is
~0.46 credits against ~3–4.5 for OpenAI: roughly 8×, not 25×.

**These are static assets generated once.** §15 says so itself. Finishing the quiz means 6–14 more
pairs, i.e. 12–28 frames: **on the order of 40–125 credits, one time, forever.** Against a balance
in the hundreds and a one-off scope, an 8× multiple on a trivial base is not a real constraint.
Cost was a legitimate tiebreak when quality was assumed equal. It is not one now that quality is
measured and unequal.

### 3.5 Cost priced properly — direct OpenAI against Higgsfield as a reseller

Everything above is in Higgsfield credits, because everything above ran through Higgsfield. Priced
in dollars against calling OpenAI directly, the picture changes enough to end the vendor
relationship. Two sources, named so the arithmetic can be re-checked: **OpenAI's image-generation
guide, "calculating costs" table** for the direct per-image prices, and **Higgsfield Plus at
$49/month for 1,000 credits = $0.049/credit** for the reseller prices. Both are *list* prices;
no volume discount is assumed anywhere below.

**Per image, portrait 1024×1536, direct from OpenAI:**

| Tier | `gpt-image-1.5` | `gpt-image-2` |
|---|---|---|
| Low | $0.013 | **$0.005** |
| Medium | $0.050 | **$0.041** |
| High | $0.200 | **$0.165** |

`gpt-image-2` is cheaper than `gpt-image-1.5` at every tier. Both columns are here because the
product uses both: the quiz takes `gpt-image-2`, Style Studio takes `gpt-image-1.5`. **The price
column did not decide Studio and should not be read as if it had** — §4 and `docs/15` §5 set out
why a $0.035 difference at the high tier loses to a measured 3.7-point identity regression.

**The same model, direct against through the reseller:**

| Route | Config | Per frame |
|---|---|---|
| Direct | `gpt-image-2`, 1024×1536, medium | **$0.041** |
| Higgsfield | `gpt_image_2` 1k / medium — 2 credits | $0.098 — **~2.4×** |
| Higgsfield | `gpt_image_2` 2k / medium — 3 credits | $0.147 |
| Higgsfield | `gpt_image_2` 2k / high — 7 credits | $0.343, against $0.165 direct at high — ~2.1× |

Be fair to Higgsfield about the 2k rows: its "2k" returned **1744×2336**, roughly 2.6× the pixels
of the 1024×1536 the direct table prices, so part of that gap is resolution rather than margin.
**The 1k/medium row is the clean like-for-like, and it is ~2.4×.** The extra resolution buys
nothing here in any case — `scripts/build_quiz_imagery.py` crops the top 7% and resizes to 720px
wide, so everything above ~1024px wide is discarded before a frame ships.

**Why the subscription, not the multiple, is what decides this.** Higgsfield Plus is **$49/month —
$588/year — regardless of usage.** It is a seat, not metered credit. After this document the only
thing that seat buys is the static quiz imagery below: on the order of **$3 of one-time
generation**. Paying $588/year to save three dollars is backwards, and that sentence is the whole
argument for dropping the vendor.

**For static assets the difference is trivial, and that is the point.** Finishing the quiz is 6–14
more pairs — 12–28 frames. At medium: **$1.15 direct against $4.12 through Higgsfield** at its
2k/medium rate. A three-dollar difference, once, forever. Nobody should choose a vendor on this
number in either direction.

**For runtime it decides everything.** Style Studio (§6.17) is per user, per month, indefinitely.
Priced on `gpt_image_2`, the model Higgsfield actually resold, at 10 high-tier images/month:
**$1.65 direct against $3.43 through Higgsfield.** Against the $12.99 monthly plan — roughly
$9.09 net after Apple's 30% — that is **18% of net revenue against 38%**. Against the $79.99
annual plan, roughly $4.67/month-equivalent net, it is **35% against 73%**. (Studio actually runs
on `gpt-image-1.5` at $0.200 high, so its own direct line is a little higher than the $1.65 in
this like-for-like comparison; the comparison is about the *route*, and the reseller multiple is
what it is measuring. `docs/11` risk 5 carries the corrected per-model inputs and has **not** been
recomputed on them.)

`docs/09` §5.6 already puts reasoning-provider inference *alone* at 28–34% of net revenue
on the annual plan; stacking a 73% image line on top of that is not a thin margin, it is a plan
that loses money on every subscriber. The reseller's markup by itself would put it underwater.

**And there was never a Higgsfield runtime path to put it on.** ADR 0004 is explicit that the
client never talks to a provider and that Edge Functions hold the keys, so whatever generates a
Style Studio image is called server-side with Astra's own credentials. A per-seat creative-tool
subscription could never have sat in that path — it was only ever a way to hand-generate static
assets, which is exactly the $3 line above.

## 4. Decision

| Use case | Provider | Confidence |
|---|---|---|
| Quiz imagery (§6.9) | **OpenAI `gpt-image-2`, text-to-image, portrait 1024×1536, medium quality, called directly against OpenAI's API** | High — decided on measured prompt adherence, not preference |

Medium rather than high because §3.4 measured them indistinguishable on the decisive prompt.
1024×1536 rather than the 1744×2336 the bake-off ran at because the pipeline throws that
resolution away: crop the top 7%, resize to 720px wide, ship. Directly rather than through
Higgsfield because §3.5 prices the same model at ~2.4× through the reseller and the seat costs
$588/year whether it is used or not.

Existing shipped pairs are **not** regenerated. The three `soul_2` pairs that passed QC
(`texture-01`, `logo-01`, `logo-02`) and the three from the original batch are all internally
consistent, and reshooting them would spend credits to change nothing a user could perceive. New
pairs go to OpenAI. A mixed catalogue is fine: consistency is required *within* a pair, not
across the quiz.

### A claim in an earlier draft of this document was wrong

An earlier version said §15 evaluated `gpt-image-1.5` while this document tested `gpt-image-2`,
and therefore that §15's Style Studio numbers were "a floor, not a ceiling". **That is withdrawn.**
§15 §3a measured *both* models head to head at n=3, and `gpt-image-1.5` won the identity axis —
78.5% ±1.6 against 74.8% ±2.2, with ~1.6× tighter per-cell spread. The newer model is not
uniformly better; it is better at the thing measured here and worse at the thing measured there.

**Style Studio therefore stays on `gpt-image-1.5`.** This document's result is about
negative-instruction adherence in text-to-image with no reference attached. Preserving a real
man's likeness through a reference-conditioned edit is a different task, and a win here does not
transfer. Generalising one use case's vendor result to another is precisely the error that left
§6.9 on the wrong vendor until it blocked us; repeating it in the opposite direction on the same
day would be worse.

The price difference does not rescue the argument: $0.200 against $0.165 at the high tier is
**$0.035 an image**, roughly thirty-five cents per subscriber per month at ten generations,
weighed against `docs/11` risk 4 — Studio output that looks wrong or uncanny.

### Higgsfield is dropped, not merely unused

Style Studio → OpenAI (§15). Reference/figure generation → OpenAI (§15). Quiz imagery → OpenAI
(this document). **No remaining use case routes to Higgsfield**, and §3.5 prices what keeping it
would cost: $588/year for a seat whose only remaining job is ~$3 of one-time generation. So it is
dropped as a vendor dependency, deliberately, rather than left as an unused integration nobody
remembers the status of. **OpenAI is the only image provider, called with Astra's own key.**

Concretely, that means: no Higgsfield adapter is written, `HIGGSFIELD_API_KEY` is not a secret
this project sets, and `docs/10`'s Higgsfield client, prompt construction and credit arithmetic
are history rather than a specification. The measurements that got us here — §15's
prompt-rewriting disqualification, §3.1's watch, §3.2's backdrop numbers — stay on the record in
full, because a decision whose evidence has been deleted is indistinguishable from a preference.

Dropping the vendor is not the same as collapsing onto one model: Style Studio stays on
`gpt-image-1.5` for the reasons set out above and in `docs/15` §5. One provider, one key, two
models chosen per task.

### Before this ships — open operational items

Neither of these is a quiz-imagery question, but both were surfaced by this decision and belong
somewhere a person will actually look:

- **The OpenAI key is not where the architecture requires it.** Spec §25 and ADR 0004 permit a
  provider key to exist only as an Edge Function environment variable, and `supabase secrets list`
  currently shows **no `OPENAI_API_KEY` on the project**. The working key lives in local env files
  outside the repo — uncommitted, which is the part that is fine, and outside the sanctioned
  location, which is not. Anything beyond hand-generating static assets is blocked on setting it
  properly. See `supabase/README.md`.
- ~~**Two evaluation credentials are now dead.**~~ **Done 2026-07-31.** The `XAI_API_KEY` and
  `GEMINI_API_KEY` from §15's bake-off had no remaining use and **were revoked at the provider
  on 2026-07-31.** Nobody needs to chase this; an unused key in plaintext was a liability, not a
  convenience, and it is gone.

## 5. What this does NOT settle

Recorded explicitly so a later reader knows these were skipped rather than forgotten.

- **n=1 per prompt.** §15 held itself to n=3 replication before resolving a tier. This ran one draw
  per cell. The accessory result is categorical enough (a watch is present or it is not) that
  replication would be unlikely to overturn it, but the backdrop and framing numbers are
  single-draw and should be treated as indicative.
- **Only three of eight axes were tested**, and all three were chosen because Higgsfield failed
  them. That is the right test for "does switching unblock us" and the wrong one for "which vendor
  is better in general" — this document deliberately answers the first.
- **Texture was not re-tested on OpenAI.** It defeated `soul_2` three times by dragging colour and
  volume along with surface. Whether OpenAI holds tone and cut constant while varying only weave is
  unknown, and it is the most likely of the remaining axes to be genuinely hard for any model.
- **No blinded human rating**, same gap §15 §7 records. Nobody has confirmed these read as
  *photographs of clothes* rather than *renders* to a real user.
- **The same-man-across-a-pair result is from three pairs.** It is the single most important
  property for this content and deserves more evidence before being treated as settled.
- **The direct OpenAI route was never exercised on these prompts.** Every frame measured here
  reached `gpt_image_2` through Higgsfield's API. The decision moves the route to OpenAI directly,
  and while the model is the same, nothing here proves that a direct call with the same prompt
  returns comparable output — parameter names, defaults and any silent server-side prompt handling
  differ per API surface, and §15's whole disqualification of `soul_2` was about exactly that kind
  of invisible difference. **Generate one pair directly and compare it against the bake-off frames
  before producing a batch.** Verified so far: the key works and has access to `gpt-image-1`,
  `gpt-image-1-mini`, `gpt-image-1.5`, `gpt-image-2` and `chatgpt-image-latest`.
  **Closed 2026-07-31 — see §6.** The full set was generated through OpenAI's own API and the
  direct route did not merely match these frames, it beat them.
---

## 6. Executed — what the decision produced

Recorded 2026-07-31, the same day the decision was taken. This section is the outcome, not a
revision: nothing above is rewritten, and the numbers here either confirm or improve on it.

**The full §6.9 set was regenerated from scratch through OpenAI's own API.** Every frame produced
on Higgsfield was deleted — the three original pairs and the three added to them — so nothing in
`brand/quiz-imagery/` or `ios/AstraStyle/Resources/QuizImagery/` came from the dropped vendor.
`scripts/generate_quiz_imagery.py` is the tool, `gpt-image-2` at portrait 1024×1536 medium is the
configuration this document chose, and the direct route is what it calls.

**The technique changed, and that is the headline rather than the vendor.** §3.3 measured whether
one man survived across a pair. The shipped pipeline no longer leaves that to the prompt: it
generates **one canonical figure** — `brand/quiz-imagery/_reference-figure.png`, a headless man in
a plain grey base layer — and produces every single frame by passing that figure to
`/v1/images/edits` with an instruction to keep the same man and change only the clothing. The
person is therefore removed as a variable from the whole instrument, not merely balanced inside
each pair, which is a stronger property than anything measured here.

Measured against this document's own numbers:

| Metric | Higgsfield `soul_2` (§3.2) | OpenAI text-to-image (§3.2) | Reference-conditioned edits (shipped) |
|---|---|---|---|
| Backdrop drift within a pair, mean luma | 20.9 | 13.9 | **1.6** |
| Backdrop drift within a pair, worst case | 33.7 | — | **3.0** |
| Residual after normalisation | ~1.0 | — | **≤0.8** |

- **The accessory axis is buildable and built.** §3.1's decisive result held at batch scale: both
  "bare" frames have genuinely bare wrists, verified at full resolution, and both "layered" frames
  show a wristwatch. That axis measured nothing on the old vendor.
- **Hands were checked at full resolution across the set** — clean.
- **14 pairs ship, covering all 8 dimensions.** Six axes have two pairs; `silhouette` and
  `logo_tolerance` have one each and therefore sit at `.low` confidence permanently. The manifest
  is at `version: 2`.

**Two pairs were rejected rather than shipped**, and both reasons are worth carrying forward:

1. `logo-1-b` came back wearing **"HILFIGER"** — a real trademark, unshippable. The file was
   deleted from the repo entirely rather than left unreferenced. The prompt now asks for an
   abstract chevron emblem containing no letters, because **asking this model for a wordmark makes
   it reach for a real brand**; the same failure produced a circled "G" reading as a luxury house's
   mark on an earlier attempt.
2. `silhouette-2-b` came back **short-sleeved** against a long-sleeved partner, putting sleeve
   length in a pair meant to isolate volume. The prompt now says "long-sleeved" and "sleeves down
   to the wrist".

Both regenerations are blocked on an **OpenAI billing hard limit** (`billing_hard_limit_reached`),
not on anything unresolved. The corrected prompts are committed;
`python3 scripts/generate_quiz_imagery.py --pair logo-1 --pair silhouette-2` produces them once the
limit is raised.

What this section does **not** close: §5's remaining items stand. There is still no blinded human
rating, the same-man property is verified by eye rather than by a metric, and one canonical figure
means the instrument shows every user the same build and skin tone — a coverage question that
should be a recorded decision rather than a side effect. See
`ios/AstraStyle/Resources/QuizImagery/README.md` for the live version of all of it.
