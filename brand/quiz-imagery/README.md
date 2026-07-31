# Style quiz imagery — full-resolution sources

The generated sources for the §6.9 preference quiz. Nothing here ships. The shipped tiles live in
`ios/AstraStyle/Resources/QuizImagery/`, produced from these by `scripts/build_quiz_imagery.py`
(normalise the pair's backdrop, crop the top 7%, resize to 720px, JPEG q90). Sources stay here at
full resolution so a pair can be reprocessed without paying to regenerate it.

**The whole set was regenerated from scratch on 2026-07-31.** Every frame produced on the previous
vendor was deleted; nothing from it survives in this directory or in the shipped one.

## How these are made — the script is the source of truth

`scripts/generate_quiz_imagery.py` holds the prompt wording in two constants:

- **`REFERENCE_PROMPT`** — generates `_reference-figure.png`, one canonical headless man in a
  plain mid-grey base layer, on the seamless warm mid-grey studio backdrop.
- **`EDIT_SKELETON`** — wrapped around every garment clause and sent to OpenAI's
  `/v1/images/edits` **with that reference figure attached**. Its first sentence instructs the
  model to keep the same man, the same skin tone, the same framing and the same backdrop, and to
  change only the clothing.

**This file deliberately does not reproduce the skeleton.** It used to, and a copied prompt in a
README drifts from the one that actually runs — at which point the document is worse than nothing,
because it reads authoritative. Read the constants.

Every one of the 28 shipped frames came out of that edit path, from that one figure. The reason
that matters, and the measured result, are in
`ios/AstraStyle/Resources/QuizImagery/README.md` — the short version is that the person is no
longer a variable anywhere in the instrument, and backdrop drift inside a pair fell from 20.9 mean
luma on the old vendor to 1.6.

`--all` covers 16 pairs, two per axis. 14 are shipped; `logo-1` and `silhouette-2` were rejected
and are blocked on an OpenAI billing hard limit, with fixed prompts already committed. Both
rejections are documented in full in the shipped directory's README.

## What is in here

| File(s) | What it is |
|---|---|
| `_reference-figure.png` | The canonical figure every other frame is edited from. Do not regenerate it casually — a new figure is a new man, and every existing frame would disagree with the new one. |
| 28 frames for the 14 shipped pairs | `<axis>-<n>-<a\|b>.png`, 1024×1536. These are the sources for everything in `ios/AstraStyle/Resources/QuizImagery/`. |
| `logo-1-a.png` | Kept; its partner `logo-1-b.png` was **deleted** for returning a real trademark ("HILFIGER") across the chest. The pair does not ship. |
| `silhouette-2-a.png`, `silhouette-2-b.png` | Rejected, kept as candidates: the B frame came back short-sleeved against a long-sleeved A, putting sleeve length in a pair meant to isolate volume. Not in the manifest, so nothing can render them. |
| `bakeoff-2026-07-31*.png` | Contact sheets from the vendor bake-off, retained as `docs/16`'s evidence. Not sources and not shipped. |

**`quiz-imagery-review.html` has been removed.** It rendered the first six candidates as quiz
cards in the dark palette and named files that no longer exist. Judging a tile at tile size is
still the right instinct — build the pair and look at the JPEGs in the shipped directory, which is
what the app actually reads.

## Known issues

1. **Backdrop tone still drifts between generations, by much less.** Reference-conditioned editing
   holds it far better than text-to-image did: 1.6 mean and 3.0 worst-case luma within a pair,
   against 20.9 mean and 33.7 worst on the old vendor and 13.9 mean on OpenAI text-to-image
   (`docs/16` §3.2). **Normalising in post remains mandatory rather than optional** —
   `scripts/build_quiz_imagery.py` does it and no pair ships without it, which brings the residual
   to 0.8 or less. The brighter frame is the more appealing photograph regardless of what it
   shows, and small is not zero. The seed route was never available on the old vendor (it rejected
   the parameter) and has not been tested on OpenAI; it is also now largely moot, since the
   reference holds the backdrop better than a pinned seed plausibly would.
2. **The chin and neck can be in frame** despite the prompt. The top 7% crop lives in the asset
   pipeline unconditionally, not in a per-image judgement call, because the cost of being wrong is
   asymmetric: a frame that ships uncropped shows a face the quiz promised not to.
3. **Hands were checked at full resolution across the set** — correct finger counts, no melted
   joints. That is a property of this batch, not of the model, and it is the first thing to
   re-check on any new generation.
4. **Asking this model for a wordmark makes it reach for a real brand.** It returned "HILFIGER"
   once and a circled "G" reading as a luxury house's mark on an earlier attempt. The logo axis is
   carried by abstract, letterless emblems for that reason.

## Cost shape

These are **static assets generated once**, not per-user generations. At OpenAI's medium tier for
portrait 1024×1536 on `gpt-image-2` — **$0.041 a frame** — the 28 shipped frames plus the
reference figure came to **about $1.20**, and the whole job including the two rejected pairs to
roughly $1.30. Medium because `docs/16` §3.4 found high indistinguishable from it on the decisive
prompt; 1024×1536 because the pipeline crops and resizes to 720px wide, so anything larger is
thrown away before it ships.

**Do not optimise this number.** The entire spread between the cheapest and most expensive
plausible way of finishing the quiz is a couple of dollars, one time, while a single confounded
pair that ships costs a wrong reading on a style axis for every user who answers it. Spend the
regeneration; check the hands.

Style Studio's per-user generation (spec §6.17) is a separate budget and a separate pipeline; do
not conflate the two when estimating. That one is per user, per month, indefinitely, and it is
where the per-image price genuinely decides things — see `docs/11` risk 5.
