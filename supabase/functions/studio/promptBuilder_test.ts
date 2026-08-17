// ============================================================================
// studio/promptBuilder_test.ts
// ============================================================================
// P6-STUDIO-05's acceptance criteria, as runnable assertions:
//   - the assembled prompt matches the spec §13 template with placeholders
//     correctly substituted (exact-string test, not a vibe check);
//   - missing optional parameters fall back to documented defaults rather
//     than leaving a literal placeholder in the prompt.
// Plus the two measured prompt rules from docs/08 §3.5 that are part of
// the vendor decision: the colour-saturation guard and cut-as-subject.
// ============================================================================

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import type { StudioGarment } from "../_shared/providers/imageGeneration.ts";
import {
  buildStudioPrompt,
  STUDIO_DISCLAIMER,
  type StudioPromptControls,
} from "./promptBuilder.ts";

const GARMENTS: StudioGarment[] = [
  {
    role: "top",
    normalizedTitle: "crewneck sweater",
    colorDescription: "navy",
    material: ["merino wool"],
    pattern: "solid",
    fit: "regular",
  },
  {
    role: "bottom",
    normalizedTitle: "chino trousers",
    colorDescription: "stone",
    material: ["cotton twill"],
    pattern: "solid",
    fit: "tapered",
  },
];

function controls(overrides: Partial<StudioPromptControls> = {}): StudioPromptControls {
  return {
    pose: "standing_three_quarter",
    background: "studio",
    colorPalette: [],
    preserveFace: true,
    preserveBodyProportions: true,
    preserveHair: true,
    ...overrides,
  };
}

Deno.test("assembled prompt matches the spec §13 template exactly, placeholders substituted", () => {
  const prompt = buildStudioPrompt(
    GARMENTS,
    controls({ formality: "balanced", season: "fall", colorPalette: ["tonal neutrals"] }),
  );
  assertEquals(
    prompt,
    "Create a realistic editorial menswear visualization using the provided authorized reference image. " +
      "Preserve the person's recognizable facial features, body proportions, skin tone, hair, and facial hair. " +
      "Dress him in: top: regular navy crewneck sweater, merino wool; bottom: tapered stone chino trousers, cotton twill. " +
      "The cut of the crewneck sweater is regular. " +
      "The cut of the chino trousers is tapered. " +
      "Use a three-quarter standing pose, weight on the back foot, hands relaxed at his sides, " +
      "a minimalist charcoal studio backdrop with a soft gradient, and crisp autumn daylight. " +
      "Keep every garment color true and fully saturated: navy stays navy, not black; deep greens stay green, not near-black. " +
      "Styling formality: smart casual, elevated but unstructured. " +
      "Overall color mood of the lighting and setting (not garment recoloring): tonal neutrals. " +
      STUDIO_DISCLAIMER,
  );
});

Deno.test("missing optional parameters take documented defaults, never a literal placeholder", () => {
  const prompt = buildStudioPrompt(GARMENTS, controls({ pose: "??", background: "??" }));
  // The template's own bracket placeholders must never survive assembly.
  assert(!prompt.includes("["));
  assert(!prompt.includes("]"));
  assertStringIncludes(prompt, "a relaxed, front-facing standing pose, arms at ease");
  assertStringIncludes(prompt, "a minimalist charcoal studio backdrop with a soft gradient");
  // No season chosen → the default lighting, not an empty slot.
  assertStringIncludes(prompt, "and soft, even editorial lighting.");
});

Deno.test("the colour-saturation guard is always present (docs/15 §2's measured failure)", () => {
  const prompt = buildStudioPrompt(GARMENTS, controls());
  assertStringIncludes(prompt, "navy stays navy, not black");
});

Deno.test("cut is foregrounded as a sentence subject per garment (docs/15 §3b)", () => {
  const prompt = buildStudioPrompt(GARMENTS, controls());
  assertStringIncludes(prompt, "The cut of the chino trousers is tapered.");
  // A garment with no recorded fit gets no cut sentence — no fabricated cut.
  const unknownFit = buildStudioPrompt(
    [{ ...GARMENTS[0]!, fit: "" }],
    controls(),
  );
  assert(!unknownFit.includes("The cut of the crewneck sweater"));
});

Deno.test("preserve toggles drop their aspects from the §13 preserve sentence", () => {
  const noBody = buildStudioPrompt(
    GARMENTS,
    controls({ preserveBodyProportions: false }),
  );
  assertStringIncludes(
    noBody,
    "Preserve the person's recognizable facial features, skin tone, hair, and facial hair.",
  );
  const nonePreserved = buildStudioPrompt(
    GARMENTS,
    controls({ preserveFace: false, preserveBodyProportions: false, preserveHair: false }),
  );
  assert(!nonePreserved.includes("Preserve the person's"));
});

Deno.test("preset appends a styling direction; disclaimer stays the closing sentence", () => {
  const prompt = buildStudioPrompt(GARMENTS, controls({ preset: "old_money_inspired" }));
  assertStringIncludes(prompt, "Styling direction: old-money inspired, quiet heritage tailoring.");
  assert(prompt.endsWith(STUDIO_DISCLAIMER));
});

Deno.test("non-solid pattern is described; solid is not restated", () => {
  const prompt = buildStudioPrompt(
    [{
      role: "top",
      normalizedTitle: "oxford shirt",
      colorDescription: "blue",
      material: ["cotton"],
      pattern: "stripe",
      fit: "slim",
    }],
    controls(),
  );
  assertStringIncludes(prompt, "top: slim blue oxford shirt, stripe, cotton");
  const solid = buildStudioPrompt(GARMENTS, controls());
  assert(!solid.includes(", solid"));
});
