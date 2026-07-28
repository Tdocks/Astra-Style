// ============================================================================
// _shared/requestId.ts
// ============================================================================
// Spec §14: "Log request ID and latency." `AstraAPIClient.performOnce`
// (ios/AstraStyle/Core/Networking/AstraAPIClient.swift) generates a UUID
// once per call, sends it as both the `X-Request-Id` header and the
// `request_id` field of the JSON envelope body, and uses its own local copy
// to tag `AstraError`s regardless of what the server echoes back. We prefer
// the header (cheapest to read, available even if the body fails to parse)
// and fall back to a body-supplied id, then to a freshly generated one so
// every request — even a malformed one — gets a request id to log against.
// ============================================================================

export function resolveRequestId(req: Request, bodyRequestId?: string | null): string {
  const header = req.headers.get("x-request-id") ?? req.headers.get("X-Request-Id");
  if (header && header.trim().length > 0) {
    return header.trim();
  }
  if (bodyRequestId && bodyRequestId.trim().length > 0) {
    return bodyRequestId.trim();
  }
  return crypto.randomUUID();
}
