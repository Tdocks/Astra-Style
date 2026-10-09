import { badRequest } from "../_shared/errors.ts";
import { isUUID } from "../_shared/validation.ts";

export function parseSubmissionKey(raw: string | null): string | null {
  if (raw === null) return null;
  if (!isUUID(raw)) throw badRequest("Idempotency-Key must be a UUID.");
  return raw.toLowerCase();
}
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).filter(([, v]) => v !== undefined)
        .sort(([a], [b]) => a.localeCompare(b)).map(([key, v]) => [key, canonical(v)]),
    );
  }
  return value;
}
export async function submissionFingerprint(body: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(canonical(body)));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
