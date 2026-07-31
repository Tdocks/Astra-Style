# Quiz imagery — shipped content

This directory **is** the §6.9 preference quiz's content. Everything in it is copied into
the app bundle at build time and read at runtime by `StyleQuizCatalog`. Nothing about the
quiz's questions lives in Swift.

**Adding a comparison is a content change, not a code change.** Drop two cropped JPEGs in
here, add a stanza to `quiz-pairs.json`, rebuild. No Swift is touched, no project file is
edited, and nothing needs to know how many pairs there are.

## Current state: 14 pairs, and all 8 dimensions produce a reading

14 is inside spec §6.9's 12–20 and leaves headroom under `StyleQuizEngine.maximumComparisons`.
The whole set was regenerated from scratch on 2026-07-31; nothing from the first batch survives
here or in `brand/quiz-imagery/`.

| Pair | Axis | Option A (negative end) | Option B (positive end) |
|---|---|---|---|
| `formality-01` | Formality | Washed sweatshirt, olive cotton trouser, canvas sneaker | Navy blazer, white shirt, grey wool trouser, cap-toe oxford |
| `formality-02` | Formality | White tee, mid-blue jeans, white leather sneaker | Charcoal suit, white shirt, navy tie, black oxford |
| `colour-01` | Colour tolerance | Putty knit, stone trouser, tan suede loafer | Burgundy knit, forest-green cord, tan suede loafer |
| `colour-02` | Colour tolerance | Stone-grey knit, oatmeal trouser, tan suede loafer | Cobalt knit, rust-orange trouser, tan suede loafer |
| `silhouette-01` | Silhouette | Close-cut navy fine knit, slim tapered navy trouser, black boot | Oversized navy knit, wide-leg navy trouser, black boot |
| `texture-01` | Texture | Smooth charcoal fine-gauge merino, flat worsted trouser | Chunky charcoal cable knit, charcoal corduroy trouser |
| `texture-02` | Texture | Smooth navy fine-gauge merino, flat navy wool trouser | Chunky navy cable knit, navy corduroy trouser |
| `logo-02` | Logo tolerance | Plain black quarter-zip | Same, with a white ringed chest emblem |
| `trend-01` | Trend tolerance | Classic navy single-breasted blazer, straight-leg trouser, oxford | Unstructured double-breasted blazer, pleated cropped trouser, lug-soled loafer |
| `trend-02` | Trend tolerance | Beige cotton gabardine trench | Beige technical nylon trench, taped seams, drawcord hem |
| `accessory-01` | Accessory preference | Oxford shirt and navy trouser, bare wrists, no belt | Same outfit with belt, steel watch, silk neck scarf |
| `accessory-02` | Accessory preference | Charcoal knit and grey trouser, bare wrists, no belt | Same outfit with belt, leather-strap watch, wool scarf |
| `contrast-01` | Contrast preference | Mid-grey knit, mid-grey trouser, mid-grey sneaker | Near-white knit, near-black trouser, black sneaker |
| `contrast-02` | Contrast preference | Mid-blue chambray, mid-blue trouser, mid-blue loafer | Pale ice-blue shirt, deep navy trouser, deep navy loafer |

Six axes have two pairs, which is the bar at which `StylePreferenceInference` will report
`.moderate` confidence on agreeing answers and Kyra is allowed to say the preference out loud.
**`silhouette` and `logo_tolerance` have one pair each, so they sit at `.low` confidence
permanently** — a single forced choice gives a direction and nothing else, no matter how clean
the photograph is. Those two axes produce a reading, and the reading is not statable. The two
pairs that would fix it are described under "Two pairs are missing" below.

## Every frame is the same man, and that is the point

This is the technique, and it matters more than any individual frame.

The frames are not generated independently. `scripts/generate_quiz_imagery.py` generates **one
canonical figure** — a headless man in a plain mid-grey base layer, saved as
`brand/quiz-imagery/_reference-figure.png` — and then dresses him. Every one of the 28 shipped
frames was produced by passing that figure to OpenAI's `/v1/images/edits` with a prompt whose
first sentence says to keep the same man, the same backdrop, the same lighting and the same
framing, and to change only the clothing. Read that script's header; the reasoning is there in
full and it is short.

