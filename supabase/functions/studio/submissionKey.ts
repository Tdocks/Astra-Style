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

/**
 * Cache identity for the actual, server-resolved render. Version this when
 * prompt assembly or the provider/model defaults change. Callers pass only
 * owned/resolved fields; transport keys and consent receipt metadata are not
 * part of visual identity.
 */
export async function generationCacheFingerprint(input: {
  userId: string;
  referenceImagePath: string;
  outfitId: string | null;
  provider: string;
  resolution: string;
  prompt: string;
  garments: unknown[];
  mode: string;
  context: string;
  instructions: string;
  itemIds: string[];
  controls: Record<string, unknown>;
  variationNonce?: string;
}): Promise<string> {
  return await submissionFingerprint({
    cache_version: "studio-render-v1",
    ...input,
  });
}
