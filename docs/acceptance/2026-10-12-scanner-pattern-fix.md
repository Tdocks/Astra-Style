# Scanner pattern/background correction — 2026-10-12

The frozen baseline was 38/48 correct pattern predictions (79.17%). The
changes define the garment region, explicitly exclude patterned backgrounds,
and distinguish colored checks/prints from fabric texture. No color/pattern
labels or acceptance thresholds were changed to improve a score. The original
vest annotation remains in the baseline so before/after comparisons match.

The first deployed revision (closet v27) clarified both the system prompt and
pattern schema. The follow-up requires a short visual description of the
inside-garment motif before the enum choice; this evidence is provider-internal
and does not change the client DTO or app UI. Verification results are recorded
below when the live runs finish.

Eight additional, previously unscanned photos from the same CC0 dataset were
selected and labeled before requests. See
`fixtures/vision-pilot/pattern-heldout-2026-10-12/manifest.json`. They cover small
chest graphics, a large floral graphic, a plain white shirt, plaid, checked
shorts, denim on a patterned rug, and two jackets. This held-out set was not
used to select the general pattern definitions. Its small size and subjective
color/formality annotations limit conclusions about release-wide accuracy.

## Revision history

- v26 baseline: pattern 79.17% (38/48), failed.
- v27 instruction/schema definitions: original pattern 83.33% (40/48), still
  failed. Additional-set pattern 91.67% (22/24), but its complete quality gate
  failed color and repeatability checks. These unsuccessful results are retained.
- v28 evidence-first schema: targeted four failing garments, two fresh runs
  each, 8/8 pattern predictions correct; median 4.512 seconds. This prompted a
  complete original/additional-set rerun, not a declaration of success from
  the targeted cases alone.

Detailed intermediate results are in the adjacent first-revision and targeted
JSON evidence files. The additional set's color failures include off-white/ivory
versus the pre-labeled white/cream family, and burgundy versus pink/white on a
multicolored checked shirt. The harness intentionally retains its original
literal color scoring; those discrepancies should not be described as proven
background contamination. A future independent color benchmark should define
color-family equivalence before calls. The plain shirt's formality disagreement
is likewise a subjective anchor disagreement. Pattern thresholds are unchanged.

## Complete v28 verification

Original set: pattern 87.5% (42/48), above 85%, but pass/fail pattern
repeatability 18.75% missed the 15% bar. Category was 97.92%, below 98% because
one long coat/cardigan was labeled top rather than outerwear. Color 97.92%,
subtype 91.67%, formality 93.75% and p50 4.494 seconds met their thresholds.
The complete original gate failed; its result is preserved unchanged.

Additional set: pattern 100% (24/24), with zero pattern verdict changes.
Category and subtype were 100%, p50 4.646 seconds. The complete additional-set
gate nevertheless failed literal color accuracy (79.17%) and color repeatability
(50%). Four of its five color mismatches were off-white versus the frozen
white/cream labels; one was dark green versus black on checked shorts. These
are reported separately from pattern/background accuracy. Formality was 91.67%.

Residual original pattern errors were concentrated in the small polo logo,
fine coat/cardigan weave, and ordinary leather creases. v29 clarifies dominant
body patterns, isolated logos, houndstooth, and leather grain/creases. This is a
general taxonomy clarification, with no observed-value remapping or label edits.

## Consistency enforcement

The instruction-only v29 targeted pass still failed difficult weave/leather
cases. Its nine observations are retained in the detail-targeted JSON file.
The final provider includes a narrow deterministic taxonomy check over its
foreground-only evidence. It corrects explicit camouflage/plaid/herringbone
contradictions, isolated small logos on otherwise plain bodies, and ordinary
leather creases/grain. Conflicting motifs, negations and descriptions mentioning
backgrounds cannot force a foreground pattern. Embossing, braiding, perforation,
knits and other named decorative structures are preserved.

Corrections add pattern to fields_below_confidence_threshold, so the client asks
for review. No image IDs or expected benchmark labels enter this logic. No
category/color/formality prediction or benchmark threshold is remapped. The
provider-internal visual evidence is neither returned to clients nor logged.
Six focused tests cover positive cues, negatives/backgrounds, genuine textured
footwear, conflicting cues and propagation of the review flag. Together with
schema/handler regression, 33 tests pass. Deployed closet v30 retains JWT checks.

