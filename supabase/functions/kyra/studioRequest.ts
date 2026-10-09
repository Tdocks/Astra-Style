import { badRequest } from "../_shared/errors.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION } from "../studio/schema.ts";
import type {
  ConsentedStudioReference,
  StudioPreviewSelection,
} from "./tools/generateStudioPreview.ts";

/** Translate the public tool's options to the existing Studio API without
 * silently downgrading resolution or pretending unsupported options exist.
 */
export function studioRequestBody(
  selection: StudioPreviewSelection,
  reference: ConsentedStudioReference,
): Record<string, unknown> {
  if (selection.resolution !== "draft") {
    throw badRequest("High-resolution previews are not available yet. Choose a draft preview.");
  }
  if (reference.termsVersion !== CURRENT_STUDIO_CONSENT_TERMS_VERSION) {
    throw badRequest("Confirm the current Studio photo terms before generating.");
  }
  const backgrounds: Readonly<Record<string, string>> = {
    "studio-neutral": "studio",
    studio: "studio",
    neutral: "neutral",
    urban: "urban",
    editorial_outdoor: "editorial_outdoor",
  };
  const background = Object.hasOwn(backgrounds, selection.background)
    ? backgrounds[selection.background]
    : undefined;
  if (!background) throw badRequest("Choose a Studio, neutral, urban or outdoor background.");
  const poses = {
    standing: "standing_front",
    walking: "walking",
    "three-quarter": "standing_three_quarter",
  };
  return {
    reference_image_path: reference.path,
    ...(selection.outfitId
      ? { outfit_id: selection.outfitId }
      : { ad_hoc_item_ids: selection.itemIds }),
    background,
    pose: poses[selection.pose],
    preserve_face: true,
    preserve_body_proportions: true,
    preserve_hair: true,
    consent: { acknowledged: true, terms_version: reference.termsVersion },
  };
}