The first batch was text-to-image, one prompt per frame, and the generator returned a different
person each time. Skin tone visibly changed between the two halves of three of ten candidate
pairs. That is a worse confound than any lighting difference, because the user may be answering
*the model* rather than the clothes and nothing downstream can tell.

What the change bought, measured:

- **Backdrop drift within a pair fell to 1.6 mean and 3.0 worst-case luma**, against 20.9 mean
  and 33.7 worst on the old vendor's text-to-image output and 13.9 mean on OpenAI's own
  text-to-image (`docs/16` §3.2). After the normalisation pass in the pipeline below, the
  residual is **0.8 or less** on every shipped pair.
- **The person is removed as a variable from the whole instrument**, not merely balanced inside
  each pair. Build, skin tone, framing scale and lighting are all held by the reference. That is
  a different and stronger property than "the two frames of this pair happen to match".
- **The accessory axis works.** Both "bare" frames have genuinely bare wrists, checked at full
  resolution, and both "layered" frames show a wristwatch on the correct wrist. This axis was
  unbuildable before: the previous generator put a watch on a man told not to wear one, on both
  frames.
- **Hands are clean** across the set, checked at full resolution. That is a property of this
  batch, not a guarantee about the model, and it is the first thing to re-check on anything new.

## Two pairs are missing, and each was rejected for a reason worth keeping

Both were generated and both were thrown away rather than shipped. Their prompts are already
fixed and committed in `scripts/generate_quiz_imagery.py`; **both regenerations are blocked on an
OpenAI billing hard limit** (`billing_hard_limit_reached`), not on an unresolved question. Once
the limit is raised:

```sh
python3 scripts/generate_quiz_imagery.py --pair logo-1 --pair silhouette-2
python3 scripts/build_quiz_imagery.py --pair logo-1 --pair silhouette-2
```

**`logo-1-b` came back wearing "HILFIGER" across the chest.** A real trademark on a garment we
generated and would ship inside the app is unshippable, so the file was **deleted from the repo
entirely** rather than left unreferenced — an unreferenced file is one careless manifest edit
away from shipping. The prompt now asks for an abstract emblem of three stacked white chevrons,
explicitly containing no letters and no words. The lesson generalises: **asking this model for a
wordmark makes it reach for a real brand.** The same failure produced a circled "G" reading as a
luxury house's mark on an earlier attempt at `logo-02`. Carry the logo axis with non-letterform
emblems.

**`silhouette-2-b` came back short-sleeved while its partner was long-sleeved.** Sleeve length
then sits in the frame alongside volume — two variables in a pair whose entire job is to isolate
one. The prompt now says "long-sleeved" and "with the sleeves down to the wrist". The two
rejected `silhouette-2` frames are still on disk in `brand/quiz-imagery/` as candidates; they are
not in this directory and are not in the manifest, so nothing can render them.

## Absent is honest; a confounded reading is not

The manifest supports an option loading on several axes at once, and a well-designed pair can
legitimately do that. **None of the 14 here do**, deliberately.

Look at `colour-01`: option B is not only more saturated, it is corduroy against a smooth knit.
Declaring a texture loading on it would harvest a second "measurement" per photograph — and it
would be a measurement of two things at once, with no way afterwards to tell which one the man was
answering. `trend-01` is the case that looks like a counter-example and is not: its option B
changes lapel, trouser and shoe together, because "current" is a bundle of details rather than any
one of them. That is still one axis, and it declares one loading.

Absent is honest. A confounded reading is not. Any new pair intended to probe two axes has to be
**generated** to probe two axes — varying both deliberately and nothing else — rather than having
a second loading added to a frame that happened to vary. A quiz with fewer questions is worth
more than one with a wrong answer baked into it, because the wrong answer is indistinguishable
downstream from a real one.

## What is still genuinely at risk

- **Two axes are at one pair and therefore at `.low` confidence permanently.** Not a defect in
  the imagery; a shortfall in coverage, fixed by the two regenerations above and by nothing else.
