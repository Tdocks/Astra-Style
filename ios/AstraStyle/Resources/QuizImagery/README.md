# Quiz imagery — shipped content

This directory **is** the §6.9 preference quiz's content. Everything in it is copied into
the app bundle at build time and read at runtime by `StyleQuizCatalog`. Nothing about the
quiz's questions lives in Swift.

**Adding a comparison is a content change, not a code change.** Drop two cropped JPEGs in
here, add a stanza to `quiz-pairs.json`, rebuild. No Swift is touched, no project file is
edited, and nothing needs to know how many pairs there are.

## Current state: 3 of the 12–20 spec §6.9 asks for

The quiz runs on what exists. It asks three questions, shows "1 of 3", and produces a
preference vector with entries for the three axes those pairs probe and **no entries at all**
for the other five. That is the intended behaviour, not a degraded mode — see
`StylePreferenceInference`'s header for why an unasked axis must come back absent rather
than neutral.

| Pair | Axis | Option A | Option B |
|---|---|---|---|
| `formality-01` | Formality | Navy blazer, white shirt, flannel trouser, derby | Washed sweatshirt, olive chino, canvas sneaker |
| `colour-01` | Colour tolerance | Putty knit, stone trouser, tan loafer | Burgundy knit, forest cord, tan boot |
| `silhouette-01` | Silhouette | Fine knit, narrow trouser, leather boot | Mohair cardigan, wide-leg trouser, sneaker |

### Still to produce

Five axes have no imagery and therefore no reading. Each needs **two to three pairs**, not
one — a single comparison yields `.low` confidence forever (see the confidence table in
`StylePreferenceInference`), which is not enough for Kyra to state the preference back to
the user.

| Axis | What the pair must vary, and only that |
|---|---|
| `texture` | Flat, smooth cloth (poplin, worsted, fine gauge) against pronounced surface (chunky knit, tweed, corduroy, boucle). Same colour family, same cut, same formality on both sides. |
| `logo_tolerance` | Visible branding — a chest logo, a monogram, a legible wordmark — against the same outfit with none. Everything else identical. |
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
