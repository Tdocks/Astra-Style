// ============================================================================
// studio/promptBuilder.ts
// ============================================================================
// The structured prompt builder — spec §13's template, assembled from the
// same `closet_items` attributes that drive compatibility scoring, never a
// free-text re-description of the outfit (`docs/08` §8.2). Assembled ONCE
// per generation, stored in `prompt_payload` before submission, submitted
// verbatim; a §21 retry replays the stored string, it never re-assembles.
//
// The §13 template is preserved sentence-for-sentence, with two additions
// that are part of the vendor decision record (`docs/08` §3.5), not
// optional polish — both fix failures that were MEASURED, not guessed:
//
// 1. CUT IS A SENTENCE SUBJECT, NOT A BURIED ADJECTIVE. `docs/15` §3b:
//    with "wide-leg" as one adjective among four garments, 2 of 18 images
//    honoured it; with cut as the sentence's subject, all of them did.
//    `docs/14`'s FitRules reason entirely on the cut axis — if Studio
//    cannot render slim versus wide, Kyra's advice sits beside a picture
//    that contradicts it. So each garment's fit also gets its own
//    "The cut of the X is Y." sentence.
//
// 2. A COLOUR-SATURATION GUARD. `docs/15` §2: every one of this model's
//    garment-accuracy misses was the same failure — desaturation toward
//    black (navy rendered black, forest green near-black). Naming the trap
//    explicitly fixed it at no cost to identity.
//
// The advanced controls (formality / season / palette / preset) append
// sentences AFTER the template's scene sentence and BEFORE its closing
// disclaimer, so the template's own sentences keep their §13 order. The
// palette clause is explicitly scoped to lighting/setting mood: garment
// colour comes from `closet_items.primary_color` and must render as
// specified — a palette control that recoloured a red sweater would
// contradict the exact-garments principle the whole feature stands on.
// ============================================================================

import type { StudioGarment } from "../_shared/providers/imageGeneration.ts";

/**
 * §11's labelling guardrail as a constant: the disclaimer is part of the
 * prompt AND stored on every `studio_generations` row at creation
 * (`prompt_payload.disclaimer`), so "every generated image is labeled" is
 * a structural guarantee, not a per-screen discipline.
 */
export const STUDIO_DISCLAIMER =
  "The image is a visual styling estimate, not an exact representation of garment fit or color.";

export interface StudioPromptControls {
  /** `StudioPose` raw values from the wire; unknown values take the default. */
  readonly pose: string;
  /** `StudioBackground` raw values from the wire; unknown values take the default. */
  readonly background: string;
  readonly preset?: string;
  readonly formality?: string;
  readonly season?: string;
  readonly colorPalette: readonly string[];
  readonly preserveFace: boolean;
  readonly preserveBodyProportions: boolean;
  readonly preserveHair: boolean;
}

// Documented defaults — the acceptance criterion is that a missing or
// unknown optional parameter falls back HERE rather than leaving a literal
// "[pose]" placeholder in the prompt.
const DEFAULT_POSE = "a relaxed, front-facing standing pose, arms at ease";
const DEFAULT_BACKGROUND = "a minimalist charcoal studio backdrop with a soft gradient";
const DEFAULT_LIGHTING = "soft, even editorial lighting";

const POSE_FRAGMENTS: Record<string, string> = {
  standing_front: DEFAULT_POSE,
  standing_three_quarter:
    "a three-quarter standing pose, weight on the back foot, hands relaxed at his sides",
  walking: "a walking candid pose, mid-stride, slight turn toward camera",
  seated: "a seated pose, relaxed posture, three-quarter angle",
};

const BACKGROUND_FRAGMENTS: Record<string, string> = {
  studio: DEFAULT_BACKGROUND,
  editorial_outdoor: "an outdoor editorial setting in soft, overcast daylight",
  urban: "a warm-lit city street at dusk with soft background bokeh",
  neutral: "a plain neutral backdrop with no props",
};

// There is no client-side lighting control (spec §6.17's advanced controls
// stop at season), so the template's [lighting] slot is derived from the
// season when one is chosen and defaults otherwise.
const SEASON_LIGHTING_FRAGMENTS: Record<string, string> = {
  spring: "soft spring daylight",
  summer: "bright summer daylight",
  fall: "crisp autumn daylight",
  winter: "cool, low winter daylight",
  all_season: DEFAULT_LIGHTING,
};

const FORMALITY_FRAGMENTS: Record<string, string> = {
  very_casual: "relaxed, off-duty ease",
  casual: "casual and unforced",
  balanced: "smart casual, elevated but unstructured",
  formal: "polished, business-ready structure",
  very_formal: "formal eveningwear precision",
};

