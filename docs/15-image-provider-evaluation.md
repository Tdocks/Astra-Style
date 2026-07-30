# 15 — Image provider evaluation

**Status:** measured. Supersedes the vendor decision in `docs/08` §3.5 and the Higgsfield-specific
mechanics in `docs/10`, both of which were written around a capability the chosen vendor does not
have. Those documents are now wrong and must be updated to match this one.

Scope: which provider generates Style Studio's images (spec §6.17 / §13), and separately which
generates the §6.9 quiz imagery. Kyra's text/reasoning tier is **not** in scope and remains
untested.

---

## 1. What was tested, and how

Six synthetic reference faces, controlled for skin tone (three bands), facial hair (three states),
glasses (present/absent) and age (28–50). Synthetic on purpose: testing identity preservation
requires uploading a face to three vendors, and doing that with a real person's photo would trip
the §29 consent gate with the very experiment meant to inform it.

Three outfits, each 4+ garments, built to stress different things — structure (tailored), layer
order (layered-casual), and colour fidelity under a hard constraint (high-contrast).

Every vendor received a **byte-identical prompt** built deterministically from structured garment
data, so the comparison measures the model rather than the phrasing.

**Identity was measured, not eyeballed.** ArcFace cosine similarity between reference face and
output face, reported as *retention*:

```
retained = (similarity − different_person_floor) / (same_photo_ceiling − floor)
```

1.0 means "as similar as the same photograph re-encoded", 0.0 means "no more similar than a
different member of the panel". Normalising per-face matters: each face has its own measurement
ceiling, and a raw score silently penalises the faces the metric reads less reliably.

**The metric was validated before use.** Face recognition models carry documented demographic
bias, so the self-score was computed per reference. Spread across the panel was **0.051** and did
not track skin tone (lowest ceiling was a deep-skinned reference at 0.947, but the second-lowest
was a fair-skinned one at 0.958, and the highest was olive at 0.998). The ruler is even enough
across these six faces for the comparison to stand.

**Garment accuracy was scored blind.** 54 images shuffled to random IDs, mapping withheld until
scoring was complete, then joined. Necessary because the same person ran the generators and held a
prior belief about the outcome.

---

## 2. Results

### Identity retention (primary criterion)

| Reference | OpenAI | Gemini | xAI |
|---|---|---|---|
| fair / clean-shaven | **68%** | 62% | 50% |
| fair / beard + glasses | **71%** | 53% | 44% |
| olive / stubble | **81%** | 68% | 70% |
| deep / glasses | **86%** | 65% | 64% |
| deep / beard | **68%** | 59% | 42% |
| east asian / clean-shaven | **84%** | 58% | 71% |
| **overall** | **76%** | 61% | 57% |

OpenAI wins every row. `gpt-image-2` for the main run; see §3 on tiers.

### Garment accuracy (blind-scored)

| | tailored | layered | high-contrast | overall |
|---|---|---|---|---|
| Gemini | 100% | 100% | 100% | **100%** |
| xAI | 96% | 100% | 100% | 99% |
| OpenAI | 92% | 100% | 96% | 96% |

**The ranking inverts.** Every OpenAI miss was the same failure mode: desaturation toward black —
navy blazer rendered black, forest-green corduroy rendered near-black. That is a characterisable
bias, and plausibly the same conservatism that wins it the identity comparison. It changes less.

### Cut fidelity — the finding that matters most

The high-contrast outfit specified **wide-leg** trousers. Of 18 images, **two** honoured it, both
OpenAI. Gemini 0/6, xAI 0/6.

Colour and garment presence are followed reliably by all three. **Cut is largely ignored by all
three.** This is not a vendor problem; it is the same result across three independent vendors.

**Consequence for `docs/14` (frame-aware fit):** `ClosetItem.fit` stores slim / tailored / regular
/ relaxed / oversized, and the entire `FitRules` table reasons on that axis — the skinny-jeans case
*is* a cut distinction. If Style Studio cannot render slim versus wide, then Kyra's advice ("a
straight leg balances the shoulder line") sits next to a picture that shows the same trousers
either way. The words would be right and the image would quietly contradict them. That is worse
than showing no image.

### Higgsfield — disqualified for Style Studio

`soul_2` **silently rewrites the prompt** when a reference image is attached. All 18 generations
came back as head-and-shoulders portraits in a grey t-shirt: the garment list was discarded
entirely and the identity was frequently lost too. Confirmed unfixable —
`params.enhance_prompt: {requested: false, used: "omitted", reason: "Higgsfield Soul 2.0 does not
support this parameter"}`.

`soul_2` also would not keep a whole body in frame across three attempts at building a fixture
panel, cropping at the neck regardless of instruction.

Higgsfield **remains the choice for §6.9 quiz imagery** — text-to-image with no reference is a
different code path, unaffected by the rewriting, and cheapest at ~0.12 credits per generation.

### Soul ID — rejected without testing, deliberately

Higgsfield's actual identity product trains a Soul on 5–20 photos per user. Rejected on three
grounds, the third being decisive:

1. Twenty photos plus a ~10-minute wait, in an onboarding flow whose §6.6 philosophy is "allow
   *I don't know*" on every field.
2. Souls are **account-scoped, not user-scoped**. Thousands of end users' Souls would live in one
   seat with no isolation, and one account suspension would destroy all of them.
3. A trained Soul **is a persistent derived biometric model of the user**, held indefinitely on a
   third party's infrastructure. Every other option here is stateless. Soul ID is therefore the
   *worst* option for §29 and for right-to-erasure — deleting a trained model is materially harder
   than deleting a file. This is the opposite of what "the proper identity product" implies.

