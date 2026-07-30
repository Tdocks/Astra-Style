// ============================================================================
// _shared/time.ts
// ============================================================================
// Every timestamp an Edge Function puts on the wire has to be decodable by
// the iOS client, and the client's decoder is stricter than it looks:
// `AstraAPIClient` sets `decoder.dateDecodingStrategy = .iso8601`, which is
// `ISO8601DateFormatter` with its DEFAULT options — `.withInternetDateTime`
// and nothing else. That formatter REJECTS fractional seconds.
//
// This matters because Postgres `timestamptz` has microsecond resolution and
// PostgREST serializes it faithfully: `2026-07-30T19:12:34.567891+00:00`.
// Handing that straight through produces a `DataCorrupted` decoding error on
// device for a response the server considers a complete success — a failure
// that no server-side test sees, that no HTTP status reflects, and that
// presents to the user as "something went wrong" on the last screen of
// onboarding.
//
// So every timestamp crossing this boundary is normalized here, in one
// place, to whole-second UTC: `2026-07-30T19:12:34Z`. Sub-second precision
// is not information any client of these endpoints uses.
//
// (Rows read through the Supabase Swift SDK's own PostgREST path do not come
// through here — that SDK brings its own decoder. This module is about the
// Edge Function response envelope specifically.)
// ============================================================================

/**
 * Formats a Postgres timestamp (or any parseable date value) as whole-second
 * ISO-8601 UTC, or returns null when the value is absent or unparseable.
 *
 * Unparseable input returns null rather than throwing: a timestamp the
 * server cannot read is a bad reason to fail a request whose actual work
 * succeeded, and every timestamp field on the wire that could take this path
 * is Optional on the Swift side.
 */
export function toIso8601Seconds(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== "string" && typeof value !== "number" && !(value instanceof Date)) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  const ms = date.getTime();
  if (Number.isNaN(ms)) {
    return null;
  }
  // `toISOString()` always emits exactly three fractional digits and a "Z";
  // dropping them is a string operation rather than arithmetic so it cannot
  // shift the second (truncation toward the epoch, matching how a whole-
  // second timestamp is conventionally read).
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/**
 * Same as `toIso8601Seconds`, for a field the client requires to be present
 * (a non-Optional Swift `Date`). Falls back to `fallback` — normally the
 * request's own clock reading — rather than emitting null into a field whose
 * decode would then throw.
 */
export function requireIso8601Seconds(value: unknown, fallback: Date): string {
  return toIso8601Seconds(value) ?? toIso8601Seconds(fallback) ?? fallback.toISOString();
}