// Spec §6.17's eight presets. A preset is a styling direction appended to
// the scene — it never overrides an explicit control the user set.
const PRESET_FRAGMENTS: Record<string, string> = {
  smart_casual: "smart casual, elevated but unstructured",
  date_night: "date night, refined and intimate evening styling",
  wedding: "wedding guest, celebratory and polished",
  vacation: "vacation, relaxed warm-weather ease",
  executive: "executive, boardroom-ready authority",
  old_money_inspired: "old-money inspired, quiet heritage tailoring",
  minimalist: "minimalist, clean lines and deliberate restraint",
  night_out: "night out, sharp and confident evening energy",
};

function describeGarment(garment: StudioGarment): string {
  const fit = garment.fit.trim();
  const pattern = garment.pattern.trim();
  const patternFragment = pattern.length > 0 && pattern !== "solid" ? `, ${pattern}` : "";
  const material = garment.material.filter((m) => m.trim().length > 0).join("/");
  const materialFragment = material.length > 0 ? `, ${material}` : "";
  const fitFragment = fit.length > 0 ? `${fit} ` : "";
  const colorFragment = garment.colorDescription.trim().length > 0
    ? `${garment.colorDescription.trim()} `
    : "";
  return `${garment.role}: ${fitFragment}${colorFragment}${garment.normalizedTitle}` +
    `${patternFragment}${materialFragment}`;
}

/** `docs/15` §3b's rule: cut as the sentence's subject, one per garment. */
function cutSentences(garments: readonly StudioGarment[]): string[] {
  return garments
    .filter((garment) => garment.fit.trim().length > 0)
    .map((garment) => `The cut of the ${garment.normalizedTitle} is ${garment.fit.trim()}.`);
}

/**
 * §13 sentence 2, with the advanced controls' preserve toggles applied.
 * The mapping: "facial features" and "skin tone" ride the face toggle,
 * "body proportions" the body toggle, "hair, and facial hair" the hair
 * toggle. All-off drops the sentence entirely rather than emitting
 * "Preserve the person's ." — but the wire defaults every toggle to true,
 * so the full spec sentence is the overwhelmingly common case.
 */
function preserveSentence(controls: StudioPromptControls): string | null {
  const aspects: string[] = [];
  if (controls.preserveFace) {
    aspects.push("recognizable facial features");
  }
  if (controls.preserveBodyProportions) {
    aspects.push("body proportions");
  }
  if (controls.preserveFace || controls.preserveBodyProportions) {
    aspects.push("skin tone");
  }
  if (controls.preserveHair) {
    aspects.push("hair", "facial hair");
  }
  if (aspects.length === 0) {
    return null;
  }
  const last = aspects.pop() as string;
  const list = aspects.length > 0 ? `${aspects.join(", ")}, and ${last}` : last;
  return `Preserve the person's ${list}.`;
}

const COLOR_GUARD =
  "Keep every garment color true and fully saturated: navy stays navy, not black; " +
  "deep greens stay green, not near-black.";

export function buildStudioPrompt(
  garments: readonly StudioGarment[],
  controls: StudioPromptControls,
): string {
  const garmentList = garments.map(describeGarment).join("; ");
  const pose = POSE_FRAGMENTS[controls.pose] ?? DEFAULT_POSE;
  const background = BACKGROUND_FRAGMENTS[controls.background] ?? DEFAULT_BACKGROUND;
  const lighting = controls.season !== undefined
    ? SEASON_LIGHTING_FRAGMENTS[controls.season] ?? DEFAULT_LIGHTING
    : DEFAULT_LIGHTING;

  const optionalClauses: string[] = [];
  const formality = controls.formality !== undefined
    ? FORMALITY_FRAGMENTS[controls.formality]
    : undefined;
  if (formality !== undefined) {
    optionalClauses.push(`Styling formality: ${formality}.`);
  }
  const preset = controls.preset !== undefined ? PRESET_FRAGMENTS[controls.preset] : undefined;
  if (preset !== undefined) {
    optionalClauses.push(`Styling direction: ${preset}.`);
  }
  const palette = controls.colorPalette.map((entry) => entry.trim()).filter((entry) =>
    entry.length > 0
  );
  if (palette.length > 0) {
    optionalClauses.push(
      `Overall color mood of the lighting and setting (not garment recoloring): ${
        palette.join(", ")
      }.`,
    );
  }

  return [
    "Create a realistic editorial menswear visualization using the provided authorized reference image.",
    preserveSentence(controls),
    `Dress him in: ${garmentList}.`,
    ...cutSentences(garments),
    `Use ${pose}, ${background}, and ${lighting}.`,
    COLOR_GUARD,
    ...optionalClauses,
    STUDIO_DISCLAIMER,
  ].filter((sentence): sentence is string => sentence !== null).join(" ");
}