---

## 3. Tier matters more than vendor, and newest is never best

Measured on three references × two outfits per tier:

| tier | retention | range |
|---|---|---|
| `gpt-image-1.5` | **77%** | 71–83 |
| `gpt-image-2` | 73% | 60–88 |
| `gemini-2.5-flash-image` | 72% | 65–79 |
| `grok-imagine-image` | 66% | 57–78 |
| `gemini-3.1-flash-image` | 61% | 49–67 |
| `nano-banana-pro-preview` | 59% | 46–63 |
| `gemini-3-pro-image` | 58% | 49–69 |
| `grok-imagine-image-quality` | 49% | 42–69 |
| `gpt-image-1` | 27% | 15–39 |
| `gpt-image-1-mini` | 13% | **−15**–30 |

Three independent instances of the same pattern:

- `gpt-image-1.5` edges `gpt-image-2`, with a much tighter spread.
- `gemini-2.5-flash-image` beats every newer Gemini image model by 11–14 points.
- `grok-imagine-image` beats `grok-imagine-image-**quality**` by 17 points.

The plausible mechanism: newer and higher-"quality" image models regenerate more aggressively and
optimise for an attractive picture. Faithfulness to an input face rewards conservatism.

`gpt-image-1-mini` produced one cell at **−15%** — the output resembled a *different* panel member
more than the person supplied.

**Methodological error to record:** the main comparison was run on
`grok-imagine-image-quality`, xAI's *worse* tier. xAI's headline 57% understates it by roughly 17
points. The OpenAI conclusion is unaffected; the xAI ranking was measured on the wrong model.

---

## 4. Is 76% good enough?

The standard ArcFace threshold for same-person verification is 0.32 similarity. **All 54 cells
cleared it** — weakest was 0.42, OpenAI's median 0.774. Any face-recognition system would return
"same person" on every output from every vendor.

So 76% does not mean "fails to look like him". It means *comfortably identified as the same person,
with roughly a quarter of the fine facial detail redrawn*. The inferred subjective experience —
untested — is "that's me, but airbrushed": smoother skin, tidier hair, marginally more symmetrical.

**The remaining gap probably does not close by changing vendor.** It is inherent to inferring a
whole person from one photograph. The routes that would close it are multi-reference conditioning
(which is Soul ID, rejected above) or a middle path of two or three photos, which nobody has tested.

---

## 5. Decision

| Use case | Provider | Confidence |
|---|---|---|
| Style Studio (§6.17) | **OpenAI**, `gpt-image-1.5` or `gpt-image-2` | High on vendor, low on tier — 77 vs 73 at n=6 is inside noise |
| Quiz imagery (§6.9) | **Higgsfield** `soul_2`, text-to-image | High |
| Reference / figure generation | **OpenAI** | High — only vendor that keeps a body in frame |
| Kyra reasoning (§11) | **untested** | — |

Style Studio's prompt must carry an explicit colour-saturation guard ("navy, not black") to
counter OpenAI's one measured weakness.

---

## 6. Weaknesses of this evaluation

Stated plainly, because the conclusions above are only as good as these admit.

1. **Every cell is n=1.** No variance estimate anywhere. The identity gaps are large relative to
   plausible per-draw noise; the tier gaps at the top (77 vs 73) are not.
2. **Body-type fidelity was not measured at all.** The chosen metric was the wrong instrument:
   pose landmarks track the *skeletal* hip joint, which barely moves with soft tissue, so
   shoulder:hip is near-constant across humans. Silhouette width would see build but is confounded
   by clothing — an overcoat legitimately widens the outline.
3. **The body reference panel failed.** `gpt-image-1.5` regresses hard toward an average male body
   regardless of how specifically a build is described; only "compact" and "tall/lean" came out
   distinct. Worth noting as its own product finding: if Style Studio ever renders a *figure*
   rather than a photo, expect every figure to look average, and the frame axes in `docs/14` will
   not survive the generator.
4. **No prompt tuning per vendor.** One phrasing for all three is good for comparability and bad
   for fairness — it partly measures which model likes that phrasing.
5. **"Best looking" is unmeasured**, and it is the criterion nominated as decisive. No blinded
   human rating has happened.
6. **A single judge scored the subjective half**, and that judge was confidently wrong once in this
   evaluation: the first eyeball pass claimed OpenAI drifted on the two deepest skin tones and xAI
   held them better. Those two rows are OpenAI's *largest* margins. The error came from anchoring
   on salient attributes — beard present, glasses present, skin tone right — at thumbnail size,
   where facial geometry is invisible. This is the case for measuring rather than looking.
7. **The cut-fidelity finding rests on one instruction** (wide-leg). It is consistent across three
   vendors, which is what makes it credible, but it deserves a purpose-built test before anything
   is redesigned around it.
8. **The panel is six synthetic men**, one pose, one lighting setup, a narrow age band, no
   variation in body type, and no women. Fine for a vendor comparison; not a coverage claim.
9. **Cost at scale is not modelled.** Notably xAI exposes no seed control, so there is no
   deterministic cache key and every regeneration pays full price — a multiplier on §16's tier
   quota economics rather than a footnote.
10. **`docs/08` §3.5 and `docs/10` still name Higgsfield** for Style Studio and have not been
    updated.
11. **Evaluation API keys were live in an ephemeral container** and should be rotated regardless of
    outcome.
