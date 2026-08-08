// ============================================================================
// daily-brief/schema.ts
// ============================================================================
// Request parsing and the wire DTO for `POST /daily-brief/generate`
// (spec §14, P4-HOME-02).
//
// The body has NO user-id-shaped field, deliberately and for the same
// reason `outfits/schema.ts` has none: the only identity this endpoint
// recognises is the JWT's. There is nothing here for an attacker to
// substitute, rather than something checked after the fact.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";

export interface GenerateDailyBriefBody {
  /** Calendar day in the CALLER's local timezone, `YYYY-MM-DD`. */
  readonly briefDate: string;
  /**
   * Rebuild today's brief even though one already exists.
   *
   * P4-HOME-02's second acceptance criterion is that calling twice in one
   * day returns the same brief "unless explicitly regenerated", so the
   * distinction has to be something the caller states. Defaulting it to
   * false rather than inferring it from, say, a cache-control header keeps
   * the expensive path opt-in: a client that simply retries after a dropped
   * connection must not silently rebuild the day's outfits underneath a
   * user who is looking at them.
   */
  readonly regenerate: boolean;
  /**
   * The caller's own `WeatherService` reading (P4-HOME-05), or `null` when
   * weather permission was never granted or the lookup failed. There is no
   * server-side weather provider — see `README.md`'s "What it deliberately
   * does not produce" — so this is the only source `weather_snapshot` can
   * ever have. Validated, not merely passed through: a populated object
   * that does not match the client's `WeatherSnapshot` shape would decode
   * on the device and throw, per `DailyBrief.init(from:)`'s own comment on
   * why a malformed snapshot must not reach that column.
   */
  readonly weatherSnapshot: Record<string, unknown> | null;
}

/** Envelope every Astra client wraps its bodies in (`AstraRequestEnvelope`). */
export interface RequestEnvelope {
  readonly requestId?: string;
  readonly body: unknown;
}

function asRecord(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw badRequest(`${what} must be a JSON object.`);
  }
  return value as Record<string, unknown>;
}

export function parseEnvelope(raw: unknown): RequestEnvelope {
  const record = asRecord(raw, "Request");
  if (!("body" in record)) {
    throw badRequest("Request envelope must carry a `body` field.");
  }
  const requestId = record["request_id"];
  if (requestId !== undefined && typeof requestId !== "string") {
    throw badRequest("`request_id` must be a string when present.");
  }
  return { requestId: requestId as string | undefined, body: record["body"] };
}

// Deliberately stricter than `new Date(value)`. JavaScript will happily
// accept "2026-13-45", "2026-8-6" and a full ISO timestamp, and each of
// those would land in a different row of a table whose uniqueness
// constraint is `(user_id, brief_date)` — so a sloppy parse here is how a
// user ends up with several briefs for one day, none of which the next
// request finds.
const BRIEF_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/** Mirrors `WeatherCondition`'s raw values on the client exactly. */
const KNOWN_WEATHER_CONDITIONS = new Set([
  "clear",
  "partly_cloudy",
  "cloudy",
  "fog",
  "rain",
  "drizzle",
  "thunderstorm",
  "snow",
  "sleet",
  "windy",
]);

/**
 * Validates an optional client-supplied weather reading against the shape
 * `WeatherSnapshot.init(from:)` on the client actually decodes.
 *
 * Absent/`null` maps to `null` — "no forecast available" is the ordinary
 * case (permission not yet granted, or granted but the lookup failed) and
 * is not an error. A PRESENT object that does not match the shape IS
 * rejected rather than silently dropped: `DailyBrief.init(from:)`'s own
 * comment explains why a populated-but-malformed snapshot must never reach
 * the column — the client's decoder throws on it and takes the whole
 * brief down, which is worse than this request failing loudly instead.
 */
function parseWeatherSnapshot(raw: unknown): Record<string, unknown> | null {
  if (raw === undefined || raw === null) {
    return null;
  }
  const record = asRecord(raw, "`weather_snapshot`");

  const temperatureHigh = record["temperature_high"];
  const temperatureLow = record["temperature_low"];
  if (typeof temperatureHigh !== "number" || typeof temperatureLow !== "number") {
    throw badRequest("`weather_snapshot.temperature_high`/`temperature_low` must be numbers.");
  }

  const condition = record["condition"];
  if (typeof condition !== "string" || !KNOWN_WEATHER_CONDITIONS.has(condition)) {
    throw badRequest("`weather_snapshot.condition` must be a known weather condition.");
  }

  return record;
}

export function parseGenerateDailyBriefBody(raw: unknown): GenerateDailyBriefBody {
  const record = asRecord(raw, "`body`");

  const briefDate = record["date"];
  if (typeof briefDate !== "string" || !BRIEF_DATE_PATTERN.test(briefDate)) {
    throw badRequest("`date` must be a calendar day in YYYY-MM-DD form.");
  }
  // Reject a well-shaped string that is not a real day ("2026-02-31").
  const parsed = new Date(`${briefDate}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== briefDate) {
    throw badRequest("`date` is not a real calendar day.");
  }

  const regenerate = record["regenerate"];
  if (regenerate !== undefined && typeof regenerate !== "boolean") {
    throw badRequest("`regenerate` must be a boolean when present.");
  }

  const weatherSnapshot = parseWeatherSnapshot(record["weather_snapshot"]);

  return { briefDate, regenerate: regenerate === true, weatherSnapshot };
}

// ---------------------------------------------------------------------------
// Response DTO
// ---------------------------------------------------------------------------

/**
 * The wire shape of a `daily_briefs` row.
 *
 * This is NOT the raw row, and the difference is load-bearing.
 * `weather_snapshot` and `schedule_snapshot` are `jsonb NOT NULL DEFAULT
 * '{}'`, but the client decodes them into `WeatherSnapshot?` /
 * `ScheduleSnapshot?`, whose non-optional fields cannot be built from `{}`.
 * A row written with the schema's own defaults would therefore fail to
 * decode on the device — not degrade to nil, *throw* — so this function
 * maps an empty object to `null` on the way out and the client treats an
 * empty object as absent on the way in. Both halves, because
 * `fetchDailyBrief` reads the raw row over Postgrest and never sees this
 * DTO at all.
 */
export interface DailyBriefDTO {
  readonly id: string;
  readonly user_id: string;
  readonly brief_date: string;
  readonly primary_outfit_id: string | null;
  readonly alternative_outfit_ids: string[];
  readonly weather_snapshot: Record<string, unknown> | null;
  readonly schedule_snapshot: Record<string, unknown> | null;
  readonly kyra_message: string | null;
}

export interface DailyBriefRow {
  id: string;
  user_id: string;
  brief_date: string;
  primary_outfit_id: string | null;
  alternative_outfit_ids: unknown;
  weather_snapshot: unknown;
  schedule_snapshot: unknown;
  kyra_message: string | null;
}

function emptyObjectToNull(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  return Object.keys(record).length === 0 ? null : record;
}

export function mapBriefRowToWire(row: DailyBriefRow): DailyBriefDTO {
  return {
    id: row.id,
    user_id: row.user_id,
    brief_date: row.brief_date,
    primary_outfit_id: row.primary_outfit_id,
    alternative_outfit_ids: Array.isArray(row.alternative_outfit_ids)
      ? row.alternative_outfit_ids.filter((id): id is string => typeof id === "string")
      : [],
    weather_snapshot: emptyObjectToNull(row.weather_snapshot),
    schedule_snapshot: emptyObjectToNull(row.schedule_snapshot),
    kyra_message: row.kyra_message,
  };
}
