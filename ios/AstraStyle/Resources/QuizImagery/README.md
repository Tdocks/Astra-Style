# Quiz imagery — shipped content

This directory **is** the §6.9 preference quiz's content. Everything in it is copied into
the app bundle at build time and read at runtime by `StyleQuizCatalog`. Nothing about the
quiz's questions lives in Swift.

**Adding a comparison is a content change, not a code change.** Drop two cropped JPEGs in
here, add a stanza to `quiz-pairs.json`, rebuild. No Swift is touched, no project file is
edited, and nothing needs to know how many pairs there are.

## Current state: 15 pairs (30 frames), and all 8 dimensions produce a reading

15 is inside spec §6.9's 12–20 and leaves headroom under `StyleQuizEngine.maximumComparisons`.
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
| `logo-01` | Logo tolerance | Plain black crew-neck sweatshirt | Same, with Astra monogram composited on the left chest |
| `logo-02` | Logo tolerance | Plain black quarter-zip | Same, with Astra monogram composited on the left chest |
| `trend-01` | Trend tolerance | Classic navy single-breasted blazer, straight-leg trouser, oxford | Unstructured double-breasted blazer, pleated cropped trouser, lug-soled loafer |
| `trend-02` | Trend tolerance | Beige cotton gabardine trench | Beige technical nylon trench, taped seams, drawcord hem |
| `accessory-01` | Accessory preference | Oxford shirt and navy trouser, bare wrists, no belt | Same outfit with belt, steel watch, silk neck scarf |
| `accessory-02` | Accessory preference | Charcoal knit and grey trouser, bare wrists, no belt | Same outfit with belt, leather-strap watch, wool scarf |
| `contrast-01` | Contrast preference | Mid-grey knit, mid-grey trouser, mid-grey sneaker | Near-white knit, near-black trouser, black sneaker |
| `contrast-02` | Contrast preference | Mid-blue chambray, mid-blue trouser, mid-blue loafer | Pale ice-blue shirt, deep navy trouser, deep navy loafer |

Seven axes have two pairs, which is the bar at which `StylePreferenceInference` will report
`.moderate` confidence on agreeing answers and Kyra is allowed to say the preference out loud.
**`silhouette` has one pair, so it sits at `.low` confidence permanently** — a single forced
choice gives a direction and nothing else, no matter how clean the photograph is. That axis
produces a reading, and the reading is not statable. The pair that would fix it is described
under "One pair is missing" below. Both logo pairs ship; their branded frames are **composited**
(`scripts/composite_quiz_logo.py`), not regenerated.

## Every frame is the same man, and that is the point

This is the technique, and it matters more than any individual frame.

The frames are not generated independently. `scripts/generate_quiz_imagery.py` generates **one
canonical figure** — a headless man in a plain mid-grey base layer, saved as
`brand/quiz-imagery/_reference-figure.png` — and then dresses him. The garment photographs were
produced by passing that figure to OpenAI's `/v1/images/edits` with a prompt whose first sentence
says to keep the same man, the same backdrop, the same lighting and the same framing, and to
change only the clothing. Logo "b" frames are then composited from their plain partners. Read
that script's header; the reasoning is there in full and it is short.

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

## One pair is missing, and it was rejected for a reason worth keeping

`silhouette-2` was generated and thrown away rather than shipped. Its prompt is already fixed and
committed in `scripts/generate_quiz_imagery.py`; **regeneration is blocked on an OpenAI billing
hard limit** (`billing_hard_limit_reached`), not on an unresolved question. Once the limit is
raised:

```sh
python3 scripts/generate_quiz_imagery.py --pair silhouette-2
python3 scripts/build_quiz_imagery.py --pair silhouette-2
```

**`silhouette-2-b` came back short-sleeved while its partner was long-sleeved.** Sleeve length
then sits in the frame alongside volume — two variables in a pair whose entire job is to isolate
one. The prompt now says "long-sleeved" and "with the sleeves down to the wrist". The two
rejected `silhouette-2` frames are still on disk in `brand/quiz-imagery/` as candidates; they are
not in this directory and are not in the manifest, so nothing can render them.

**Logo history (shipped via compositing, not regeneration).** An earlier `logo-1-b` came back
wearing "HILFIGER" across the chest — unshippable; the file was deleted. The logo axis now ships
both pairs with Astra's monogram composited onto the plain frame (`scripts/composite_quiz_logo.py`).
Lesson: **asking this model for a wordmark makes it reach for a real brand.** Carry the axis with
a mark that is not a third-party trademark and does not invite brand preference as a confound.

## Absent is honest; a confounded reading is not

The manifest supports an option loading on several axes at once, and a well-designed pair can
legitimately do that. **None of the 15 here do**, deliberately.

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

- **`silhouette` is at one pair and therefore at `.low` confidence permanently.** Not a defect in
  the imagery; a shortfall in coverage, fixed by regenerating `silhouette-2` and by nothing else.
- **No blinded human rating.** Nobody has confirmed these read as *photographs of clothes* rather
  than as renders to a real user. Same gap `docs/16` §5 records.
- **One man throughout is a coverage question as well as a control.** The instrument now shows
  every user the same build and the same skin tone. That is the right trade for measurement — the
  alternative reintroduces the confound the whole technique exists to remove — but it should be a
  recorded decision rather than a side effect nobody noticed.
- **The logo mark is Astra's monogram.** That removes third-party trademark risk and brand-preference
  confounding; it is still worth a second opinion before App Store submission that the mark reads
  as "a logo" rather than as noise.
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

## The logo pairs are built differently, and it matters

`logo_tolerance` is the one axis whose two frames are **not** two photographs.
The branded frame **is** the plain frame with a mark composited onto it
(`scripts/composite_quiz_logo.py`) — same man, same fold of cloth, same shadow,
the same pixel everywhere the mark is not. Backdrop delta between the two: 0.0,
necessarily.

Generating a second frame, even from the same reference figure, would let the
drape shift and the fabric catch the light differently. All of that is signal a
man might answer and none of it is branding. Compositing removes the
possibility rather than measuring it, which makes this the most rigorous pair
in the set.

**The mark is Astra's own monogram, and the reason is measurement, not law.**
A first attempt asked the generator for a wordmark and got `HILFIGER` — a real
trademark, unshippable, file deleted. Replacing it with an abstract geometric
emblem fixed that and failed a plainer test: it looked like nothing any brand
has made, which is to say it looked generated.

But a real mark fails for a better reason. Put one on the garment and the man
stops answering *"do I mind visible branding"* and starts answering *"do I like
that company"*. Those come apart constantly — someone happy in a large Carhartt
logo may find another house naff — so the quiz would record low logo tolerance
for a man whose logo tolerance is high. Same class of error as a pair whose
frames differ in sleeve length: a second variable riding along, recorded as if
it were the first, undetectable downstream.

Astra's monogram has neither problem. Not a third party's mark, and it carries
no prior brand opinion for the man answering — it is simply *a logo*, which is
exactly and only what this axis asks about. It is also the one mark that can be
rendered identically on every garment, forever.

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
