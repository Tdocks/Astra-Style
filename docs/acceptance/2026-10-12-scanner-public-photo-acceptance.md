# Hosted scanner public-photo pilot — 2026-10-12

**Result: completed, quality gate failed.** All 48 authenticated live requests
succeeded through the deployed `closet` function v26. No provider credentials
were extracted from Supabase; the scanner used its existing configured provider.

Sixteen real photos came from [Alexey Grigorev's CC0 Clothing Dataset](https://github.com/alexeygrigorev/clothing-dataset).
The frozen manifest, images, license and selection explanation are in
`fixtures/vision-pilot/public-sample-2026-10-12/`. Labels were assigned by visual
inspection before calls. The test sent only photographs, without label/category
or OCR hints. Three unique requests per garment measure variation rather than
cached idempotent replay. These 48 observations represent 16 garments, not 48
independent samples.

| Measurement | Original result | Threshold | Outcome |
|---|---:|---:|---|
| Category | 100% (48/48) | 98% | Pass |
| Subcategory | 93.75% (45/48) | 80% | Pass; annotation issue below |
| Primary color | 100% (48/48) | 90% | Pass |
| Pattern | 79.17% (38/48) | 85% | Fail |
| Formality within ±15 | 97.92% (47/48) | 85% | Pass |
| End-to-end p50 | 4.407 seconds | ≤5.5 seconds | Pass |
| End-to-end p95 | 6.252 seconds | No approved p95 bar | Diagnostic |

Pass/fail verdict disagreement across repetitions: category 0%, subtype 0%,
color 0%, pattern 12.5%, formality 6.25%; each falls below the proposed 15%
ceiling. Raw subtype wording varied for 68.75% of photos; this is separately
recorded and does not mean the garment class changed.

## Findings

- Image 02: camouflage/graphic T-shirt on a checked background → `check` in all
  three runs, despite subtype descriptions recognizing camouflage. Background
  isolation and explicit pattern vocabulary need attention.
- Image 05: red/black plaid flannel → `textured` in all three runs.
- Image 06: small repeating geometric/check print → `textured` in two runs.
- Image 09: geometric printed swim shorts → `textured` in two runs.
- Image 11: the original contact-sheet annotation called this a jacket. Full-size
  inspection confirms a sleeveless hooded vest; all three model descriptions are
  reasonable. Retain the original score and document the correction rather than
  changing the benchmark silently. Correcting this annotation would make subtype
  accuracy 100%; it does not repair the pattern failure.
- Image 15: one formality score was 45 versus the subjective 65 anchor. Treat this
  as a judgment disagreement, not a proven objective recognition bug.

The deployed mapper matches local code (`check` maps to `check`, `print` to
`print`, herringbone/texture-only to `textured`), so the pattern misses are not
caused by a stale deployed mapping table. No prompt or model was tuned during
this run. The next measured change should clarify garment-vs-background focus
and distinguish colored prints/checks from fabric texture, using a held-out
sample to avoid overfitting these photographs.

## Scope and cleanup

`scripts/run_hosted_vision_pilot.py` uploaded to a disposable authenticated user's
private folder, called the real scanner without hints, and removed all uploaded
objects and the fixture account. Service-role readback confirmed the folder
empty and the auth account absent (404). The temporary credential file was
deleted. No actual customer account was used or modified.

Detailed safe observations: `2026-10-12-scanner-public-photo-results.json`.
The current harness exits 1 for a completed quality failure, 2 for an incomplete
run or failed cleanup, and 0 only when the recorded thresholds pass.

This is a small convenience sample with mixed garment genders, independently
judged color/pattern/formality and no brand/material truth. It demonstrates a
real failure worth fixing; it does not prove release-wide accuracy, replace
phone camera/lighting tests, or close the master-plan consented user-photo gate.
