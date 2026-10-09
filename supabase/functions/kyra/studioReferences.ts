import type { SupabaseClient } from "@supabase/supabase-js";
import { isUUID } from "../_shared/validation.ts";
import { serverError } from "../_shared/errors.ts";
import type { ConsentedStudioReference } from "./tools/generateStudioPreview.ts";

export interface StudioReferenceReads {
  savedPaths(): Promise<readonly string[]>;
  hasCurrentConsentReceipt(path: string, termsVersion: string): Promise<boolean>;
}

export interface CompletedInspirationRow {
  readonly id: string;
  readonly user_id: string;
  readonly status: string;
  readonly deleted_at: string | null;
  readonly retention_expires_at: string | null;
  readonly result_image_path: string | null;
  readonly prompt_payload: unknown;
}

export interface StudioInspirationReads {
  generation(id: string): Promise<CompletedInspirationRow | null>;
  signedImageURL(path: string): Promise<string | null>;
}

/** Resolve only an owned, live completed inspiration result to a short-lived image URL. */
export async function resolveCompletedStudioInspiration(
  userID: string,
  generationID: string,
  reads: StudioInspirationReads,
  expectedStorageOrigin: string,
  now: Date,
): Promise<{ readonly imageURL: string } | null> {
  if (!isUUID(userID) || !isUUID(generationID)) return null;
  const generation = await reads.generation(generationID);
  const mode = isRecord(generation?.prompt_payload) ? generation.prompt_payload["mode"] : null;
  const expectedPath =
    `users/${userID.toLowerCase()}/studio/${generationID.toLowerCase()}/result.png`;
  const retentionExpiry = generation?.retention_expires_at;
  const retentionIsCurrent = retentionExpiry === null || (
    typeof retentionExpiry === "string" &&
    Number.isFinite(Date.parse(retentionExpiry)) &&
    Date.parse(retentionExpiry) > now.getTime()
  );
  if (
    !generation || generation.id.toLowerCase() !== generationID.toLowerCase() ||
    generation.user_id.toLowerCase() !== userID.toLowerCase() ||
    generation.status !== "complete" || generation.deleted_at !== null ||
    !retentionIsCurrent ||
    (mode !== "inspiration" && mode !== "closet_inspiration") ||
    generation.result_image_path !== expectedPath
  ) return null;

  const imageURL = await reads.signedImageURL(generation.result_image_path);
  if (!imageURL) return null;
  let parsedURL: URL;
  try {
    parsedURL = new URL(imageURL);
  } catch {
    return null;
  }
  let expectedOrigin: string;
  try {
    expectedOrigin = new URL(expectedStorageOrigin).origin;
  } catch {
    return null;
  }
  let decodedPath: string;
  try {
    decodedPath = decodeURIComponent(parsedURL.pathname);
  } catch {
    return null;
  }
  const expectedObjectURLPath = `/storage/v1/object/sign/user-content/${expectedPath}`;
  return parsedURL.protocol === "https:" && parsedURL.origin === expectedOrigin &&
      decodedPath === expectedObjectURLPath && parsedURL.searchParams.has("token")
    ? { imageURL: parsedURL.toString() }
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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

export function buildStudioInspirationReads(
  supabase: SupabaseClient,
  userID: string,
): StudioInspirationReads {
  return {
    async generation(id) {
      const { data, error } = await supabase.from("studio_generations")
        .select(
          "id,user_id,status,deleted_at,retention_expires_at,result_image_path,prompt_payload",
        )
        .eq("id", id).eq("user_id", userID).is("deleted_at", null).maybeSingle();
      if (error) throw serverError("Couldn't verify this Studio image.");
      return data as CompletedInspirationRow | null;
    },
    async signedImageURL(path) {
      const { data, error } = await supabase.storage.from("user-content").createSignedUrl(
        path,
        300,
      );
      if (error) return null;
      const url = data?.signedUrl;
      return typeof url === "string" ? url : null;
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