## Final additional-set result (v30)

Pattern 100% (24/24), with 0% pattern verdict disagreement. Category and subtype
100%; p50 4.235s and p95 5.921s. All provider requests succeeded and the fixture
images/account were removed and independently checked absent.

Its complete multi-attribute gate still fails: literal color 87.5% (21/24) and
color verdict disagreement 25% exceed their bars. Formality is 87.5%, passing.
This is not an all-fields pass. Pattern/background checks pass, while color
family naming and the dark-green/black shorts annotation require separate
validation. No labels or bars were changed to hide these misses.

## Final original-set result (v30)

The same 16 original photographs and frozen labels were run three times each.
All 48 live requests succeeded, and readback confirmed the temporary storage
folder empty and fixture account absent. The additional set likewise completed
all 24 calls and cleanup. The temporary credential file was removed after both
runs. No iOS code or build changed; production closet v30 is active with JWT checks.

| Measurement | Original baseline v26 | Final original v30 | Bar | Final outcome |
|---|---:|---:|---:|---|
| Pattern | 79.17% (38/48) | 85.42% (41/48) | ≥85% | Pass |
| Pattern verdict disagreement | 12.5% | 6.25% | ≤15% | Pass |
| Category | 100% | 97.92% (47/48) | ≥98% | Fail |
| Subcategory | 93.75% | 91.67% | ≥80% | Pass |
| Primary color | 100% | 97.92% | ≥90% | Pass |
| Formality within ±15 | 97.92% | 97.92% | ≥85% | Pass |
| End-to-end p50 | 4.407s | 4.408s | ≤5.5s | Pass |
| End-to-end p95 | 6.252s | 6.869s | No approved bar | Diagnostic |

The pattern-specific gate passes both datasets: original 85.42% and additional
100% (24/24), with pattern verdict disagreement 6.25% and 0% respectively.
The broader scanner quality gate does **not** pass. One original category
prediction classified the long coat/cardigan as a top; at this small sample
size, one miss is 97.92%, just below 98%. The additional set separately fails
literal color accuracy/repeatability as documented above.

The previously failing camouflage T-shirt, plaid flannel, geometric shirt and
printed shorts now have correct pattern values in every final repetition.
Residual original pattern misses are one small polo logo, the fine-patterned
coat/cardigan in all three runs, and the creased black boot in all three runs
(the latter two were labeled print). The conservative evidence check does not
remap those ambiguous print descriptions into a guessed solid/check label. These
remain real open taxonomy/recognition cases, rather than being removed from the
sample. Category/formality truth for the coat/cardigan and color-family scoring
need separate adjudication; no expected labels were altered in this comparison.

No readiness claim follows from a marginal pass on 16 garments. The public-photo
sample does not close the master-plan real-device or consented user-photo gate.

## Coat/cardigan, color and boot consistency pass — deployed v31

Added construction/length guidance distinguishing substantial long coatigans from lightweight
cardigans, and a category consistency check for explicit coat/coatigan/blazer/jacket subtypes.
Category corrections are marked for user review. Primary color now uses dominant garment body
area, with stable white aliases for off-white/ivory; checks use base area rather than bright stripes.
Boot consistency checks now also reconcile print with ordinary leather creases, while preserving
explicit floral/animal/colored motifs and decorative textures. No benchmark labels changed.

35 regression tests passed; lint and diff checks passed. Deployed closet v31, JWT enabled.

| Measurement | Original (48 scans) | Additional (24 scans) |
|---|---:|---:|
| Category | 100% | 100% |
| Subcategory | 93.75% | 100% |
| Primary color | 93.75% | 100% |
| Pattern | 91.67% | 100% |
| Formality within ±15 | 97.92% | 87.5% |
| p50 | 5.030s | 4.513s |
| p95 | 7.787s | 5.457s |
| Full configured benchmark gate | **Pass** | **Pass** |

Both runs completed without provider errors, and uploaded photos and disposable users were removed.
Safe full reports: `2026-10-12-scanner-consistency-original.json` and
`2026-10-12-scanner-consistency-heldout.json`.

