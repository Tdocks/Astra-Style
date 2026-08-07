# `daily-brief`

Serves spec §14's `POST /daily-brief/generate` — the data behind §6.11, Kyra's Daily Brief. Ticket
`P4-HOME-02`.

|            |                                                                    |
| ---------- | ------------------------------------------------------------------ |
| Slug       | `daily-brief`                                                      |
| Routes     | `POST /generate`                                                   |
| Auth       | `verify_jwt: true`; the JWT is the only source of identity         |
| Rate limit | 10/min per user, in-isolate (best effort, not a security boundary) |
| Deployed   | 2026-08-06, `anutsdzbxycaavmmkewo`                                 |

```bash
supabase functions deploy daily-brief --project-ref anutsdzbxycaavmmkewo
```

## Request

```json
{
  "request_id": "…",
  "client_version": "ios/1.0.0",
  "body": {
    "date": "2026-08-06",
    "regenerate": false,
    "weather_snapshot": {
      "temperature_high": 68,
      "temperature_low": 54,
      "condition": "partly_cloudy"
    }
  }
}
```

`weather_snapshot` is optional and, when present, must match the client's own `WeatherSnapshot`
shape (`temperature_high`/`temperature_low` numbers, a known `condition` string — see `schema.ts`'s
`parseWeatherSnapshot`). Omit it, or send `null`, when the client has no weather reading to offer.

`date` is the caller's local calendar day and is matched strictly against `YYYY-MM-DD`, then
re-checked for being a real day. `new Date(value)` would accept `2026-13-45`, `2026-8-6` and a full
ISO timestamp, and each of those lands in a different row of a table whose uniqueness constraint is
`(user_id, brief_date)` — a sloppy parse is how one user ends up with several briefs for one day,
none of which the next request finds.

## What it does

1. Returns the stored brief for that day unless `regenerate` is true.
2. Reads wearable `closet_items` and scores them with `_shared/scoring/leastRecentlyWorn.ts`.
3. **Persists the outfits as real `outfits` + `outfit_items` rows**, then writes the brief
   referencing them.
4. Upserts `daily_briefs` on `(user_id, brief_date)`.

### Step 3 is the one that surprises people

`daily_briefs.primary_outfit_id` is a foreign key into `outfits`. The ids that
`POST /outfits/generate` hands back are minted per request and stored nowhere, so a brief built from
that endpoint's output would be rejected by the database. This function therefore writes the outfits
itself.

### Idempotency is enforced twice

`handler.ts` reads the existing brief first, and the write is an upsert on the table's own unique
constraint. The read alone is a race: two requests that both miss it would otherwise have one
succeed and one fail on the constraint.

## What it deliberately does not produce

Spec §14 lists weather and a Kyra-authored message among this endpoint's inputs.

- **`weather_snapshot` is whatever the client sent, or null.** There is still no server-side weather
  provider — `P4-HOME-05` wired the client's own `WeatherService` (WeatherKit) into
  `HomeBriefProviding`, which now passes its reading up in the request body rather than this
  endpoint looking one up itself. `null` when the client had none to offer (permission not yet
  granted, denied, or the lookup failed) is still the honest, and common, answer — this endpoint
  never invents a forecast to fill the column, and rejects a populated-but-malformed one rather than
  storing it (see `schema.ts`'s `parseWeatherSnapshot`).
- **`kyra_message` is null.** The scorer behind these outfits returns one identical hardcoded
  `reason` for every outfit it builds, so a "Kyra's insight" module fed from it would be the same
  sentence every day, dressed as a judgement. `HomeView` already renders that module only when the
  message is present.

Both columns are `jsonb NOT NULL DEFAULT '{}'` / nullable text, so the response DTO maps an **empty
object to `null`** on the way out — the client decodes these into `WeatherSnapshot?`, whose
non-optional fields cannot be built from `{}`, and a present-but-empty object makes the whole
`DailyBrief` decode _throw_ on the device rather than degrade to nil. `DailyBrief`'s hand-written
`init(from:)` closes the same hole on the Postgrest read path, which never sees this DTO.

## Known gap

A regenerate leaves the previous brief's generated outfits active and unreferenced. Nothing surfaces
them today (`P4-OUTFIT-11` is Not started). The right policy is probably to archive the unworn ones
and keep the worn ones for `outfit_wears` history — but that is easier to settle against a screen
than in the abstract, so it is recorded rather than guessed at.
