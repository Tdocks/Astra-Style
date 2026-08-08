# 05 — Wardrobe Graph: Algorithmic Specification

**Status:** Implementation-ready
**Depends on:** `00-master-spec.md` §10 (Wardrobe Graph), §6.6 (fit profile), §6.19 (product decision page), §9 (data model), §22 (testing requirements)
**Owner surface:** Supabase Edge Functions (`/outfits/generate`, `/outfits/rank`, `/products/evaluate`), plus a pure-function scoring core shared by both so iOS can run a cached/offline approximation.

All formulas here are deterministic and side-effect-free given their inputs, specifically so they can be unit tested without network, model providers, or a database.

---

## 0. Amendments made when this document was implemented (2026-08-07)

Implementing §1–§4 as `supabase/functions/_shared/scoring/` surfaced six places
where this document could not be followed as written. All six are corrected in
the sections below; this section is the record of **why**, so nobody
"restores" an earlier value later. The implementation is the arbiter for the
first two and the shipped schema is the arbiter for the rest.

**1. §1.3's neutral bands were written in HSL hue and applied in CIE hue.**
The navy band was `h° 240–270`. Five real navies pushed through §1.2's own
pipeline land at **274.4–289.2**; not one fell inside. Olive-drab's band capped
chroma at 22 and real olive-drabs measure **17.7–30.6**. Both bands — the only
two the table exists for, since black/grey/white are already caught by the
`C* ≤ 12` rule — classified their own subject as chromatic. The cause is the
trap §1.1 warns about: 240° is where blue sits in HSL, whose hue is an artifact
of the RGB cube; in CIE LCh blue is near 280–300°. Bands replaced with measured
envelopes and pinned from both sides in `colorSpace_test.ts`.

**2. §2.2's worked example changes with it — 0.91 becomes 0.97.** Its olive
polo was classified chromatic *because* the old band excluded it. Under the
corrected band it is a neutral, all three pairs take the neutral route, and two
clear the ≥30 lightness-contrast bonus. This is the better answer on the
merits: olive is a canonical menswear neutral, and an engine that scored an
olive polo as a chromatic element competing with stone trousers would be
marking down one of the easiest outfits a man owns.

**3. §2.5's warmth scale is 0–100, not 0–10.** `closet_items.warmth_score` is
`smallint check (between 0 and 100)`. Read on the 0–10 scale, an overcoat at 85
maps to an ideal temperature of −267°C and every winter garment scores zero
against every forecast on earth. `water_resistance_score` is the same column
type, so §2.5's "< 3" rain threshold becomes "< 30".

**4. §2.9 excludes more than dirty items.** `availability_state` has seven
values, not two: it also carries `in_alteration`, `packed_for_travel`,
`lent_out` and `lost`. A jacket at the tailor, in a suitcase in another city,
on a friend's floor or gone is exactly as impossible to put on as a dirty
shirt. The hard filter excludes all of them.

**5. §1.5's pattern rule cannot run — there is no `pattern_scale` column.**
The whole rule turns on scale separation. The penalty is skipped and *reported*
rather than run against a guessed scale; inventing the one fact a rule reads is
worse than not running the rule.

**6. §2.8 has no item-level input — `occasion_tags` exists only on `outfits`.**
Item-level occasion relevance returns the section's own unconstrained-request
default and names the missing column.

Two smaller notes. `clothing_category` has `watch` and `fragrance`, which
postdate §2.1's role table: `watch` folds into `accessory`, and `fragrance` is
excluded from scoring entirely — it has no colour, silhouette or formality any
formula here can read, and a scent cannot clash with trousers. And §2.3's third
worked pair score is printed as 0.417 where `(28/40)^1.5` gives 0.41434; the
document rounds `0.58566` to `0.583`.

A seventh surfaced when §5 was implemented (2026-08-08). The seed table is the
arbiter for this one:

**7. §5.1's closed form never passed through its own seed table.** The seeds
say n=5→3, n=15→12, n=40→35, n=80→60; `3 + 9.2 × ln(n/5 + 1)` evaluates to
**9.38, 15.75, 23.2, 29.1** at those same four points. No curve of that family
can fit them: from n=5→40 the seeds grow *superlinearly* (3× the items buys 4×
the versatility, as raw per-item combinations do — they grow ~(n/3)²), and a
concave log cannot, so "interpolated via" was never true of these seeds. The
seeds are the operative values — §5.1's own prose re-asserts one ("half of the
n=15 expectation of 12") and §5.10's versatility column only reproduces
against them — and the formula fails at both ends of the range: at n=5 it
demands 9.38 qualifying outfits per item where the best possible 2/2/1 split
structurally caps the per-item mean at **2.4** (an expectation no closet can
meet, contradicting §5.1's own "what's structurally achievable" definition),
and at n=80 its target of 29 is trivially cleared by any large closet (~710
raw combinations per item), pegging a 25%-weight component at 1.0 for volume
alone — the exact failure §5.1's normalization exists to prevent, and the
§5.8/master-spec failure mode of volume buying score. The formula looks like
an unrefitted earlier draft: without the `+ 1`, `3 + 9.2 × ln(n/5)` hits
n=5→3 exactly and lands 13.1 against the n=15 seed of 12 — a plausible fit to
a two-seed draft that predates the n=40/80 seeds and the "+1" corruption.
§5.1 now interpolates the seeds piecewise-linearly (0 below n=5; extended past
n=80 at the last segment's slope so volume never saturates the component) and
drops "log-shaped". Pinned from both sides in `wardrobeScore_test.ts`.

Three more surfaced in the same pass over §5, and were left standing at the
time because each needed a decision rather than a fix. They are decided now.

**8. §5.2's `0.4 ×` coefficient caps fit confidence at 0.76.** Printed as
`0.6 + 0.4 × feedbackAdjustment` with `feedbackAdjustment ∈ {+0.4, 0, −0.5}`,
the component's whole reachable range is **[0.4, 0.76]** — a user who tells
Astra that every garment he owns fits him lands at 0.76 out of 1.0, and no
user can ever reach the top of a component named "fit confidence". Three
things say the coefficient is the corruption and not the ±values. `0.6 + 0.4`
is exactly `1.0`, so removing it makes the best case land precisely on the
ceiling — designed, not coincidental. §5.2 wraps the expression in
`clamp(·, 0, 1)`, a clamp that under the printed formula is unreachable in
both directions; authors do not clamp expressions they believe are already
bounded, and without the coefficient it does real work (−0.5 takes the value
to 0.1, and §4.3's body multiplier can push it further). And fit confidence
would otherwise be the only one of §5's seven components that cannot reach
1.0, costing every user 3.6 points of a 100-point score for no stated reason.
The adjustment now applies directly: **1.0 / 0.6 / 0.1**. The asymmetry is the
doc's own and is the right way round — one "this doesn't fit" is stronger
evidence than one "I like this".

**9. §5.4 normalizes entropy by the wrong denominator, and scores a two-colour
wardrobe at 0.** `normalizedEntropy = ShannonEntropy / log2(numNonEmptyClusters)`
divides by the number of clusters the wardrobe *occupies*, which measures how
evenly its items are spread across the buckets they already sit in — not how
few buckets it uses. A wardrobe split evenly between exactly two hue families
gives entropy 1.0 over log2(2) = 1.0, so **cohesion 0**: the bottom of the
scale, for the palette §5.4's own prose calls high-scoring ("a wardrobe
concentrated in 2–4 hue families plus neutrals scores high"). Every evenly
spread wardrobe scores 0 however few families it spans, and a single family
divides by log2(1) = 0. The denominator is now `log2(13)` — the maximum
possible entropy over the full cluster space of 12 hue bins plus neutral — so
the ratio answers "how much of the available spread does this wardrobe use",
which is what concentration means. One family → 1.0; two evenly → 0.73; a
realistic capsule (60% neutral, two chromatic families) → 0.63; all thirteen
evenly → 0.0. The `numNonEmptyClusters ≤ 1` special case disappears with it,
since a single-outcome distribution has entropy 0 and now falls out of the
same arithmetic.

**10. §5.6's `damaged` rung had no value to land on.** The scale is
`excellent=1.0, good=0.8, fair=0.5, worn=0.25, damaged=0.0`; the shipped
`condition` enum was `new_with_tags, like_new, good, fair, worn`. So the 0.0
rung was unreachable and a garment with a hole in it could not score below
0.25 — a wardrobe of ruined clothes and a wardrobe of well-loved ones sat four
points apart on a 100-point score. This one was not only a scoring gap: the
vision provider's vocabulary has always included `damaged`, and
`closet/mapper.ts` mapped it down to `worn` on the way in, so a correct reading
of a ruined garment arrived in the closet as a wrong one. Unlike amendments
3–6, the arbiter here is **the document, not the schema** — the schema was
simply missing a value the document specifies, so
`20260808120000_condition_damaged.sql` adds it rather than the document
conceding. `damaged` is deliberately not folded into
`availability_state.unavailable`: availability answers "can this be worn right
now" and every other value in it is temporary or locational, while condition is
a property of the garment that persists across all of them.

Amendments 8 and 9 were invisible to CI because nothing tested either
component's arithmetic — `wardrobeScore_test.ts` checked that every component
was *reported*, not what any of them computed. Four regression tests now fail
against the old behaviour and pass against the new; `check_schema_drift.py`
gained the ability to read `alter type ... add value`, without which amendment
10 would have made it report the correct Swift case as drift.

---

## 1. Color Space and Perceptual Color Model

### 1.1 Why not RGB

sRGB is a device-oriented encoding, not a perceptual one. Euclidean distance in RGB does not track perceived color difference:

- Equal RGB steps in the green region produce almost no perceived change, while the same step size in the blue region produces a large perceived change. A polo that is RGB-distance 40 from navy trousers can look more harmonious than a shirt that is RGB-distance 15 from the same trousers, depending on which axis the distance is in.
- RGB has no native concept of *hue*, *lightness*, and *chroma* as separable, perceptually meaningful axes. Menswear harmony rules ("analogous," "complementary," "monochrome") are defined in terms of hue and value relationships, which do not exist as orthogonal, uniform axes in RGB. Deriving them via HSL is not a fix — HSL's "hue" is a geometric artifact of the RGB cube, not a perceptual hue; two HSL-adjacent colors can differ in perceived hue by more than two HSL-distant colors do.

### 1.2 Chosen space: CIE LCh (LAB cylindrical)

Pipeline: `sRGB → linear RGB → CIE XYZ (D65) → CIE L*a*b* → LCh(L*, C*, h°)`.

- **L\*** (0–100): perceptual lightness.
- **C\*** (0–~150 in practice for textiles): chroma/saturation.
- **h°** (0–360): hue angle.

LCh is used instead of raw LAB because harmony rules are naturally expressed as operations on the hue angle (`h°`) and its circular distance, which LAB's Cartesian `a*/b*` does not expose directly.

Color distance (ΔE) uses **CIE76** (Euclidean distance in LAB) for the MVP:

```
ΔE = sqrt((L1-L2)² + (a1-a2)² + (b1-b2)²)
```

**Judgment call:** CIEDE2000 is the more perceptually accurate metric (it corrects for known LAB non-uniformities in the blue and low-chroma regions), but it is ~10x more code for a correction that matters most at ΔE < 2, well below the granularity this scorer needs (garment colors are extracted from photos with their own noise floor). CIE76 is specified for MVP; CIEDE2000 is a drop-in replacement behind the same `colorDistance()` function if photo-derived color accuracy later justifies it.

### 1.3 Neutral classification

An item's primary color is classified **functional-neutral** if either:

- `C* ≤ 12` (low saturation, regardless of hue), OR
- its LCh falls within a curated neutral band (handles navy and olive-drab, which have `C*` in the 15–25 range but function as neutrals in menswear pairing):

| Neutral | L* range | C* range | h° range |
|---|---|---|---|
| Black | 0–20 | 0–10 | any |
| Charcoal | 20–35 | 0–12 | any |
| Gray | 35–75 | 0–10 | any |
| White | 90–100 | 0–8 | any |
| Stone / Bone / Cream | 75–92 | 5–20 | 70–100 |
| Navy | 8–32 | 12–30 | 270–295 |
| Olive-drab | 28–50 | 12–32 | 100–120 |
| Tan / Camel | 60–80 | 15–33 | 60–100 |

**Corrected 2026-08-07 — see §0 amendment 1.** The bottom four rows were
originally `stone 70–95°`, `navy 240–270°`, `olive-drab C* 10–22`, `tan 60–80°`,
and in that form the navy and olive-drab bands matched nothing at all. The
values above are measured envelopes, not reasoned ones: real garment sRGB pushed
through §1.2's pipeline and widened to what came out.

**Chroma, not hue, is what separates a neutral from its saturated twin.** Cobalt
measures h° 291 — squarely between two of the navies used to fit that band. What
makes navy a neutral is that its saturation has been taken out: navy `C* 15–28`,
cobalt `C* 63`. Every band above therefore leans on its chroma ceiling to do the
discriminating, and widening one of those ceilings is the change most likely to
start calling a royal-blue shirt a neutral. The nearest miss in the whole
vocabulary is moss at `C* 35.2`, clearing olive-drab's ceiling by three points.

~~Every closet item stores `primary_color_lch` and `is_functional_neutral`
(precomputed at analysis time, not recomputed per scoring call).~~

**Neither column exists, and adding them would have shipped the engine inert.**
`closet_items.primary_color` is `text` — the word "olive" — because that is what
a vision provider returns and what the §6.10 palette is written in. Migrating to
precomputed columns would leave every existing row null, making colour (the
heaviest component at 0.25) a flat 0.6 prior for every current user's entire
closet.

So the words resolve to LCh at scoring time, through
`_shared/scoring/colorVocabulary.ts` — the server's copy of the 58-word
vocabulary iOS already uses to draw Style DNA palette swatches, held in sync by
`scripts/check_color_vocabulary.py`. A precomputed column, when it arrives,
becomes a cache in front of that function rather than a replacement for it: the
words will still be what the providers speak.

### 1.4 Harmony rules

For a chromatic-chromatic pair (neither is functional-neutral), compute circular hue distance:

```
ΔH = min(|h1 - h2|, 360 - |h1 - h2|)   // 0–180
```

| Zone | ΔH range | Relationship | Base score |
|---|---|---|---|
| Monochrome | 0°–15° | Same hue family | 0.95 if `|L1-L2| ≥ 20` or `|C1-C2| ≥ 15` (value/chroma separation present), else 0.55 (flat, "matchy," reads accidental) |
| Analogous | 15°–60° | Adjacent hues | `0.95 - 0.15 × (ΔH-15)/45` → ranges 0.95→0.80 |
| Discordant | 60°–150° | Neither analogous nor complementary — the classic "clash" zone | `0.55 - 0.20 × min(ΔH-60, 150-ΔH)/45` → floor 0.35 at ΔH≈105° (worst case) |
| Complementary | 150°–180° | Opposite hues | `0.60 + 0.30 × (1 - ΔC_norm)` where `ΔC_norm = |C1-C2| / 100`, clamped [0,1] — rewards one muted + one saturated ("pop of color"), penalizes two fully-saturated complements clashing |

For a neutral-chromatic pair: base score **0.90**. Neutrals anchor any hue; the only adjustment is a small penalty (−0.05) if the chromatic item's `C* > 55` (very saturated colors still read slightly "loud" against a neutral, e.g., pairing a neutral with a highlighter-saturated item, vs. a muted chromatic).

For a neutral-neutral pair: base score **0.95**, with +0.03 bonus if `|L1-L2| ≥ 30` (visible value contrast, e.g., charcoal trousers + white shirt) since undifferentiated neutral-on-neutral (charcoal-on-charcoal, no contrast) reads flat rather than intentional. Capped at 0.98.

### 1.5 Pattern interaction

Each item carries `pattern: solid | stripe | check | herringbone | print | texture-only` and, when non-solid, `pattern_scale: micro | small | medium | large` (garment-relative repeat size, set at analysis time from the CV pipeline's pattern-cue detector, §12).

- **Solid + anything:** no penalty.
- **Pattern + pattern:** apply a multiplicative penalty to the pair's color harmony score:
  - Same or adjacent scale (`|scaleRank1 - scaleRank2| ≤ 1`, where micro=1..large=4): `× 0.55` — two patterns of similar visual weight compete rather than layer.
  - Scale separated by ≥ 2 ranks (e.g., micro houndstooth shirt + large windowpane jacket): `× 0.85` if the patterns share a hue family (ΔH ≤ 30° between their dominant colors), else `× 0.70`. This is the "pattern mixing" rule real stylists use: scale separation plus a shared color thread is what makes pattern-on-pattern read intentional instead of busy.
- The penalty applies **once per pair**, computed on the raw harmony base score before it enters the weighted outfit aggregate (§2.1).

---

## 2. Compatibility Scoring (§10, weighted formula)

The master spec defines eight weighted components summing to 1.0. Compatibility is computed **pairwise** between two items (used live in the outfit builder's compatibility meter, §6.13) and **outfit-wide** (used for ranking full outfit candidates, §5.4) as the pair-weighted aggregate defined in §2.1 below. Every subscore is normalized to `[0,1]`; the final score is `round(100 × Σ weight_i × subscore_i)`.

### 2.1 Outfit-wide aggregation of pairwise subscores

Not every item pair matters equally. Define role-pair weights used to aggregate any pairwise component (color, formality, silhouette) into an outfit-level subscore:

| Pair | Weight |
|---|---|
| top–bottom | 0.35 |
| top–shoes | 0.20 |
| bottom–shoes | 0.20 |
| top–outerwear | 0.10 (0 if no outerwear in outfit) |
| outerwear–bottom | 0.05 |
| any item–accessory | 0.05 per accessory, capped at 0.10 total |

Weights present in the outfit are renormalized to sum to 1.0 (e.g., an outfit with no outerwear and no accessories renormalizes top–bottom/top–shoes/bottom–shoes from 0.75 to 1.0 by dividing each by 0.75).

### 2.2 Color compatibility — weight 0.25

**Inputs:** `primary_color_lch`, `secondary_colors_lch[]`, `pattern`, `pattern_scale` for each item in a pair.

**Computation:**
1. Compute primary-primary harmony score per §1.4/§1.5.
2. If both items have secondary colors, compute the best-matching secondary-primary cross pair and blend at 20% weight: `finalPairScore = 0.8 × primaryScore + 0.2 × bestSecondaryScore`.
3. Aggregate pairs per §2.1.

**Edge cases:**
- Missing/unanalyzed color (`primary_color_lch = null`): subscore defaults to `0.6` (neutral prior — do not let a data gap tank or inflate the score) and the item is flagged `low_confidence_color` so the UI can show a "verify color" affordance rather than silently trusting a guess.
- Pure white/black/gray items always classify as neutral regardless of the curated band table (fast path).

**Worked example — olive knit polo + stone trousers + white sneakers** (the spec's canonical outfit, §2):

| Item | Approx sRGB | L* | a* | b* | C* | h° | Classification |
|---|---|---|---|---|---|---|---|
| Olive knit polo | (110,110,60) | 45 | −8 | 30 | 31 | 105° | Chromatic (olive-drab band edge; classified chromatic here since C*=31 > band's 22 upper bound) |
| Stone trousers | (200,190,165) | 77 | 1 | 14 | 14 | 86° | Neutral (`C* ≤ 12`? no — but falls in Stone band: L*77∈[75,92], C*14∈[5,18], h°86∈[70,95] → **neutral**) |
| White sneakers | (245,243,238) | 96 | 0 | 1 | 1 | — | Neutral (`C* ≤ 12`) |

**Recomputed 2026-08-07 — see §0 amendments 1 and 2.** The table above classified
the polo chromatic on the strength of `C* = 31` exceeding the old olive-drab
band's ceiling of 22. That ceiling excluded every real olive-drab garment and has
been corrected to 32, so the polo — measured at `C* 28.9` through §1.2's
pipeline — is a **neutral**, and all three pairs take the neutral–neutral route:

- Polo (L\* 45) – Trousers (L\* 77): neutral–neutral, `|ΔL| = 32 ≥ 30` → 0.95 + 0.03 = **0.98**
- Polo (L\* 45) – Shoes (L\* 96): neutral–neutral, `|ΔL| = 51 ≥ 30` → 0.95 + 0.03 = **0.98**
- Trousers (L\* 77) – Shoes (L\* 96): neutral–neutral, `|ΔL| = 19 < 30`, no bonus → **0.95**

Outfit color subscore = `0.35×0.98 + 0.20×0.98 + 0.20×0.95`, renormalized over the
0.75 of weight actually present → `(0.343+0.196+0.190)/0.75 = 0.972`.

**Color subscore = 0.97**, contributing `0.25 × 0.97 = 0.243` to the final
compatibility score. The old figures were 0.91 and 0.228.

That the score went *up* is the correct outcome, not a convenient one. Olive is
a canonical menswear neutral — it anchors a hue the way navy and khaki do, which
is precisely why §1.3 has a band for it — and three neutrals with real value
separation is about as safe as an outfit gets. An engine that scored this
combination at 0.91 was marking down one of the easiest outfits a man owns.

### 2.3 Formality alignment — weight 0.20

See §3 for the formality scale itself. Pairwise subscore between two items:

```
score = max(0, 1 - (Δf / 40)^1.5)
```

where `Δf = |formality_i - formality_j|` on the 0–100 scale. The exponent super-linearizes the penalty: a 15-point gap (0.95 score) is barely felt, a 40-point gap zeroes out, matching the styling heuristic that small formality gaps read as texture/personality while large gaps read as a mistake (dress shoes with gym shorts).

**Edge case:** if either item's `formality_score` is null (not yet classified), fall back to a category-level default formality (e.g., `top → 45`, `outerwear → 50`) and flag `low_confidence_formality`.

**Worked example** (same outfit, using §3 anchors: polo=40, tailored chinos=50, casual leather sneaker=22):
- Polo–Trousers: `Δf=10` → `1-(10/40)^1.5=1-0.125=0.875`
- Polo–Shoes: `Δf=18` → `1-(18/40)^1.5=1-0.302=0.698`
- Trousers–Shoes: `Δf=28` → `1-(28/40)^1.5=1-0.583=0.417`

Aggregate: `(0.35×0.875 + 0.20×0.698 + 0.20×0.417)/0.75 = (0.306+0.140+0.083)/0.75 = 0.706`

**Formality subscore = 0.71** — correctly reflects that the sneakers are meaningfully more casual than the trousers, which is exactly why this outfit reads "smart casual" rather than uniformly one register; it is not a flaw, but it is why this component alone won't return 0.9+.

### 2.4 Silhouette compatibility — weight 0.15

Defined fully in §4.

### 2.5 Season/weather suitability — weight 0.10

**Inputs:** item `seasonality jsonb` (subset of `{spring, summer, fall, winter}`), `warmth_score` (**0–100**), `water_resistance_score` (**0–100**), target context: current or forecast temperature band and precipitation probability (from `get_weather`).

**Scale corrected 2026-08-07 — see §0 amendment 3.** Both columns are
`smallint check (between 0 and 100)`. This section originally stated them as
0–10, and read that way an overcoat at `warmth_score` 85 maps to an ideal
temperature of −267°C, so every winter garment scores zero against every
forecast on earth. The mapping endpoints below are unchanged in meaning:
`warmth 0 → 30°C`, `warmth 100 → −5°C`. The rain threshold is `< 30`, not `< 3`.

**Computation (per item, then averaged across outfit items with equal weight):**
```
tempFit = 1 - clamp(|itemIdealTempC - targetTempC| / 20, 0, 1)
```
`itemIdealTempC` is derived from `warmth_score` via a fixed mapping table (`warmth 0 → 30°C ideal`, `warmth 10 → −5°C ideal`, linear between). If precipitation probability > 40% and `water_resistance_score < 3` for an outerwear/shoe item, apply a flat `× 0.6` penalty to that item's tempFit.

**Outfit subscore** = mean of per-item `tempFit` (not pairwise — this is a context-fit, not an item-pairing, so it aggregates by simple mean across all included items, unweighted by role).

**Edge case:** no weather available → subscore defaults to `0.75` (mild positive prior, not a penalty for something the user didn't cause) and the outfit card must omit weather-suitability language (see `06-kyra-orchestration.md` §6, "weather unavailable").

### 2.6 User preference — weight 0.10

**Inputs:** `style_profiles.preferred_colors/avoided_colors/preferred_fit/formality_preference`, plus implicit signal from `style_feedback` (like/dislike embeddings on similar items, cosine similarity ≥ 0.85 to the item in question).

**Computation:**
```
explicitScore =
  0.4 (if item's primary color ∈ avoided_colors → hard penalty, override to 0.1 regardless of other terms)
  + 0.3 × (1 if item.fit == preferred_fit else 0.6)
  + 0.3 × (1 - |item.formality_score - formality_preference_center| / 100)

implicitScore = weighted average of feedback.signal on embedding-similar items,
  like=1.0, dislike=0.0, wore+rating≥4=0.9, wore+rating≤2=0.2, skipped=0.35,
  weighted by recency decay: weight = 0.5^(days_since / 90)

finalScore = 0.6 × explicitScore + 0.4 × implicitScore   (implicit omitted, weight redistributed to explicit, if fewer than 3 relevant feedback signals exist)
```

This is computed **per item** and averaged across the outfit's items (unweighted mean), since preference is about the user's relationship to each garment, not a pairing.

**Edge case (cold start):** no feedback history and no explicit avoided/preferred data → subscore defaults to `0.7`. This is intentionally *not* 0.5 or 1.0: it should not drag a new user's outfit scores down (0.5 would look like the app "doesn't trust" a brand-new closet) nor claim confident personalization it doesn't have yet (1.0 would be a lie the first time it's wrong).

### 2.7 Historical co-wear / feedback — weight 0.10

**Inputs:** count of times these two specific items (or, if never worn together, their category pair) appear together in `outfit_wears` with `rating ≥ 3`, vs. total co-occurrences.

**Computation — Bayesian-smoothed positive rate:**
```
score = (positiveCoWears + prior_alpha) / (totalCoWears + prior_alpha + prior_beta)
```
`prior_alpha = 2, prior_beta = 1` — a mild optimistic prior (an untested pair starts at `2/3 = 0.667`, not 0.5), because absence of negative history is not evidence of a bad pairing, and we don't want new items to be structurally disadvantaged against items with a long wear history.

If these two *specific* items have never co-occurred, fall back to the **category-pair prior**: same formula computed over all `(category_i, category_j)` co-wears across the user's whole history (e.g., all top-bottom co-wears), which converges toward the user's general pairing taste even for a brand-new item.

Aggregated across the outfit via §2.1 pair weights.

### 2.8 Occasion relevance — weight 0.05

**Inputs:** outfit/item `occasion_tags jsonb`, target `occasion.dress_code` (from the request or an `occasions` row).

**Computation:** exact tag match = 1.0; adjacent-occasion match via a fixed adjacency table (e.g., `business-casual ↔ business-formal = 0.6`, `smart-casual ↔ date-night = 0.7`, `athletic ↔ everyday-casual = 0.5`, all non-adjacent unlisted pairs = 0.2) = adjacency value; no target occasion supplied (general "what should I wear" request) = 0.8 flat (don't penalize for an unconstrained request).

### 2.9 Availability/laundry — weight 0.05

**Inputs:** `availability_state`, `laundry_state`.

**Computation:** this is the one component that is a **hard filter before it is a score** — items with `laundry_state ∈ {laundry, unavailable}` are excluded from candidate generation entirely (§6 unlock-count generation, §5.4 outfit generation), not merely down-weighted, because recommending an outfit containing a dirty shirt is a product failure, not a low-quality match. For items that do pass the filter (`clean` or `wornOnce`), the subscore is `clean = 1.0`, `wornOnce = 0.75` (mild preference for fresher rotation, not a hard rule).

---

## 3. Formality Scale

A 0–100 scale, anchored every 10 points per category so the CV classifier (§12) and human reviewers share a rubric. These anchors are seed data in an admin-editable table (§28), not hardcoded constants, but the values below are the shipped defaults.

| Score | Tops | Bottoms | Outerwear | Shoes |
|---|---|---|---|---|
| 0 | Graphic tee / tank top | Athletic shorts / swim trunks | Zip hoodie (graphic) | Slides / flip-flops |
| 10 | Plain crewneck tee | Gym joggers | Athletic zip-up | Running sneakers |
| 20 | Heavyweight tee / Henley | Distressed denim | Casual bomber | Casual canvas/leather sneaker |
| 30 | Casual flannel, worn open | Dark-wash straight jeans | Denim jacket | Minimalist leather sneaker |
| 40 | Knit polo | Relaxed chino / chino short | Field / waxed-cotton jacket | Suede desert boot / chukka |
| 50 | Casual button-down (untucked) | Tailored chino | Unstructured cotton/linen blazer | Penny loafer (unlined) |
| 60 | Fitted oxford (tucked) / fine-gauge sweater | Wool-blend dress trouser (no jacket) | Structured sport coat (unmatched) | Leather derby |
| 70 | Dress shirt, no tie | Suit-separate trouser | Business overcoat (wool) | Cap-toe oxford |
| 80 | Dress shirt + tie | Matched suit trouser | Matched suit jacket | Black formal oxford |
| 90 | Dress shirt + tie + waistcoat | Tuxedo trouser (satin stripe) | Tuxedo jacket | Patent leather formal oxford |
| 100 | Wing-collar formal shirt | White-tie trouser | Tailcoat | Formal opera pump |

Intermediate items are interpolated by the classifier's confidence-weighted nearest anchors, not free-form guessing — the model prompt (`06-kyra-orchestration.md` is conversational; the CV classification prompt, owned by `08-provider-abstraction.md` §2, is instructed to output the two nearest anchor labels and a blend fraction, e.g., `"between knit polo (40) and casual button-down (50), 0.3"` → `43`).

### 3.1 Outfit-level formality aggregation

**Not a mean.** A single item far outside the outfit's formality register damages the outfit more than a single well-matched item helps it — a rule from real styling: "the outfit reads as casual as its most casual visible element, tempered by proportion." Formalized:

```
1. Compute weighted mean M = Σ(weight_i × formality_i) / Σ(weight_i)
   weights: top=1.0, bottom=1.0, shoes=1.0, outerwear=0.9, accessory=0.4

2. deviation = M - min(formality_i for visible, non-accessory items)

3. if deviation > 10:
     penalty = 0.5 × deviation
   else:
     penalty = 0

4. outfit_formality = clamp(M - penalty, 0, 100)
```

The `deviation > 10` gate means minor variation (a 40 and a 50 in the same outfit) is not penalized at all — real outfits mix registers slightly by design (texture, casualization) — while a genuine outlier (a 22 shoe against a 50/40 top/bottom) is.

**Worked example** (olive polo=40, stone trousers=50, white sneakers=22, no outerwear):
```
M = (40+50+22)/3 = 37.33
min = 22, deviation = 37.33-22 = 15.33 > 10 → penalty = 0.5 × 15.33 = 7.67
outfit_formality = 37.33 - 7.67 = 29.66 → 30
```

An outfit_formality of **30** ("smart casual," per the anchors) matches the spec's own framing of this outfit as one that "moves cleanly from work to dinner" — coherent, casual-leaning, not sloppy.

---

## 4. Silhouette Compatibility

**Inputs:** `fit ∈ {slim, tailored, regular, relaxed, oversized}` per item, plus `body_profiles.fit_notes` (e.g., `broad_chest`, `short_torso`, `long_legs`, `large_thighs`).

### 4.1 Fit-pairing base table

Assign `fitRank`: slim=1, tailored=2, regular=3, relaxed=4, oversized=5. For a pair, `d = fitRank(itemA) - fitRank(itemB)`, `|d|` distance:

| \|d\| | Base score | Reading |
|---|---|---|
| 0 | 0.90 (slim/tailored), 0.85 (regular), 0.65 (relaxed), 0.50 (oversized) | Uniform silhouette — coherent for tighter fits, reads shapeless/sloppy without a fitted anchor for relaxed/oversized-on-both |
| 1 | 0.90 | Natural gradation (e.g., tailored top + regular bottom) |
| 2 | 0.75 | Still coherent, more visible contrast |
| 3 | 0.60 | Contrast zone — see directional adjustment below |
| 4 | 0.45 | Extreme contrast (slim + oversized) — see directional adjustment |

### 4.2 Directional adjustment

Menswear silhouette rules are not symmetric: a looser top over a tighter bottom reads as a deliberate proportion play; a looser bottom under a tighter top reads as ill-fitting/accidental, *except* the common "regular top + relaxed bottom" casual combo, which is not penalized.

```
d = fitRank(top) - fitRank(bottom)   // positive = top looser than bottom

if d ≥ 2:            adjustment = +0.08   (deliberate volume-balance silhouette)
elif d == 1:          adjustment = 0
elif d == 0:           adjustment = 0
elif d == -1:          adjustment = 0     (regular top + relaxed bottom: normal casual combo, not penalized)
elif d ≤ -2:          adjustment = -0.05 × |d|   (tighter top + looser bottom beyond one step: increasingly reads accidental)

silhouette_pair_score = clamp(base_score + adjustment, 0, 1)
```

This directional rule applies specifically to the **top–bottom** pair (where proportion storytelling happens). Other pairs (top–outerwear, bottom–shoes) use the base table with no directional adjustment — outerwear is conventionally looser than the layer beneath it regardless of direction, and shoe "fit" isn't a silhouette-volume axis in the same sense.

### 4.3 Body-profile modifiers

Each `fit_notes` entry maps to a lookup of `(issue, category, fit)` → multiplier ≤ 1.0 (these only dampen, per the master spec's framing of them as *fit issues* to manage, not preferences to optimize toward):

| Fit issue | Rule | Multiplier |
|---|---|---|
| `broad_chest` | top fit ∈ {slim} and material not tagged `stretch` | ×0.85 |
| `short_torso` | top or outerwear tagged `length: long` and fit ∈ {relaxed, oversized} | ×0.90 |
| `long_legs` | bottom tagged `break: no-break` (cropped) and fit == `slim` | ×0.92 |
| `large_thighs` | bottom fit ∈ {slim} and material not tagged `stretch` | ×0.85 |

Multiple applicable issues stack multiplicatively (e.g., `broad_chest` + a slim non-stretch top = single ×0.85 since only one rule matches that item; issues on different items in the same outfit each apply to their own item's pair-scores independently). Final silhouette subscore for the outfit is the §2.1-weighted aggregate of all pairwise `silhouette_pair_score` values, each pre-multiplied by whichever body-profile modifiers apply to the items in that pair.

**Edge case:** no `body_profiles` row or empty `fit_notes` (user selected "I don't know" at onboarding, §6.6) → no modifiers applied, base table only. This must never be treated as "user has no fit issues" for messaging purposes — Kyra should not claim fit certainty (§11 guardrail) when this data is simply absent.

---

## 5. Wardrobe Score

0–100 composite, seven components (§10). Each component produces a `[0,1]` normalized value; the composite is `Σ weight_i × component_i × 100`, then **confidence-damped** (§5.9) before display.

### 5.1 Versatility — 25%

**Definition:** how many *distinct, above-threshold* outfits (compatibility ≥ 0.65) each item can participate in, normalized against what's structurally achievable for a closet of this size (so raw combinatorics don't reward volume for its own sake).

```
for each item i:
  itemVersatility_i = count(outfits containing i with outfit compatibility ≥ 0.65, deduplicated per §6.3 near-duplicate rule)

expectedVersatility(n) = a size-indexed target curve, empirically seeded at:
  n=5 → 3, n=15 → 12, n=40 → 35, n=80 → 60
  (sublinear relative to raw combinatorics, which grow ~(n/3)² per item — but NOT log-shaped:
   the seeds themselves grow superlinearly until §6.3 dedup flattens them past n≈40)
  interpolated linearly between adjacent seed points for n ≥ 5, else 0;
  past n=80, extended at the last segment's slope (+0.625/item) so the target keeps growing
  and sheer closet volume can never saturate this component   (§0 amendment 7)

normalizedVersatility_i = clamp(itemVersatility_i / expectedVersatility(n), 0, 1)

component = mean(normalizedVersatility_i across all active items)
```

Normalizing per-item versatility against a size-indexed expectation is what prevents "buy more clothes" alone from inflating this score — a 15-item closet where items average 6 outfits each (half of the n=15 expectation of 12) scores lower than a 15-item closet averaging 12, even though both have the same *count* of items.

### 5.2 Fit confidence — 15%

```
perItemFitConfidence_i =
  0.6 (base, unconfirmed)
  + feedbackAdjustment_i        // §0 amendment 8: was `0.4 ×` this, which
                                // capped the component at 0.76

feedbackAdjustment_i =
  +0.4 if any `style_feedback` on this item has signal ∈ {like, wore+rating≥4} and none negative
  -0.5 if any signal ∈ {bad_fit, dislike}
  0 if no feedback exists on this item

also apply the §4.3 body-profile multiplier for this item's category/fit if a fit_notes issue matches (a garment that structurally conflicts with a stated fit issue cannot claim high fit confidence even absent explicit feedback)

component = mean(clamp(perItemFitConfidence_i, 0, 1) across active items)
```

### 5.3 Occasion coverage — 15%

```
targetOccasions = lifestyle_profiles.common_occasions ∪ {inferred from dress_code}
  (a fixed minimum set is always included: everyday-casual, work, date-night, semi-formal-event)

for each occasion o in targetOccasions:
  covered_o = 1 if ≥1 outfit exists (generated or historical) with occasion_tags matching o
              and compatibility ≥ 0.7, else 0

component = mean(covered_o across targetOccasions)
```

### 5.4 Color cohesion — 10%

```
palette = the set of primary_color_lch across active items
clusters = group palette into hue families (12 × 30° hue bins + a neutral bucket)

component = 1 - normalizedEntropy(cluster sizes)
  where normalizedEntropy = ShannonEntropy(clusterDistribution) / log2(13)
  // 13 = the whole cluster space (12 hue bins + neutral), NOT the number of
  // clusters this wardrobe occupies. See §0 amendment 9: the latter scores an
  // evenly-split two-colour wardrobe at 0, which contradicts the paragraph
  // immediately below.
```

A wardrobe concentrated in 2–4 hue families plus neutrals scores high (low entropy = high cohesion); one where every item is a different, unrelated hue scores low. **Edge case:** fewer than 4 chromatic items (mostly neutrals) → component defaults to `0.8` (neutrals-heavy is not incoherent, it's a valid capsule strategy — entropy over a near-empty chromatic set is not meaningful).

### 5.5 Wear utilization — 15%

Must reward genuine rotation, not raw wear counts (which would reward owning fewer items worn constantly out of necessity) or raw item count (which would reward hoarding).

```
activeWindow = 180 days
wornInWindow_i = 1 if last_worn_at within activeWindow, else 0
utilizationRate = mean(wornInWindow_i across active, non-archived items with age_in_closet ≥ 30 days)
  (items owned < 30 days are excluded from the denominator — they haven't had a fair chance to be worn yet)

component = utilizationRate
```

### 5.6 Condition — 10%

```
conditionValue: excellent=1.0, good=0.8, fair=0.5, worn=0.25, damaged=0.0
  // Shipped enum names differ (§0 amendment 10): new_with_tags=1.0,
  // like_new=0.9, good=0.8, fair=0.5, worn=0.25, damaged=0.0. `damaged` was
  // added to the enum on 2026-08-08; before that this bottom rung was
  // unreachable and the vision provider's `damaged` was folded into `worn`.
component = weighted mean of conditionValue_i, weighted by itemVersatility_i (§5.1)
  (a damaged rarely-worn accessory should matter less to overall wardrobe health than a damaged frequently-worn workhorse item)
```

### 5.7 Redundancy control — 10%

```
component = 1 - mean(redundancyScore_i across active items)
```

using the redundancy score defined in §7.1. Inverted because *low* redundancy is *good* wardrobe health.

### 5.8 Explicit non-goal: price must not inflate the score

No component above references `price_paid`. This is deliberate, per the master spec's explicit instruction ("do not equate expensive clothing with a higher score"). `condition` and `versatility` correlate loosely with quality/price in practice, but the formulas score the *functional* property (does it still look good, does it pair with things), not spend. A unit test (§10) asserts that two closets identical in every field except `price_paid` produce identical Wardrobe Scores.

### 5.9 Confidence damping for sparse wardrobes

Several components are *structurally* unable to score well with few items (§5.1's versatility curve and §5.3's occasion coverage both approach 0 as `n → 0`, by construction). That alone under-scores small wardrobes correctly for those components. But it is not sufficient protection: a 3-item closet where all 3 items happen to be perfectly color-matched, same-formality basics could still post a deceptively high *raw* composite (e.g., near-perfect color cohesion + condition + fit confidence, offsetting a merely-low versatility/coverage). The master spec explicitly forbids this ("a 3-item closet must not score 90 by accident").

Apply a global confidence multiplier to the **composite**, not to individual components (so individual component values remain interpretable in the UI's score breakdown):

```
N0 = 15   // items at which we consider the score "fully earned"
confidence(n) = clamp(n / N0, 0, 1)
displayedScore = confidence(n) × rawComposite + (1 - confidence(n)) × 50
```

`50` is used as the damping anchor (not 0) because it represents "unknown," not "bad" — a brand-new user should see a neutral, non-alarming number while the confidence ramps up, not a punitive one.

**Judgment call:** `N0=15` and the damping-anchor of `50` are product tuning constants without a canonical source in the spec; they are exposed as admin-configurable weights (§28) alongside the compatibility weights so they can be tuned post-launch against real cohort data.

### 5.10 Worked cold-start table

| n | versatility | occasion coverage | confidence(n) | example raw composite | displayed score |
|---|---|---|---|---|---|
| 0 | 0 (undefined — see §9) | 0 | 0 | n/a | **not shown** — replaced by empty-state CTA |
| 5 | ~0.15 (few combos possible) | ~0.25 | 0.33 | ~48 | `0.33×48 + 0.67×50 ≈ 49` |
| 15 | ~0.55 | ~0.60 | 1.0 | ~66 | `66` |
| 40 | ~0.75 | ~0.85 | 1.0 | ~78 | `78` |

---

## 6. Purchase Unlock Count

### 6.1 Why naive enumeration is infeasible

An "outfit" for unlock-counting purposes is defined as `{top|dress-item, bottom, shoes}` required, plus optional `outerwear` and 0–2 `accessories` chosen from up to 5 accessory items considered. Naive brute force enumerates the full cross-product:

```
combinations = |tops| × |bottoms| × |shoes| × (|outerwear|+1) × Σ_{k=0..2} C(|accessories|,k)
```

For a mid-size real closet (40 tops-equivalent items spread ~10/category across 4 required slots, plus 20 accessories):

```
10 × 10 × 10 × 11 × (1 + 20 + 190) = 1,000 × 11 × 211 ≈ 2,321,000 combinations
```

This is **O(∏|slot_i|)** — exponential in the number of slots, and this evaluation would need to run *every time a user views a product* on the decision page (§6.19), potentially dozens of times per session. At even 50µs per combination score (optimistic for an 8-component weighted score), 2.3M combinations is ~116 seconds of compute — completely incompatible with the synchronous product-evaluation UX.

**The naive approach becomes infeasible above roughly 8–10 items per required category or ~60–80 total wardrobe items** including accessories — well within range of an active user within a few months, so this must be solved for launch, not deferred.

### 6.2 Candidate-anchored pruned generation

Because the unlock count is specifically "outfits made possible by *this* candidate item," every generated combination must include the candidate. This collapses one slot entirely and lets us prune the rest aggressively *before* enumerating:

```
1. Fix candidate item into its role slot.
2. For every OTHER required/optional slot, compute pairwise compatibility (§2) between
   the candidate and every closet item eligible for that slot.
3. Keep only the top K=10 candidates per slot by pairwise compatibility with the anchor
   (K is configurable; 10 balances recall against combinatorial blowup).
4. Enumerate the cross-product of the pruned slots only.
```

New complexity: **O(K^(slots-1))**. With 3 remaining required-ish slots (bottom, shoes, and one of top/the candidate depending on candidate's own category) plus outerwear and ≤2 of a pruned top-10 accessory list:

```
10(bottom) × 10(shoes) × 11(outerwear incl. none) × (1+10+45) = 100 × 11 × 56 ≈ 61,600
```

Still too high for a single synchronous call. Apply a second, tighter prune specifically for accessories (they are 5% of the compatibility weight and rarely change whether a combination is viable): cap accessories to **top 4** candidates and **at most 1** accessory slot considered per combination (not 2) for the unlock-count use case specifically (product decision page), reserving 2-accessory enumeration for the interactive outfit builder where the user is actively curating one outfit at a time, not scoring thousands:

```
10 × 10 × 11 × (1+4) = 100 × 11 × 5 = 5,500 combinations
```

At ~50µs/score, ~275ms — within the 300–500ms compute budget (§6.5).

### 6.3 Near-duplicate detection

Two full outfit combinations are **near-duplicates** — counted as one unlocked outfit, not two — if they are identical in every role **except at most one**, and in that differing role the two items belong to the same **equivalence class**:

```
equivalenceClass(item) = (category, colorClusterId, formalityBucket, fit)

colorClusterId = the hue-bin index from §5.4's 12-bin clustering, plus a neutral flag
  (so "white tee #1" and "white tee #2" land in the same neutral bucket, not different hue bins)
formalityBucket = floor(formality_score / 10)   // matches the §3 anchor granularity
fit = the item's fit enum value directly
```

Concretely: two outfits differing only by which of two white t-shirts is used have identical `(top, bottom, shoes, outerwear, accessory)` equivalence-class tuples except the top slot's *specific item ID* differs while its equivalence class is identical → they collapse to one counted outfit.

**Implementation:** for every generated combination, compute a **canonical signature** = the sorted tuple of `equivalenceClass()` across all filled roles, and hash it (e.g., SHA-1 truncated to 64 bits). Deduplicate by signature before counting; the unlock count is `|distinct signatures among combinations that pass §6.4|`, not `|combinations|`.

### 6.4 Quality and gap thresholds

A deduplicated combination counts toward the unlock number only if it passes **both**:

1. **Quality threshold:** outfit compatibility score (§2) ≥ 0.65 (same threshold as Wardrobe Score's versatility component, §5.1, for consistency across the app's scoring surfaces).
2. **Novelty:** the combination was **not already achievable without the candidate** — i.e., re-running the same pruned generation with the candidate excluded and checking that no already-owned substitute in the candidate's equivalence class exists that would produce the same signature. (If the user already owns a white sneaker in the same formality bucket, a second white sneaker candidate cannot claim credit for combinations that pre-existing sneaker already unlocked.)

**"Fills a wardrobe gap"** is defined precisely: a combination fills a gap if its `(occasion_tag, formalityBucket)` pair had **fewer than 2** qualifying combinations (quality ≥ 0.65) in the wardrobe *before* the candidate was added, and has ≥1 more after. This flag is surfaced separately in the product decision UI ("fills a gap in: date night") rather than folded into the raw count, since gap-filling is a qualitatively different value proposition than "one more variation of what you already have plenty of."

### 6.5 Caching

```
cacheKey = hash(user_id, candidateAttributesHash, closetStateVersion, compatibilityWeightsVersion)

candidateAttributesHash = hash of the candidate's normalized (category, color, formality, fit, pattern)
  — NOT the product_candidate_id alone, so two different products with materially identical
  attributes share a cache entry (avoids re-computing for near-identical SKUs, e.g. color variants)

closetStateVersion = a per-user monotonically incrementing integer, bumped on:
  - closet item added / archived / hard-deleted
  - closet item's category, primary_color, formality_score, fit, or pattern edited
  NOT bumped on: laundry_state or availability_state changes (unlock count answers a
  hypothetical-ownership question, not "what can I wear today" — laundry cycling
  shouldn't invalidate a cache that's answering a different question)

compatibilityWeightsVersion = bumped globally whenever admin-configured weights (§10 of
  the master spec, §28) change — invalidates all users' cached unlock counts at once.
```

**TTL:** 30 days as a backstop even absent invalidation triggers (product prices/availability drift; a stale-but-not-technically-invalid unlock count older than 30 days is recomputed on next view regardless).

### 6.6 Compute budget

- **Target:** ≤ 500ms server-side compute for a cache miss, as part of the synchronous `/products/evaluate` call the user is waiting on (§14).
- **Timeout:** if pruned generation exceeds 800ms (e.g., pathological closet shape), return a degraded response: `outfits_unlocked: null`, `unlock_estimate_confidence: "computing"`, and complete the calculation asynchronously, pushing an update via Realtime when done. The UI must handle `null` here as a legitimate transient state, not an error (§21).

---

## 7. Redundancy and Cost-per-Wear

### 7.1 Redundancy score

Per item, computed against every **other active item in the same category**:

```
similarity(i, j) = 0.4 × colorHarmonyAsIdentity(i,j) + 0.3 × (1 - |formality_i - formality_j|/100)
                  + 0.2 × (fit_i == fit_j ? 1 : silhouetteAdjacency(fit_i, fit_j))
                  + 0.1 × (material_i ∩ material_j ≠ ∅ ? 1 : 0)

colorHarmonyAsIdentity(i,j) = 1 - clamp(ΔE(i,j) / 40, 0, 1)   // near-identical color, not "harmonizes with"
  (this is intentionally NOT the §1.4 harmony function — redundancy asks "are these the same
  color," not "do these colors go together," so it's a raw perceptual distance, not a harmony score)

redundancyScore_i = max(similarity(i,j) for j in sameCategory(i), j≠i, restricted to items whose
  occasion_tags/seasonality overlap i's — a linen shirt and a wool sweater aren't "redundant" even
  if both are white shirts-shaped, because they don't compete for the same wearing occasions)
```

**Duplicate flag** (used in §6.19's product decision page, "duplicate risk"): `similarity(i,j) ≥ 0.85`. The decision-page duplicate-risk calculation runs the same `similarity()` function between the **candidate product** and every owned item (plus wishlisted candidates) in the same category, surfacing the single highest-similarity match with its similarity score and a "this looks like your existing [item]" callout when ≥ 0.85, or "similar to, but distinct from, your existing [item]" when in the 0.65–0.85 band.

### 7.2 Cost-per-wear

For items with `wear_count > 0`:

```
costPerWear = price_paid / wear_count
```

For items with `wear_count == 0` (`price / 0` is undefined and must never reach that code path), use a **projected** cost-per-wear, explicitly labeled as an estimate in the UI (never presented as equal-confidence to an actual, historical cost-per-wear):

```
projectedAnnualWears = categoryBaseRate(item.category, item.subcategory)
                        × versatilityMultiplier(itemVersatility_i normalized 0–1, from §5.1)
                        × userCadenceMultiplier

categoryBaseRate: seeded population averages, e.g.
  everyday tee ≈ 40/yr, dress shirt ≈ 15/yr, occasion blazer ≈ 6/yr, formal suit ≈ 4/yr,
  everyday sneaker ≈ 60/yr, dress shoe ≈ 20/yr
  (admin-editable table, §28 — same mechanism as compatibility weights)

versatilityMultiplier = 0.5 + normalizedVersatility_i   // range 0.5–1.5

userCadenceMultiplier = user's own observed wears-per-item-per-year across their existing
  closet in the same category, normalized against the category base rate (defaults to 1.0
  with fewer than 5 historical wears in that category to average over)

projectedCostPerWear = price_paid / max(projectedAnnualWears × horizonYears, 1)
  horizonYears = 1 (fixed 12-month projection horizon)
```

**Edge case:** `price_paid` itself missing (gifted items, no receipt) — cost-per-wear is `null` and the UI omits the field entirely rather than showing `$0.00/wear` or `$∞/wear`, either of which is actively misleading.

---

## 8. Cold Start

Behavior at four closet sizes, across every score in this document:

| Size | Compatibility scoring (§2) | Wardrobe Score (§5) | Unlock count (§6) | Redundancy/CPW (§7) |
|---|---|---|---|---|
| **0 items** | N/A — no pairs exist. Outfit generation (§5.4) cannot run; Home shows the empty-state CTA ("Add five pieces and Kyra can begin building real outfits," §21) instead of a Daily Brief hero. | Not computed/displayed. §5.9's `n=0` row is explicitly a UI branch, not a `0` score — a `0` would read as "your wardrobe is bad," which is false; there is no wardrobe yet. | Cannot run (no items to combine with). Product decision page instead shows a qualitative "foundational piece" framing keyed off `lifestyle_profiles` alone (e.g., "a strong first top for your wardrobe") rather than a numeric unlock count. | N/A — no comparison set exists. |
| **5 items** | Runs normally; component 2.6 (user preference) and 2.7 (co-wear) both hit their cold-start priors (0.7 flat, Bayesian prior ~0.667) since there's no feedback/wear history yet. | Computed with heavy damping: `confidence(5)=0.33` → composite pulled ~67% toward the neutral 50 anchor (§5.10). | Naive enumeration is fully tractable at this size (§6.1's infeasibility threshold is ~8–10/category); the pruned algorithm still runs (same code path, no special-casing) but K=10 pruning is a no-op since fewer than 10 items exist per category anyway. | Redundancy comparison set is small; scores are volatile (one duplicate among 5 items is a much bigger relative signal than one among 40) but the formula requires no special-casing — small-n noise here is honest, not misleading, since two near-identical items in a 5-item closet genuinely is a bigger problem proportionally. |
| **15 items** | Fully normal; co-wear (§2.7) still leans on the category-pair prior for most pairs since 15 items haven't generated much specific-pair wear history yet. | `confidence(15)=1.0` — this is the design's stated "fully earned" point; score reflects raw composite. Occasion coverage (§5.3) is likely still partial (some target occasions uncovered), which is accurate, not a bug. | Pruned path is exercised for real (some categories may exceed K=10 candidates); near-duplicate collapsing starts to matter. | Comparison set large enough for the redundancy formula's occasion/season overlap filter to be meaningful. |
| **40 items** | Fully normal across all 8 components with real historical signal available for §2.6/§2.7. | `confidence(40)=1.0`; raw composite is the score shown. | This is past the naive-infeasibility threshold (§6.1) for at least the top/bottom/accessory categories in an active user's closet — the pruned/candidate-anchored path is load-bearing here, not just defensive. | Full signal; projected-CPW's `userCadenceMultiplier` (§7.2) now has enough same-category wear history (typically ≥5 items/category) to move off its 1.0 default. |

---

## 9. Unit Tests

Maps to §22's "Compatibility scoring," "Wardrobe score," and "Cost-per-wear calculation" requirements. Each test operates on the pure-function scoring core (no DB, no network) with fixture items.

**Color compatibility (§1–2.2)**
1. Two functional-neutrals (black + white) → score ≥ 0.90.
2. Two chromatic items at ΔH=105° (discordant zone) → score ≤ 0.40 and strictly lower than the same two items' scores would be if one were substituted with its neutral equivalent.
3. Monochrome pair with `|L1-L2|<20` and `|C1-C2|<15` (flat monochrome) → score ≤ 0.60, distinctly lower than a monochrome pair with value separation.
4. Complementary pair (ΔH≈170°) both at `C*>70` (saturated) → score in 0.55–0.70 band, strictly lower than the same hue pair with one muted (`C*<20`).
5. Pattern-on-pattern, same scale, unrelated hues → multiplier `×0.55` applied and verified against the pre-penalty harmony score.
6. Pattern-on-pattern, scale delta ≥2, shared hue family → multiplier `×0.85`, verified strictly greater than test 5's result.
7. `primary_color_lch = null` on one item → subscore exactly `0.6`, item flagged `low_confidence_color`.
8. The full olive-polo/stone-trousers/white-sneaker worked example (§2.2) reproduces `0.91 ± 0.01`.

**Formality (§3)**
9. Aggregation is not a mean: construct an outfit where mean(formalities) equals a second outfit's mean but the first has one outlier item — assert the first outfit's `outfit_formality` is strictly lower.
10. `deviation ≤ 10` → zero penalty applied (verify no penalty term fires below the gate).
11. Reproduce the worked example (§3.1): olive polo/stone trousers/white sneakers → `outfit_formality == 30 ± 1`.
12. Pairwise formality score at `Δf=40` → exactly `0`; at `Δf=0` → exactly `1`.

**Silhouette (§4)**
13. `d ≥ 2` (top looser than bottom) → positive directional adjustment applied, verified against the `d=1` no-adjustment case.
14. `d ≤ -2` (bottom looser than top beyond one step) → negative adjustment applied and result strictly less than the symmetric `|d|` case in the opposite direction.
15. `d == -1` (regular top + relaxed bottom) → zero adjustment (not penalized).
16. `broad_chest` fit issue against a slim non-stretch top → `×0.85` multiplier applied; same top tagged `stretch` → multiplier not applied.
17. No `body_profiles` row → zero modifiers applied, base table score returned unchanged.

**Wardrobe Score (§5)**
18. Two closets identical except `price_paid` → identical Wardrobe Scores (asserts §5.8's non-goal).
19. 3-item closet with artificially perfect color/formality/condition inputs does **not** exceed 55 (asserts §5.9 damping actually bounds the "lucky 3-item closet" failure mode named in the brief).
20. `confidence(0)` path is never invoked as a numeric score — calling the composite function with `n=0` returns a sentinel (`null`/not-applicable), not `0` or `50`.
21. `confidence(15) == 1.0` exactly (boundary of the damping curve).
22. Versatility component (§5.1): item present in 3 duplicate-signature outfits (per §6.3 equivalence) counts once, not three times, toward `itemVersatility_i`.

**Purchase unlock count (§6)**
23. Near-duplicate collapsing: two combinations differing only by swapping between two white t-shirts of the same formality bucket and fit → collapse to a single counted signature.
24. Two combinations differing by swapping a white t-shirt for a red t-shirt (different `colorClusterId`) → **not** collapsed, counted separately.
25. Quality threshold: a generated combination scoring `0.64` compatibility is excluded from the count; `0.65` is included (boundary test).
26. Novelty check: candidate whose equivalence class is already covered by an owned item contributes zero net-new unlocks for signatures achievable without it.
27. Gap-filling flag: an occasion/formality bucket with 1 pre-existing qualifying combination and 2 post-candidate combinations is flagged `fills_gap: true`; a bucket already at ≥2 is not.
28. Cache key changes when `closetStateVersion` bumps (item edited) but does **not** change when only `laundry_state` changes (asserts the §6.5 invalidation-trigger distinction directly, since getting this backwards would either serve stale unlock counts after real wardrobe changes or thrash the cache on every load/wash cycle).
29. Pruning: with a synthetic closet of 50 items/category, pruned generation returns the same *top-ranked* combinations (by score) as brute force over a reduced fixture, within the top-K window — asserts pruning doesn't silently drop the actually-best combinations.

**Redundancy and cost-per-wear (§7)**
30. Two items identical in color/formality/fit/material → `similarity ≥ 0.85`, flagged duplicate.
31. Two items same category but non-overlapping seasonality (linen shirt vs. wool sweater) → excluded from each other's redundancy comparison set regardless of raw similarity.
32. `wear_count == 0` never reaches a division producing `Infinity` or `NaN` — projected cost-per-wear path is invoked instead, and the return type is distinctly tagged `isProjected: true`.
33. `price_paid == null` → `costPerWear` is `null`, not `0` or `NaN`.
34. `userCadenceMultiplier` defaults to exactly `1.0` with fewer than 5 same-category historical wears, and departs from `1.0` at 5+.

**Cold start (§8)**
35. Parametrized test running the full scoring pipeline at `n ∈ {0, 5, 15, 40}` synthetic closets asserts: `n=0` → all scores are `null`/not-applicable (not zero); `n=5` → Wardrobe Score composite within the damped band computed by `0.33×raw + 0.67×50`; `n=15` → `confidence==1.0`; `n=40` → unlock-count pruned path is exercised (assert the pruning branch was taken, not the brute-force branch, via a code-path spy/flag).