The coat/cardigan category now passes all three repeats. Boot pattern improved from 0/3 to 2/3.
Residual errors remain: coatigan pattern is still print in 3/3 rather than the frozen check/textured
label; boot pattern is print in 1/3; ivory/cream blazer is consistently white in 3/3, exposing an
over-broad white alias decision. The benchmark gate passes its predeclared thresholds, but these
individual cases are not completely resolved. The vest subtype annotation mismatch remains
separately documented. Public-photo evidence does not close the real-device/user-photo pilot.
No native build was required; changes remain uncommitted.

## Warm-color and embroidered-boot pass — deployed v32

Direct reinspection identified a faulty coat pattern annotation: the visible garment has
repeating ornamental loops/medallions, not a check. This was identified before the v32 calls.
The frozen manifest remains unchanged. Separate adjudication is recorded in
`2026-10-12-scanner-pattern-adjudication.json`; never compare its revised 100% pattern accuracy
as though the original benchmark labels stayed identical. Original frozen pattern accuracy is 93.75%.

Removed the ivory-to-white alias that caused the cream blazer regression. Clarified neutral white
versus warm ivory/cream, small monochrome boot embroidery versus dominant body pattern, and
ornamental motifs versus checks. Image requests explicitly use high detail. No photo IDs,
benchmark labels, or filenames are sent to the provider.

35 regression tests pass; lint and diff checks pass. Closet v32 is deployed with JWT enabled.
The same 24 photos were each scanned three times (72 live requests), no provider errors.
All disposable uploads/users were removed and the temporary credential file deleted.

| Measurement | Original frozen (48) | Additional (24) |
|---|---:|---:|
| Category | 97.92% | 100% |
| Subcategory | 91.67% | 100% |
| Primary color | 100% | 95.83% |
| Pattern, frozen labels | 93.75% | 100% |
| Formality within ±15 | 95.83% | 87.5% |
| p50 | 4.552s | 4.319s |
| p95 | 6.992s | 6.128s |
| Full frozen benchmark gate | **Fail: category** | **Pass** |

Requested cases: coat pattern print 3/3 (visually appropriate); cream blazer ivory/cream 3/3;
boot solid 3/3. Coat outerwear category also passes 3/3. These targeted cases are resolved in
this run, not a guarantee for all future photos. One separate geometric shirt (image 6) was
classified as a blazer in 1/3, narrowly failing the ≥98% category bar. Two formality readings
missed their ±15 labels but the aggregate formality bar passes. The checked shorts have one
dark-green versus black color disagreement. No full readiness claim.

Full reports: `2026-10-12-scanner-detail-original.json` and
`2026-10-12-scanner-detail-heldout.json`. Backend-only changes; no TestFlight build required.

## Shirt versus blazer — deployed v33

Added private construction evidence before category in the strict provider schema: visible
collar, placket, cuffs, hem, pockets and lining/structure. The prompt distinguishes an open
shirt collar from tailored blazer lapels and forbids inferring jacket construction from
ornate fabric or hanging shape alone. This evidence is not returned/stored in the app DTO.
No benchmark labels changed, no photo-specific rules or IDs passed to the provider.

36 regression tests passed; lint and diff checks passed. Closet v33 deployed with JWT enabled.
Same 24 photos × 3 repeats = 72 live scans. The previously failing patterned shirt (image 6)
was correctly categorized as top/button-up shirt in 3/3 repeats. Boot solid and cream/ivory
blazer color also pass 3/3. Both full frozen benchmark gates now pass.

| Measurement | Original (48 scans) | Additional (24 scans) |
|---|---:|---:|
| Category | 100% | 100% |
| Subcategory | 89.58% | 100% |
| Primary color | 100% | 95.83% |
| Pattern, frozen labels | 91.67% | 100% |
| Formality within ±15 | 97.92% | 87.5% |
| p50 | 4.935s | 4.643s |
| p95 | 8.275s | 6.012s |
| Full configured gate | **Pass** | **Pass** |

No provider errors; disposable uploads and users cleaned up; temporary credential file
deleted. Raw reports: `2026-10-12-scanner-construction-original.json` and
`2026-10-12-scanner-construction-heldout.json`. Previously documented coat pattern annotation
issue is preserved, not quietly changed to obtain a pass. Aggregate pass allows individual
subcategory, pattern and color misses; this limited public-photo pilot does not establish
real-world/user-photo accuracy or replace physical-camera verification. Changes uncommitted;
no native build required.
