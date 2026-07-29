# 14 — Frame-aware fit

**Status:** design, not built. Targets Phase 2 (Identity), because it consumes the measurements
§6.6 collects and feeds the Style DNA that §6.10 produces.

Spec §6.6 collects height, chest, waist, inseam, neck, shoe/shirt/trouser size, preferred fit,
and free-text fit issues. Spec §9's `body_profiles` table stores all of it. Then nothing reads
it. Recommendation (§10) scores colour, formality, silhouette, season, preference, co-wear,
occasion and laundry — eight dimensions, none of which know the wearer's proportions. We ask a
man his inseam during onboarding and never use the answer.

This document specifies the layer that closes that gap.

---

## 1. The thing to get right before anything else

Half of received menswear fit advice is durable optics. The other half is convention that has
already turned over once in the last fifteen years. **If both are encoded in the same table, the
app repeats stale blog dogma in the same confident voice it uses for geometry** — and there is
no way to update one without auditing the other.

So every rule carries a `basis` field, and the two bases are treated differently.

### `basis: .optical` — durable

These follow from how shapes and lines are read. They do not go out of fashion:

- A horizontal line placed at the widest point of a shape emphasises that width. Waistband and
  jacket hem placement are horizontal lines.
- Fewer horizontal breaks between shoulder and shoe read as a longer line.
- A shoulder seam sitting on the joint reads structured; off the joint reads wider and softer.
- Rigid fabric holds its own volume; fluid fabric takes the body's. Two garments of identical
  measured width read completely differently depending on which they are.
- Contrast draws the eye to where it is placed.
- A garment under tension reads as ill-fitting regardless of its cut.

### `basis: .convention` — expiring

Widely repeated, genuinely useful *now*, and certain to change:

- Lapel width scaled to chest breadth (cycles roughly every decade).
- Pattern scale matched to frame size (weak, widely violated by good dressers).
- Prescriptions against whole categories for whole body types — "short men shouldn't wear
  double-breasted," and similar.

Convention rules carry a `reviewAfter` date and get a lower confidence weight. When one expires,
it stops firing rather than silently continuing to be asserted. The optical set needs no such
handling.

### Worked example: your skinny-jeans case

The received rule is *"muscular build → not skinny jeans."* It is convention, and it is subtly
wrong. The optical rule underneath it is *"a garment under tension reads as ill-fitting."*

Those give different answers. A muscular thigh in rigid 100% cotton selvedge cut slim reads as
strained — the fabric can't move, so it shows every place it's being asked to. The same thigh in
a slim trouser with 2% elastane and a generous thigh block, tapering below the knee, reads
clean and deliberate. Same nominal silhouette, opposite outcome, and the difference is fabric
and block — not width.

The convention rule bans a category. The optical rule identifies the actual failure and leaves
the category open. The optical rule is also the one that can explain itself to the user without
saying anything about his body.

**This is why the two bases can't share a table.** Ship only the convention version and Astra
tells a muscular man he can't wear something he can in fact wear well — confidently, and wrongly.

---

## 2. Three axes, derived — never a body-type label

Spec §2 bans shaming body type. A single archetype label is where that goes wrong: it flattens a
person into a box, the box gets a name, and the name gets surfaced. Three orthogonal continuous
axes carry the same information with nothing to name.

The somatotype vocabulary the menswear industry uses casually — ectomorph / mesomorph /
endomorph — is **not used here.** It originates in Sheldon's 1940s constitutional psychology,
which tied body shape to personality and criminality, and is discredited. It is also imprecise
for our purpose. Its convenience is not worth inheriting.

| Axis | Derived from | Range | What it drives |
|---|---|---|---|
| **Taper** | chest − waist (the tailoring "drop") | straight ← → strong V | jacket suppression, top-block fit, whether a boxy cut reads intentional |
| **Proportion** | inseam ÷ height | long-torso ← → long-leg | rise, break, waistband height, where to place the one horizontal line you get |
| **Scale** | height band, plus chest and neck | compact ← → tall | number of breaks, layering depth, total visual complexity |

Notes on the derivation:

- **Drop is real tailoring.** A drop of 6" is graded regular, 7–8" athletic, ≤4" straight. This
  is how suits are actually sized; it is not an invented metric.
- **Neck relative to chest separates muscular from broad** at the same chest measurement. A 46"
  chest with a 16.5" neck and a 46" chest with a 15" neck want different armholes.
- **Weight is deliberately not an input**, even though §6.6 collects it as optional. It is the
  most shame-adjacent field and the least informative one — chest, waist and neck together
  describe the frame better, and none of them carry weight's baggage. Collecting it for the
  user's own reference is fine. Feeding it to a recommender that then tells him what to wear is
  not.

### Confidence, and the "I don't know" path

Spec §6.6 requires "I don't know" on every field, so **most users will have partial data and
some will have none.** Each axis therefore carries a `confidence: Double` alongside its value:

| Available | Behaviour |
|---|---|
| Nothing | All axes nil. Frame scoring contributes zero and the outfit score renormalises. Astra behaves exactly as it does today. |
| Shirt + trouser size only | Coarse taper and scale at low confidence. Enough to avoid the obvious mistakes. |
| Full measurements | All three axes at full confidence. |
| Measurements + fit issues | Full axes, plus explicit overrides — a stated fit issue always outranks a derived one. |

