import type { SupabaseClient } from "@supabase/supabase-js";
import { isUUID } from "../_shared/validation.ts";
import { serverError } from "../_shared/errors.ts";
import type { ConsentedStudioReference } from "./tools/generateStudioPreview.ts";

export interface StudioReferenceReads {
  savedPaths(): Promise<readonly string[]>;
  hasCurrentConsentReceipt(path: string, termsVersion: string): Promise<boolean>;
}

/** A stored filename UUID is the existing reference-photo identity (ADR 0026).
 * A current saved profile path and server-accepted consent receipt are both
 * required. No storage URL or arbitrary path supplied by a model is trusted.
 */
export async function resolveConsentedStudioReference(
  userID: string,
  referenceID: string,
  termsVersion: string,
  reads: StudioReferenceReads,
): Promise<ConsentedStudioReference | null> {
  if (!isUUID(userID) || !isUUID(referenceID)) return null;
  const path = `users/${userID.toLowerCase()}/references/${referenceID.toLowerCase()}.jpg`;
  if (!(await reads.savedPaths()).includes(path)) return null;
  if (!await reads.hasCurrentConsentReceipt(path, termsVersion)) return null;
  return { path, termsVersion };
}

export function buildStudioReferenceReads(
  supabase: SupabaseClient,
  userID: string,
): StudioReferenceReads {
  return {
    async savedPaths() {
      const { data, error } = await supabase.from("body_profiles").select("appearance")
        .eq("user_id", userID).maybeSingle();
      if (error) throw serverError("Couldn't load your saved Studio photos.");
      const paths = data?.appearance?.reference_selfie_paths;
      return Array.isArray(paths)
        ? paths.filter((path): path is string => typeof path === "string")
        : [];
    },
    async hasCurrentConsentReceipt(path, termsVersion) {
      const { data, error } = await supabase.from("studio_generations").select("id")
        .eq("user_id", userID).eq("reference_image_path", path).is("deleted_at", null)
        .contains("prompt_payload", {
          consent: { acknowledged: true, terms_version: termsVersion },
        })
        .limit(1);
      if (error) throw serverError("Couldn't verify this photo's Studio consent.");
      return (data?.length ?? 0) > 0;
    },
  };
}

/** Return identifiers only, never private paths or signed photo URLs. */
export async function listConsentedStudioReferenceIDs(
  userID: string,
  termsVersion: string,
  reads: StudioReferenceReads,
): Promise<string[]> {
  if (!isUUID(userID)) return [];
  const prefix = `users/${userID.toLowerCase()}/references/`;
  const candidates = [...new Set(await reads.savedPaths())].filter((path) =>
    path.startsWith(prefix) && path.endsWith(".jpg") &&
    isUUID(path.slice(prefix.length, -4))
  ).slice(0, 10);
  const accepted = await Promise.all(
    candidates.map(async (path) =>
      await reads.hasCurrentConsentReceipt(path, termsVersion)
        ? path.slice(prefix.length, -4)
        : null
    ),
  );
  return accepted.filter((id): id is string => id !== null);
}
