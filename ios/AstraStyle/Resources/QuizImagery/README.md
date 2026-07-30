# Quiz imagery — shipped content

This directory **is** the §6.9 preference quiz's content. Everything in it is copied into
the app bundle at build time and read at runtime by `StyleQuizCatalog`. Nothing about the
quiz's questions lives in Swift.

**Adding a comparison is a content change, not a code change.** Drop two cropped JPEGs in
here, add a stanza to `quiz-pairs.json`, rebuild. No Swift is touched, no project file is
edited, and nothing needs to know how many pairs there are.

## Current state: 6 of the 12–20 spec §6.9 asks for

The quiz runs on what exists. It asks six questions and produces a preference vector with
entries for the four axes those pairs probe and **no entries at all** for the other four.
That is the intended behaviour, not a degraded mode — see `StylePreferenceInference`'s header
for why an unasked axis must come back absent rather than neutral.

`texture` has one pair and therefore `.low` confidence permanently. That is deliberate: a
second texture pair was generated and **rejected** rather than shipped, because it varied
trouser colour and framing as well as surface. A confounded reading is worse than an absent
one, and this directory would rather ask four questions honestly than five ambiguously.

| Pair | Axis | Option A | Option B |
|---|---|---|---|
| `formality-01` | Formality | Navy blazer, white shirt, flannel trouser, derby | Washed sweatshirt, olive chino, canvas sneaker |
| `colour-01` | Colour tolerance | Putty knit, stone trouser, tan loafer | Burgundy knit, forest cord, tan boot |
| `silhouette-01` | Silhouette | Fine knit, narrow trouser, leather boot | Mohair cardigan, wide-leg trouser, sneaker |
| `texture-01` | Texture | Smooth charcoal fine-gauge knit, flat wool trouser | Chunky charcoal cable knit, corduroy trouser |
| `logo-01` | Logo tolerance | Plain navy sweatshirt | Same, with a lettered chest wordmark |
| `logo-02` | Logo tolerance | Plain black quarter-zip | Same, with a white ringed chest emblem |

### Still to produce

Five axes have no imagery and therefore no reading. Each needs **two to three pairs**, not
one — a single comparison yields `.low` confidence forever (see the confidence table in
`StylePreferenceInference`), which is not enough for Kyra to state the preference back to
the user.

| Axis | What the pair must vary, and only that |
|---|---|
| `texture` | One pair shipped, a second wanted. Flat, smooth cloth against pronounced surface, holding colour and cut. **Hard to generate** — see "What the 2026-07-30 batch learned". |
| `trend_tolerance` | A current cut or styling detail against a long-lived one at the same formality. The hard one to shoot fairly: "current" reads as "expensive" unless both frames are equally well made. |
| `accessory_preference` | The same base outfit worn bare against the same outfit with a watch, a belt, a scarf, a bag. Literally the same garments. |
| `contrast_preference` | Tonal, one narrow value band, against high contrast between top and bottom. Hold hue constant so this does not become a second colour question. |

Two to three pairs each is 10–15 more comparisons; with the three that exist that lands
inside §6.9's 12–20 and leaves headroom under `StyleQuizEngine.maximumComparisons`.

### Why the three shipped pairs declare exactly one loading each

The manifest supports an option loading on several axes at once, and a well-designed pair
can legitimately do that. **None of the three here do**, deliberately.

Look at `colour-01`: option B is not only more saturated, it is corduroy against a smooth
knit. `silhouette-01` option B is not only looser, it is mohair against fine gauge. Declaring
a texture loading on either would harvest a second "measurement" per photograph — and it
would be a measurement of two things at once, with no way afterwards to tell which one the
man was answering. `brand/quiz-imagery/README.md` makes the same point about lighting and
composition: when a frame varies on more than the axis under test, the quiz records the wrong
answer *in a form nothing downstream can detect*.

Absent is honest. A confounded reading is not. Any new pair intended to probe two axes has to
be **shot** to probe two axes — varying both deliberately and nothing else — rather than
having a second loading added to a frame that happened to vary.

## What the 2026-07-30 batch learned

Ten candidate pairs were generated to fill the five empty axes. **Three shipped.** The seven
rejects are the useful part of this section, because each failed for a reason that will recur.

**The model cannot be held constant between two frames.** In `trend-01`, `trend-02` and
`contrast-01` the man's skin tone visibly changes between A and B. Every one of the six
already-shipped frames happens to show the same light-skinned model, which reads as a
standard — it was luck, not control. A different person inside a pair is a worse confound than
the backdrop drift this file already warns about: the user may be answering the model rather
than the clothes, and nothing downstream can tell. **This is the single biggest obstacle to
finishing the quiz**, and prompt wording does not fix it. The fix is reference-conditioned
generation — a trained Soul ID, or the same reference frame passed to both sides — so both
options are the same man in different clothes. That is a change of technique, not of wording.

