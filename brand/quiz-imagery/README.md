# Style quiz imagery — candidate set

Six generations evaluating whether AI imagery is viable for the §6.9 preference quiz.
**Not yet approved.** Nothing here is wired into the app.

## What was generated

**This batch, 2026-07-28:** Higgsfield Soul 2.0 (`text2image_soul_v2`), 1536×2048, style
"General", `enhance_prompt: false`. Kept as provenance for the six files below, not as an
instruction — that vendor was dropped on 2026-07-31 (`docs/16` §3.5) and nothing new goes to it.

**New frames go to OpenAI `gpt-image-2`** — text-to-image, portrait 1024×1536, medium quality,
called directly against OpenAI's API with our own key. Medium because `docs/16` §3.4 found high
indistinguishable from it on the decisive prompt; 1024×1536 because the pipeline crops the top 7%
and resizes to 720px wide, so anything larger is thrown away before it ships. The prompt skeleton
below does not change with the vendor — it is the part that must never move.

| File | Axis | Reads as | Job ID |
|---|---|---|---|
| `formality-a.jpg` | Formality | Tailored — navy blazer, white shirt, grey trouser, cap-toe derby | `a64afae4-d99a-4613-a35c-9f1ef439b8b1` |
| `formality-b.jpg` | Formality | Relaxed — washed sweatshirt, olive chino, canvas sneaker | `37eccb69-66fd-4be2-9d37-528a09b1c3ea` |
| `colour-a.jpg` | Colour tolerance | Quiet — oatmeal, stone, tan | `2ec0a137-b3be-40ef-9410-f5b8e20f79b4` |
| `colour-b.jpg` | Colour tolerance | Saturated — burgundy, forest, cognac | `7a7d5e98-e794-4546-9e2b-4caf6f8adb12` |
| `silhouette-a.jpg` | Silhouette | Close — slim tapered, no break, chelsea boot | `7326aee2-ac12-49ce-a346-a7814402cb0b` |
| `silhouette-b.jpg` | Silhouette | Loose — oversized cardigan, wide-leg, chunky sneaker | `fc1dc5b8-adb6-4d32-9c0c-2f94a834930b` |

Open `quiz-imagery-review.html` to see all six rendered as the actual quiz card in the dark
palette. That is the view to judge from — a generated frame that looks fine at full size can
fall apart at tile size, and the reverse.

## Why these three axes

They are the ones that actually discriminate between men's style profiles. Asking someone to
choose between two navy blazers tells you nothing; asking whether they'd wear burgundy with
forest green tells you a great deal. Occasion, budget, and brand affinity are better asked as
text — they don't need a picture and a picture makes them slower to answer.

## Prompt discipline

Every frame uses an identical skeleton and varies only the garment clause:

> Editorial menswear outfit photograph on a seamless warm mid-grey studio backdrop, even soft
> directional lighting from upper left. Full body framed from the shoulders down to the shoes,
> no face visible, model centered and standing straight, arms relaxed at sides. Wearing
> **{garments}**. **{quality descriptor}**. Neutral catalog styling, no props, no text, no logos.
> Shot on 85mm, f8, full-length studio fashion photography.

This is the whole point. If one option is lit more flatteringly, shot from a better angle, or
happens to have a nicer background, the user picks the *photograph* and the quiz records it as a
*style preference*. The answer is then wrong in a way nothing downstream can detect — a bad
Style DNA that looks like a valid one. Any future additions must reuse this skeleton verbatim.

## Known issues in this batch

1. **Backdrop tone drifts between generations.** `formality-a` reads warmer than `colour-b`.
   Side by side in a pair it is faintly visible. Two fixes were proposed here originally — pin
   the backdrop seed, or normalise in post. **Normalising in post is the one that happens, and it
   is mandatory rather than optional:** `scripts/build_quiz_imagery.py` does it, and no pair
   ships without it. Drift on this batch averaged 20.9 luma and reached 33.7; OpenAI measured
   13.9 mean on the same metric (`docs/16` §3.2) — better, and still visible side by side. The
   seed route is **untested on OpenAI**: Soul 2.0 rejected the parameter outright, but nobody has
   checked whether OpenAI accepts a seed or whether one would actually hold the backdrop, so do
   not assume either way.
2. **Faces are present in the source files** — the chin and neck are in frame despite the
   prompt. The quiz tile crops the top 7% to remove them, which means *the crop is load-bearing*
   and has to live in the asset pipeline, not in a per-image judgement call.
3. Hands were checked at full resolution across all six. Correct finger counts, no melted
   joints. The usual generated-fashion tell is absent in this batch — but it is the first thing
   to re-check on any new generation, not something to assume holds.

## Cost shape

These are **static assets generated once**, not per-user generations. A full quiz at spec §6.9
length needs roughly 16–20 frames; finishing from what has shipped is 12–28 more. At OpenAI's
medium tier for portrait 1024×1536 — **$0.041 a frame** — the whole remaining job is **about a
dollar, once** (`docs/16` §3.5 prices it, including what the same frames would have cost through
a reseller: about four dollars).

**Do not optimise this number.** The entire spread between the cheapest and most expensive
plausible way of finishing the quiz is a few dollars, one time, while a single confounded pair
that ships costs a wrong reading on a style axis for every user who answers it. Spend the
regeneration; check the hands.

Style Studio's per-user generation (spec §6.17) is a separate budget and a separate pipeline; do
not conflate the two when estimating. That one is per user, per month, indefinitely, and it is
where the per-image price genuinely decides things — see `docs/11` risk 5.