- **No blinded human rating.** Nobody has confirmed these read as *photographs of clothes* rather
  than as renders to a real user. Same gap `docs/16` §5 records.
- **One man throughout is a coverage question as well as a control.** The instrument now shows
  every user the same build and the same skin tone. That is the right trade for measurement — the
  alternative reintroduces the confound the whole technique exists to remove — but it should be a
  recorded decision rather than a side effect nobody noticed.
- **The invented emblems are invented, not cleared.** `logo-02`'s concentric rings and
  `logo-1-b`'s pending chevrons are abstract by construction, and a generated mark can still land
  near a real one. Worth a second opinion before this ships to the App Store.
- **Texture is the axis most likely to regress.** Chunky fabrics genuinely have more volume than
  fine ones, so surface drags tone and cut along with it. Both texture pairs hold here; that is a
  result about these frames, not a property of the model.
- **Backdrop normalisation is still mandatory.** 1.6 raw is small, not zero, and the brighter
  frame is the more appealing photograph regardless of what it shows.

## Pipeline

`scripts/build_quiz_imagery.py` performs, in order: **normalise** each pair's backdrop to their
shared mean luma by scalar gain (preserves hue relations), **crop** the top 7%, **resize** to
720px wide, and write JPEG q90. Full-resolution sources stay in `brand/quiz-imagery/`; only the
processed files ship here. The normalisation targets the *mean of the pair* rather than a fixed
value, because neither frame is more correct than the other — they only have to match.

It accepts **`.png` sources as well as `.jpg`**, and PNG is what it finds today:
`generate_quiz_imagery.py` writes PNG because that is what OpenAI's images API returns, and
re-encoding to JPEG before the crop and resize would quantise twice for no reason.

## Manifest format

```jsonc
{
  "version": 2,
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

1. **Generate it from the reference figure, using the skeleton in
   `scripts/generate_quiz_imagery.py`.** `REFERENCE_PROMPT` and `EDIT_SKELETON` in that file are
   the source of truth for wording; vary only the garment clause. Do not write a fresh
   text-to-image prompt, and do not regenerate the reference figure to add one pair — a new
   figure is a new man, and every existing frame would then disagree with the new one.
2. **Crop the top 7%** and resize to 720px wide. Both live in the pipeline, unconditionally, and
   neither is a per-image judgement.
3. **Check the hands at full resolution** in the source PNG before accepting a frame.
4. **Check that it is the same man** — build, skin tone, framing scale. The reference holds it in
   practice; nothing enforces it.
5. **One variable per pair** unless the pair was generated to carry two. See above.
6. Both files must be present. A stanza whose image is missing is skipped with a warning and the
   quiz simply gets shorter; it never renders a placeholder, because a placeholder would be
   answered like a real photograph.

## History: what a previous approach did

Kept because each of these cost real time to discover, and because a reader looking at an old
commit or an old document will meet them. **None of it is live guidance.** The vendor named here
was dropped on 2026-07-31 (`docs/16` §3.5) and nothing new goes to it.

- **Higgsfield `soul_2` could not hold one man across a pair.** Skin tone changed between A and B
  in three of ten candidate pairs, which sank them. This is what the reference-figure technique
  replaced.
- **`soul_2` put a wristwatch on a man told to wear none**, on both `accessory` "bare" frames, so
  the accessory axis could not be built by negation there at all. That single result is what
  decided the vendor race (`docs/16` §3.1).
- **`soul_2` rejected a seed parameter outright**, which is why "pin the backdrop seed" was never
  an alternative to normalising in post. Whether OpenAI accepts a seed was never tested and no
  longer matters much: reference-conditioned editing holds the backdrop far better than a pinned
  seed was ever likely to.
- **`soul_2` left the chin and neck in frame** every time despite the prompt. The crop was
  introduced for that. It stays unconditionally anyway — a frame that ships uncropped shows a
  face the quiz promised not to, and the cost of being wrong is asymmetric.
- **Three attempts at a second texture pair on `soul_2`** each varied tone or trouser width
  alongside surface. Both texture pairs here hold, generated from the reference with the trouser
  clause naming the constant explicitly.