**Soul 2.0 rejects a `seed` parameter.** This file's known-issue #1 offers two fixes for
backdrop drift, "pin the backdrop seed, or normalise the background channel in post". The
first is not available: the API answers `Higgsfield Soul 2.0 does not support this parameter`.
So normalisation in post is the only route, and it is now mandatory rather than optional —
measured drift across ten raw pairs averaged **20.9** luma and reached **33.7**, against the
~1.0 the shipped pairs sit at after normalising. The step is in the pipeline below.

**The model puts a wristwatch on a man told to wear none.** Both `accessory-01-a` and
`accessory-02-a` were prompted "no belt, no watch and no accessories of any kind" and both
came back wearing a watch. Since the bare side is half the comparison, the accessory axis
cannot be built by negation — the "without" frame has to be generated some other way, or
retouched.

**"No text, no logos" is in the mandatory skeleton, and one axis is about logos.** The
`logo_tolerance` pairs necessarily drop that clause from their B side. This is the only
sanctioned deviation from the verbatim-skeleton rule, and it is confined to that clause on
that side; everything else stays identical.

**Letterforms drift toward real trademarks.** A first attempt at `logo-02` returned a circled
"G" that reads as a luxury house's mark. It was regenerated as an abstract ringed emblem.
Prefer non-letterform emblems. `logo-01-b`'s invented "STANESY" wordmark is retained because a
wordmark is the more realistic branding cue — but it is invented, and it is worth a second
opinion before this ships to the App Store.

**Texture drags colour and volume with it.** Three attempts at a second texture pair each
varied tone or trouser width alongside surface, because chunky fabrics genuinely have more
volume. Holding the trouser clause word-for-word identical across A and B got closest and
still drifted. This axis probably needs a real shoot, or reference conditioning.

## Pipeline

`scripts/build_quiz_imagery.py` performs, in order: **normalise** each pair's backdrop to their
shared mean luma by scalar gain (preserves hue relations), **crop** the top 7%, **resize** to
720px wide, and write JPEG q90. Full-resolution sources stay in `brand/quiz-imagery/`; only
the processed files ship here. The normalisation targets the *mean of the pair* rather than a
fixed value, because neither frame is more correct than the other — they only have to match.

## Manifest format

```jsonc
{
  "version": 1,
  "pairs": [
    {
      "id": "formality-01",          // unique; answers are stored against it, so never reuse or rename
      "priority": 0,                 // optional; lower opens the quiz when pairs are otherwise equal
      "option_a": {
        "id": "tailored",            // unique within the pair; stored as the chosen answer
        "image": "quiz-formality-a", // file in this directory, without .jpg
        "accessibility_description": "…",
        "loadings": { "formality": 1.0 }   // -1…1 per axis, per StyleDimension's sign convention
      },
      "option_b": { }
    }
  ]
}
```

Axis keys are the raw values of `StyleDimension`: `colour_tolerance`, `formality`,
`silhouette`, `texture`, `logo_tolerance`, `trend_tolerance`, `accessory_preference`,
`contrast_preference`. Sign conventions are documented case by case on that enum and must not
be reinterpreted here — a flipped sign silently inverts every profile already stored.

`no_preference` is reserved as an option id and a manifest using it is rejected.

### `accessibility_description` is required, and it is not decoration

The entire question is inside the photograph. Without this string the screen is two unlabelled
buttons for a VoiceOver user, which spec §19 does not permit. A pair missing it is dropped
from the catalog rather than shipped unlabelled.

Write it as a plain inventory of the garments — "a navy blazer with patch pockets over an
open white shirt" — in the same order and at the same level of detail on both sides. Do not
name the axis and do not characterise the look. "The formal option" tells a VoiceOver user
which answer means what, and he is then answering a different question from everyone else.

## Rules a new pair must satisfy

1. **Reuse the prompt skeleton in `brand/quiz-imagery/README.md` verbatim.** Identical backdrop,
   lighting, framing, lens. Vary only the garment clause. If one frame is better lit than its
   partner the user picks the photograph and the quiz records a style preference — wrong, and
   undetectable afterwards.
2. **Crop the top 7%** to remove the chin and neck that the generator leaves in frame despite
   the prompt, then resize to 720px wide. The files here were produced that way; the crop lives
   in the pipeline and is not a per-image judgement.
3. **Check the hands at full resolution** before accepting a frame. The current batch is clean.
   That is a property of the batch, not of the model.
4. **One variable per pair** unless the pair was shot to carry two — see above.
5. Both files must be present. A stanza whose image is missing is skipped with a warning and the
   quiz simply gets shorter; it never renders a placeholder, because a placeholder would be
   answered like a real photograph.
