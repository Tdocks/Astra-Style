# `closet` Edge Function

Grouped function for every spec §14 path under `/closet/…` (ADR 0013):

| Method | Path remainder      | Handler                                               |
| ------ | ------------------- | ----------------------------------------------------- |
| `POST` | `/analyze-item`     | `handleAnalyzeItem` — idempotent single-item analysis |
| `POST` | `/batch-analyze`    | `handleBatchAnalyze` — enqueue only (HTTP 202)        |
| `GET`  | `/batch-status/:id` | `handleBatchStatus` — advance one item per poll       |

Deployed slug: `closet`. Client paths are `/functions/v1/closet/analyze-item`, etc.

## Vision provider gate (docs/08 §2.5)

`index.ts` is the **only** place that constructs a `VisionAnalysisProvider`.

| Env                                                                     | Effect                                                                             |
| ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| _(unset / default)_                                                     | `MockVisionAnalysisProvider` — deterministic, offline, what CI and local serve use |
| `VISION_ANALYSIS_PROVIDER=openai` **and** `VISION_PROVIDER_API_KEY` set | `OpenAIVisionAnalysisProvider` (`../_shared/providers/openaiVisionAnalysis.ts`)    |
| `VISION_PROVIDER_MODEL` (optional)                                      | Model id; defaults to `gpt-5.6`                                                    |

**The key is `VISION_PROVIDER_API_KEY` and this table used to say `OPENAI_API_KEY`.** That name is
in neither spec §25's per-capability scheme nor ADR 0004's vocabulary, and it was never set on the
project — so from the day this function shipped, every scan took the mock branch and confidently
returned "Top" for whatever it was shown. Nothing said so. If you are reading this because a scan
came back wrong, check `supabase secrets list` first.

### Flip to OpenAI for a pilot deploy

```bash
# Hosted project secrets (never commit keys)
supabase secrets set \
  VISION_ANALYSIS_PROVIDER=openai \
  VISION_PROVIDER_API_KEY=... \
  VISION_PROVIDER_MODEL=gpt-5.6

supabase functions deploy closet
```

Local serve:

```bash
VISION_ANALYSIS_PROVIDER=openai \
VISION_PROVIDER_API_KEY=... \
supabase functions serve closet
```

If `VISION_ANALYSIS_PROVIDER` is not `openai`, the function runs the mock quietly — that is a
deliberate choice, not a fault. If it **is** `openai` and `VISION_PROVIDER_API_KEY` is missing, the
function still falls back to the mock but now **logs at error level naming the missing variable**
before it does. Silence was the expensive part: a mock result is a plausible-looking category for a
garment nothing measured, which is the "confounded reading" CLAUDE.md's governing rule forbids.

### Pre-launch pilot gate checklist (must measure before real users)

Enabling the OpenAI adapter in a deploy does **not** satisfy the gate. Before closet-scan traffic
from real users uses GPT-5.6 Luna, run the checklist in **`docs/08-provider-abstraction.md` §2.5**,
in short:

1. **Define the accuracy bar** (product decision) for menswear subcategory granularity (e.g. knit
   polo vs. piqué polo vs. performance polo).
2. **Label a consented real-scan sample** and score Luna against that bar.
3. **If the bar fails:** default classification to Terra, or evaluate a dedicated
   fashion-classification vendor — and rerun `docs/09-model-routing.md` §5 cost model.
4. **Watch structured-output reliability** and calibrated brand-guess confidence (wrong
   high-confidence brand guesses are worse than low-confidence empties).
5. **Confirm data-retention / no-training API terms** for garment photos (spec §29) on the OpenAI
   account in use.

This environment has **not** run that pilot. Treat `VISION_ANALYSIS_PROVIDER=openai` as an operator
opt-in for internal measurement only until §2.5 is closed.

## Layout

- `index.ts` — wiring, provider selection, route table
- `handler.ts` — analyze-item + batch enqueue/poll (deps injected)
- `schema.ts` / `mapper.ts` — wire DTOs matching iOS `ClosetItemAnalysisResult`
- Tests: `handler_test.ts`, `schema_test.ts`
