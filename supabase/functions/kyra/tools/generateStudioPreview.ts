import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import { generateStudioPreviewDefinition as previewSchema } from "./phase6Stubs.ts";
import { AppError } from "../../_shared/errors.ts";
import { isUUID } from "../../_shared/validation.ts";
import { type PendingStudioConfirmation, studioGenerationConfirmed } from "./studioConfirmation.ts";

export interface StudioPreviewSelection {
  outfitId: string | null;
  itemIds: readonly string[];
  referenceImageId: string;
  pose: "standing" | "walking" | "three-quarter";
  background: string;
  resolution: "draft" | "hi_res";
}
export interface ConsentedStudioReference {
  path: string;
  termsVersion: string;
}
export interface GenerateStudioPreviewDeps {
  userText: string;
  pending: PendingStudioConfirmation | null;
  currentConsentTermsVersion: string;
  resolveOwnedConsentedReference(id: string): Promise<ConsentedStudioReference | null>;
  /** This service must validate owned outfit/items, enforce quota and deduplicate
   * the approved selection within the current turn before enqueuing a job.
   */
  enqueue(selection: StudioPreviewSelection, reference: ConsentedStudioReference): Promise<{
    generationId: string;
    status: "queued" | "generating" | "complete" | "failed";
    estimatedSeconds: number;
  }>;
}

export function parseStudioPreview(args: Record<string, unknown>): StudioPreviewSelection | null {
  if (!isUUID(args.reference_image_id)) return null;
  const outfitId = args.outfit_id ?? null;
  const items = args.item_ids ?? [];
  if (outfitId !== null && !isUUID(outfitId)) return null;
  if (!Array.isArray(items) || items.length > 12 || !items.every(isUUID)) return null;
  if ((outfitId !== null) === (items.length > 0)) return null;
  const pose = args.pose ?? "standing";
  const resolution = args.resolution ?? "draft";
  const background = args.background ?? "studio-neutral";
  if (
    typeof pose !== "string" || !["standing", "walking", "three-quarter"].includes(pose) ||
    typeof resolution !== "string" || !["draft", "hi_res"].includes(resolution) ||
    typeof background !== "string" || !background.trim() || background.length > 200
  ) return null;
  return {
    outfitId: outfitId as string | null,
    itemIds: [...new Set(items as string[])].sort(),
    referenceImageId: args.reference_image_id,
    pose: pose as StudioPreviewSelection["pose"],
    resolution: resolution as StudioPreviewSelection["resolution"],
    background: background.trim(),
  };
}

export function studioSelectionKey(selection: StudioPreviewSelection): string {
  return JSON.stringify([
    selection.referenceImageId,
    selection.outfitId,
    selection.itemIds,
    selection.pose,
    selection.background,
    selection.resolution,
  ]);
}

export async function executeGenerateStudioPreview(
  args: Record<string, unknown>,
  deps: GenerateStudioPreviewDeps,
): Promise<Record<string, unknown>> {
  const selection = parseStudioPreview(args);
  if (!selection) {
    return {
      error: "INVALID_ARGUMENTS",
      detail: "Choose one owned outfit or a list of closet items and one saved reference photo.",
    };
  }
  if (!studioGenerationConfirmed(deps.userText, studioSelectionKey(selection), deps.pending)) {
    return {
      error: "CONFIRMATION_REQUIRED",
      detail:
        "Ask whether the user wants this preview and explain that it uses their generation allowance. Wait for confirmation of this exact selection.",
    };
  }
  const reference = await deps.resolveOwnedConsentedReference(selection.referenceImageId);
  if (!reference || reference.termsVersion !== deps.currentConsentTermsVersion) {
    return {
      error: "NO_CONSENTED_REFERENCE_IMAGE",
      detail:
        "Open Studio to confirm a saved reference photo and the current photo-consent terms before generating.",
    };
  }
  try {
    const job = await deps.enqueue(selection, reference);
    return {
      generation_id: job.generationId,
      status: job.status,
      estimated_seconds: job.estimatedSeconds,
    };
  } catch (error) {
    if (error instanceof AppError && error.status < 500) {
      return {
        error: error.status === 429
          ? "QUOTA_EXCEEDED"
          : error.status === 409
          ? "PREVIEW_REQUEST_CONFLICT"
          : "PREVIEW_UNAVAILABLE",
        detail: error.message,
      };
    }
    throw error;
  }
}

export const generateStudioPreviewDefinition: StylistToolDefinition = {
  ...previewSchema,
  description:
    "Queue a draft Studio preview using an owned outfit or closet items and a saved consented reference photo. Explain that it uses the generation allowance and obtain confirmation for the exact selection. Return missing consent or quota outcomes honestly; never invent a generation ID. High-resolution previews are not available yet.",
};
