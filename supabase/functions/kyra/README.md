# `kyra`

Serves spec §14's `POST /kyra/respond` — the Kyra stylist orchestration endpoint (§6.20, §11),
designed in `docs/06-kyra-orchestration.md`. Tickets `P5-KYRA-02..12` and `P5-KYRA-19`.

|            |                                                                                 |
| ---------- | ------------------------------------------------------------------------------- |
| Slug       | `kyra`                                                                          |
| Routes     | `POST /respond`                                                                 |
| Auth       | `verify_jwt`; the JWT is the only source of identity                            |
| Rate limit | 10/min per user in-isolate burst + 3 conversations/day free tier (below)        |
| Deployed   | **Not yet.** Do not add `kyra` to `EndpointDeploymentMappingTests` until it is. |

```bash
supabase functions deploy kyra --project-ref <ref>
```

> `supabase/functions/deno.json`'s `check`/`test`/`fmt`/`lint` include lists predate this function
> and do not cover `kyra/` yet — adding `kyra/**` there is a one-line change this directory could
> not make for itself (it may only touch `kyra/`). Until then: `deno check kyra/**/*.ts` and
> `deno test --allow-env kyra/`.

## Environment

| Variable                               | Required | Notes                                                                                                                                                                   |
| -------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY`   | auto     | Injected by Supabase; never set manually                                                                                                                                |
| `STYLIST_PROVIDER_API_KEY`             | yes*     | Spec §25's name. Missing → every turn returns the in-voice "can't reach my tools" fallback (logged loudly at cold start). *The function runs without it; Kyra does not. |
| `STYLIST_PROVIDER_MODEL_LUNA`          | no       | Defaults `gpt-5.6-luna`                                                                                                                                                 |
| `STYLIST_PROVIDER_MODEL_TERRA`         | no       | Defaults `gpt-5.6-terra`                                                                                                                                                |
| `KYRA_FREE_DAILY_CONVERSATION_LIMIT`   | no       | Default 3 (spec §16); config value per P5-KYRA-19                                                                                                                       |
| `KYRA_CONFIDENCE_ESCALATION_THRESHOLD` | no       | Default 0.55 (docs/09 §2.1's launch default)                                                                                                                            |
| `KYRA_MEMORY_MINIMUM_CONFIDENCE`       | no       | Default 0.7 (docs/06 §5.2's explicit-statement bar)                                                                                                                     |

No service-role key. RLS with the caller's own JWT covers every table this function touches.

## Request

```json
{
  "request_id": "…",
  "client_version": "ios/1.0.0",
  "body": {
    "thread_id": null,
    "text": "What should I wear tonight?",
    "attachments": [{ "type": "closet_item", "value": "<uuid>" }],
    "weather_snapshot": { "temperature_high": 21, "temperature_low": 12, "condition": "rain" }
  }
}
```

`thread_id` absent starts a new conversation (this is what the free-tier daily limit counts).
`weather_snapshot` is optional and client-supplied — there is still no server-side weather provider,
by design (`daily-brief/README.md`); the `get_weather` tool reads this snapshot or honestly reports
unavailable. The shipped iOS `KyraRespondBody` does not send it yet; the field is accepted now so
the client can add it without a server change.

## Response

The `data` payload is the persisted assistant `kyra_messages` row, decoding into Swift's
`KyraMessage`: `id`, `thread_id`, `role: "assistant"`, `content`, `structured_payload`,
`model_metadata`, `created_at` (whole-second ISO-8601 — `_shared/time.ts`).

**The structured payload's contract is the shipped Swift client, not `docs/06` §4 — they disagree.**
`schema.ts`'s header inventories the differences (card discriminator `type` with five card kinds and
id-reference payloads; `{id,label,kind}` actions with `KyraSuggestedAction.Kind`'s seven values;
`{memory_type,content,confidence}` proposals using the Postgres `memory_type` enum). Where §4 wants
information the Swift shape lacks, it rides along as additive keys Codable ignores.

## What a turn does

1. JWT → burst limit → schema validation.
2. **Free-tier gate (P5-KYRA-19):** starting a new conversation counts `kyra_threads` rows created
   today (UTC) in Postgres — durable and client-tamper-proof, unlike the shared in-memory limiter,
   whose per-isolate minute-window shape would quietly reset on every cold start. That is why the
   daily limit is _not_ built on `_shared/rateLimit.ts`. Premium (`subscriptions` row in an entitled
   status) skips the gate.
3. Context packet (`contextPacket.ts`): docs/06 §1's budget (4,000 tokens, chars/4 heuristic),
   §1.3's truncation ladder implemented as an explicit ordered list, §1.4 occasion window, §1.5
   availability filter + category-balance backfill.
4. Orchestration loop: Luna by default, eleven tools declared, tool results fed back; one
   failed-tool retry with backoff, then an honest `TOOL_EXECUTION_FAILED` result the model must
   acknowledge.
5. Escalation (docs/09 §2): confidence `< 0.55` → one full Terra retry (§2.1); schema-invalid output
   → same-tier repair then Terra repair then safe fallback (§2.2, docs/06 §6); tool loop past 4
   iterations → Terra with history preserved, cap 6 (§2.3).
6. `memory_proposals` are rebuilt from what `save_preference` **actually wrote** — model claims
   without a matching write are discarded; writes are always surfaced.
7. Guardrails (`guardrails.ts`, P5-KYRA-12): enforced post-hoc validation, not prompt hope —
   medical/body-change and sensitive-trait content force an in-voice redirect; fit-certainty claims
   are rewritten + caveated + confidence-capped; unlabelled generated images and missing affiliate
   disclosures get the required sentence appended; sponsored-above-organic ordering is detected;
   cards referencing ids nothing surfaced this turn are dropped (the hallucinated-closet-item P1
   from docs/06 §7.3).
8. Both turns persist to `kyra_messages`; every failure past auth/limits/schema still returns a
   well-formed in-voice `KyraResponse` (docs/06 §6), never a raw error into the chat UI.

## Deliberately not built (recorded, not hidden)

- **Streaming.** `LiveStylistProvider.completeStream` throws per the protocol's instruction — the
  iOS `AstraAPIClient` has no SSE path to consume it. Spec §20's <2.5s first-card target is **not
  met** by this endpoint yet.
- **Embedding-based retrieval and memory dedup.** No `EmbeddingProvider` implementation exists and
  `closet_items.embedding` / `style_memories.embedding` are never written. Closet retrieval uses
  keyword relevance + rotation (documented in `contextPacket.ts`); memory dedup uses token-Jaccard +
  a polarity heuristic (documented in `tools/savePreference.ts`), with thresholds named for a
  drop-in upgrade.
- **docs/09 §2.4–§2.6 routing triggers and the Sol tier.** §2.4 needs analytics events the server
  does not receive; §2.6 gates a Phase-6 tool. The ladder is Luna → Terra, one hop.
- **Phase-6 tools** (`analyze_product`, `search_products`, `generate_studio_preview`):
  real input schemas, honest `NOT_BUILT` results (P5-KYRA-11). `create_packing_list` is
  live and calls the same `buildPlan` as `POST /packing/generate`.
- **Admin prompt-versions table (§28).** The §2 prompt is hardcoded with a version constant, same
  precedent as `style-dna`.

## Schema-forced deviations from docs/06 (need a decision or a migration)

- **No draft outfits.** §3.3's `source: "kyra_draft"` does not exist in the `outfit_source` enum and
  there is no `is_draft` column; `create_outfit` writes `source = 'kyra_suggested'` and says so.
- **No soft supersession.** §5.3 wants `superseded_by` on `style_memories`; the column does not
  exist. A contradicted memory is hard-deleted (the table's own documented deletion mode) and the
  change is surfaced in the same turn's `memory_proposals`.
- **One confidence floor for memories.** §5.2's split bars (0.7 explicit / 0.6-avg implicit) need an
  explicitness signal §3.9's tool schema does not carry; the 0.7 bar is enforced as the single
  floor.
- **§1.4's force-include of far-future referenced occasions** needs date NLU; the 14-day window is
  applied as-is.
