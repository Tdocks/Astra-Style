import { assert, assertAlmostEquals } from "@std/assert";
import { silhouetteSubscore } from "./silhouette.ts";
import { silhouetteSubscoreWomenswear } from "./silhouette_womenswear.ts";
import type { Fit, ScorableItem } from "../types.ts";

function garment(
  id: string,
  role: ScorableItem["role"],
  fit: Fit | null,
): ScorableItem {
  return {
    id,
    category: role === "accessory" ? "accessory" : role,
    role,
    primaryColor: null,
    isNeutral: false,
    secondaryColors: [],
    pattern: null,
    patternScale: null,
    materials: [],
    formalityScore: null,
    fit,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
  };
}

Deno.test("menswear silhouette is unchanged for a top-bottom pair", () => {
  const items = [garment("t", "top", "slim"), garment("b", "bottom", "slim")];
  assertAlmostEquals(
    silhouetteSubscore(items).value,
    silhouetteSubscoreWomenswear(items).value,
    1e-9,
  );
});

Deno.test("women's module scores a dress-shoes pair", () => {
  const items = [garment("d", "dress", "regular"), garment("s", "shoes", "regular")];
  const score = silhouetteSubscoreWomenswear(items);
  assert(score.value > 0.5);
});
