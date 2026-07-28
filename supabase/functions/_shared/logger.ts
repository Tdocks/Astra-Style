// ============================================================================
// _shared/logger.ts
// ============================================================================
// Structured, single-line JSON logging to stdout, which is where Supabase's
// Edge Function log drain collects output from (`supabase functions logs` /
// the dashboard's Logs Explorer). Spec §14 requires every endpoint to "log
// request ID and latency" and to "avoid logging private images or full
// prompt contents" — this module makes the safe path the easy path:
//
//   - Every log line is tagged with `request_id` automatically.
//   - Callers pass a flat `fields` object of already-safe-to-log values
//     (counts, ids, categories, status codes, latency) — there is no
//     "log the whole request body" helper here on purpose. Free-form user
//     text (e.g. `natural_language_request`) and anything image/URL-shaped
//     must never be passed to this logger; callers should log only its
//     length or a boolean "was provided", never its contents.
//   - `redactKeys` is a defense-in-depth denylist: if a field with one of
//     these names is ever accidentally passed in, its value is replaced
//     with a fixed marker instead of being printed, rather than trusting
//     every call site to remember not to.
// ============================================================================

export type LogFields = Record<string, string | number | boolean | null | undefined>;

const REDACTED_MARKER = "[redacted]";

/** Field-name denylist. Values under these keys are never logged verbatim. */
const REDACT_KEYS = new Set([
  "prompt",
  "natural_language_request",
  "naturalLanguageRequest",
  "image",
  "image_url",
  "imageUrl",
  "storage_path",
  "storagePath",
  "authorization",
  "access_token",
  "accessToken",
  "jwt",
]);

function redact(fields: LogFields): LogFields {
  const safe: LogFields = {};
  for (const [key, value] of Object.entries(fields)) {
    safe[key] = REDACT_KEYS.has(key) ? REDACTED_MARKER : value;
  }
  return safe;
}

export interface RequestLogger {
  info(event: string, fields?: LogFields): void;
  warn(event: string, fields?: LogFields): void;
  error(event: string, fields?: LogFields): void;
}

function write(
  level: "info" | "warn" | "error",
  requestId: string,
  event: string,
  fields: LogFields,
): void {
  const line = JSON.stringify({
    level,
    event,
    request_id: requestId,
    ts: new Date().toISOString(),
    ...redact(fields),
  });
  // Structured stdout/stderr logging is the intended use of console here —
  // this is the one place in the codebase allowed to call it, and only with
  // the pre-redacted `line` above (never raw request/user content).
  if (level === "error") {
    console.error(line);
  } else {
    console.log(line);
  }
}

export function createLogger(requestId: string): RequestLogger {
  return {
    info: (event, fields = {}) => write("info", requestId, event, fields),
    warn: (event, fields = {}) => write("warn", requestId, event, fields),
    error: (event, fields = {}) => write("error", requestId, event, fields),
  };
}
