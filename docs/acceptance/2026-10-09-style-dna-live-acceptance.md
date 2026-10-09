# Style DNA live acceptance

**Date:** 2026-10-09  
**Route:** `POST /style-dna/generate`  
**Environment:** hosted Supabase project `anutsdzbxycaavmmkewo`  
**Provider model returned by the API:** `gpt-5.6-terra`

## Result

Three synthetic profile cases returned HTTP 200 and passed the same schema and
golden checks used by `style-dna/goldenEvaluation.ts`:

| Case | Verified behavior |
| --- | --- |
| No identity or other preferences | Identity remained `null`; color and silhouette stayed explicitly unknown; unsupported recommendations were empty; six open questions identified missing context. |
| Supplied `quiet_luxury` identity only | The selected identity was preserved; no secondary identity, color choice, fit preference, or purchase recommendation was inferred; silhouette stayed open; six questions named useful next inputs. |
| `luxury_streetwear` with a `creative` influence, relaxed fit, and versatile-wardrobe goal | Supplied identities were preserved; the relaxed-fit direction was acknowledged without claiming a precise fit; one goal-based priority was returned; six questions kept missing palette and wardrobe details explicit. |

The authenticated `/profile/export-data` route returned one caller-owned
`style_profiles` row for each account with its generated summary and formality
value. Normal `DELETE /account` returned 202 for all three fixtures; independent
SQL confirmed each deletion completed, cleared the owner reference, and left
zero auth, profile, Style DNA, body-profile, lifestyle-profile, Kyra-thread, or
wardrobe-snapshot rows.

The fixtures were disposable anonymous accounts. Their owner IDs were
`d957afc5-66c5-4ed7-b86c-964379e1435e`,
`3d58eb78-7be4-44ec-8d78-934ff94204ac`, and
`1cb0fc95-1de2-484d-ae59-bfbcf80fe417`; deletion IDs were
`a746f2aa-0ee3-47cc-afee-a57661c860b0`,
`846009f8-d974-42d0-a88f-76dbb47d40be`, and
`fc6fdad5-3168-48b3-8810-755aa5320b75`.

## Reliability changes and verification

The first live run showed that non-strict structured output could omit required
silhouette fields or emit an invalid formality enum. Style DNA now requests
provider-enforced strict structured output; Kyra's unrelated chat and tool
calls retain their existing non-strict mode. The prompt explicitly allows
empty recommendation lists and asks for a concise unknown when sparse input
cannot support a preference. Server-side validation remains in place before
anything is saved.

The local Style DNA and live-adapter suites passed **100 tests**. `deno check`,
`deno lint`, and `deno fmt --check` passed for the changed backend files.

## Scope and remaining limits

This acceptance verifies output structure, evidence-preserving sparse behavior,
model attribution, persistence, export, and deletion for synthetic text-only
profiles. It did not send reference photos or make image-generation requests.
It does not verify provider-account terms/configuration, which remains tracked
under the separate privacy/provider-terms work, or substitute for future
guardrail evaluation when the provider model or prompt changes.