Low confidence must attenuate the advice, not just the score. A rule fired at 0.3 confidence is
phrased as an option ("a straight leg is worth trying here"); the same rule at 0.9 is phrased as
a reason ("straight leg — it balances the shoulder line"). **Overclaiming from thin data is the
failure mode that makes a styling app feel stupid**, and it is entirely avoidable.

---

## 3. Where it enters scoring

§10's weight table is a published contract that sums to 1.0. Adding a ninth dimension would
force a rebalance of all eight. Instead, frame fit splits the **existing** `silhouette` 0.15:

```
silhouetteCompatibility = (internal × 0.55) + (frameHarmony × 0.45)
```

- `internal` — do these garments work with each other. What the dimension means today.
- `frameHarmony` — does this silhouette work on this wearer. New.

The blend is server-configurable alongside the §10 weights (§28 admin tool), so it can be tuned
without a client release. When frame confidence is zero, the blend collapses to `internal × 1.0`
and today's behaviour is reproduced exactly.

`CompatibilityBreakdown` gains both sub-scores as stored properties so the meter in §6.13 can
show *why* silhouette scored what it scored, and so the split is inspectable in tests.

### Ranking, never filtering

Frame fit **adjusts order. It never removes an option.** You raised this yourself — crossover
has to happen for personal preference — and it is also the safer failure mode: a bad ranking is
a mildly worse suggestion, while a bad filter makes a garment the user owns and likes silently
disappear from an app whose whole job is to use what he already has.

Concretely: a frame-suboptimal outfit can still surface as the top recommendation if colour,
occasion and stated preference all favour it. `frameHarmony` is 45% of 15% — about 7 points of
100 at full confidence. Enough to break a tie, not enough to overrule the user.

Explicit preference beats derived frame data, always. A man who owns four pairs of wide-leg
trousers and wears them constantly has told us something more reliable than his inseam did.

---

## 4. Language

The rules describe the **garment**, never the body:

| Never | Instead |
|---|---|
| "Skinny jeans don't suit your build" | "A straight leg through the thigh, tapered below the knee" |
| "This is flattering on you" | "This balances the shoulder line" |
| "Avoid — you're short" | "A higher rise gives you a longer line here" |
| "Your body type is…" | *(no such sentence exists)* |

Three rules for this copy:

1. **The subject of the sentence is the clothing.** If the user's body is the grammatical
   subject, rewrite it.
2. **"Flattering" is banned.** It is a euphemism for concealment and every reader knows it.
   Say what the garment does — balances, lengthens, defines, softens.
3. **No comparatives against other bodies.** Nothing is "better for your build than for
   someone's."

This is enforceable the same way the sparkle ban is: `scripts/check_ui_conventions.py` gets a
denylist for "flatter/flattering," "your build," "your body type," "for someone your size," and
"despite your." A CI check is the only version of a tone rule that survives a year of new
strings being added by whoever is on the ticket.

---

## 5. Implementation shape

New, all in Phase 2:

```
Domain/Models/FrameProfile.swift        // three axes + per-axis confidence
Domain/Services/FrameDerivation.swift   // measurements -> FrameProfile, pure and testable
Domain/Services/FitRules.swift          // rule set, each tagged .optical or .convention
Domain/Services/FrameHarmonyScorer.swift// FrameProfile x garment -> 0...1 + reasons
```

Changed:

- `CompatibilityScoring.swift` — split `silhouetteCompatibility` into the two sub-scores.
- `body_profiles` — add derived `frame_taper`, `frame_proportion`, `frame_scale` and their
  confidences. Derived server-side on profile write so the client and the Edge Functions can
  never disagree about a user's frame.
- `POST /style-dna/generate` — include the frame axes in the prompt context. Kyra should know
  the wearer's proportions when she writes the Style DNA summary, not just when ranking.

Tests that matter more than the others:

- **Zero measurements reproduces today's scores exactly.** This is the regression that would
  otherwise ship silently, since it only affects users who skipped §6.6 — the majority.
- Low confidence produces hedged phrasing, not assertive phrasing.
- A stated fit issue overrides a contradicting derived axis.
- No rule output contains a banned phrase (asserted directly against the rule table, not only
  via the string scan).
- A convention rule past its `reviewAfter` date stops firing.

---

## 6. Open, needs a call

1. **Does the user ever see his own axes?** Showing them makes the reasoning legible and is
   arguably owed to him. It also creates the label we were avoiding. Middle path: show the
   *consequences* in the Style DNA result ("Straight-leg trousers and a defined shoulder are
   your reliable shapes") without ever printing the axis values.
2. **Do we ask preferred fit before or after deriving?** Asking first anchors him. Deriving
   first and then asking gives a cleaner read on genuine preference — and the gap between the
   two is itself signal worth storing.
3. **Camera-assisted measurement** (§6.6, "future beta"). Real Vision-framework body
   measurement is achievable but inaccurate enough that a wrong number is worse than a missing
   one — a confident bad inseam poisons every rule downstream, and the user has no way to know.
   Recommend deferring past Phase 2.
