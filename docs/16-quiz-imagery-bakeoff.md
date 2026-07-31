# 16 — Quiz imagery bake-off: Higgsfield vs OpenAI

**Status:** DECIDED — **OpenAI `gpt_image_2` at 2k / medium**, resolved 2026-07-31.
**Supersedes `docs/15` §5's "Quiz imagery (§6.9) → Higgsfield `soul_2`" row.** Everything else in
`docs/15` stands.

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

## 4. Decision

| Use case | Provider | Confidence |
|---|---|---|
| Quiz imagery (§6.9) | **OpenAI `gpt_image_2`, 2k / medium, text-to-image** | High — decided on measured prompt adherence, not preference |

Existing shipped pairs are **not** regenerated. The three `soul_2` pairs that passed QC
(`texture-01`, `logo-01`, `logo-02`) and the three from the original batch are all internally
consistent, and reshooting them would spend credits to change nothing a user could perceive. New
pairs go to OpenAI. A mixed catalogue is fine: consistency is required *within* a pair, not
across the quiz.

### Higgsfield is now unused across the entire product

Style Studio → OpenAI (§15). Reference/figure generation → OpenAI (§15). Quiz imagery → OpenAI
(this document). **No remaining use case routes to Higgsfield**, so it can be dropped as a vendor
dependency. That is a real simplification and should be taken deliberately rather than left as an
unused integration nobody remembers the status of.

Note also that §15 evaluated `gpt-image-1.5`; the model tested here is **`gpt_image_2`**, a later
generation. §15's Style Studio numbers were measured on the older model and are therefore a floor,
not a ceiling — worth knowing before anyone re-litigates Style Studio.

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
