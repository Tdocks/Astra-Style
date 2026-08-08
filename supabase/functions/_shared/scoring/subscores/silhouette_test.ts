import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { type FitNote, silhouetteSubscore } from "./silhouette.ts";
import type { Fit, ScorableItem } from "../types.ts";

function garment(
  id: string,
  role: ScorableItem["role"],
  fit: Fit | null,
  materials: string[] = [],
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
    materials,
    formalityScore: null,
    fit,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
  };
}

const pair = (topFit: Fit, bottomFit: Fit) =>
  silhouetteSubscore([garment("t", "top", topFit), garment("b", "bottom", bottomFit)]).value;

Deno.test("Uniform slim and tailored read as a silhouette; uniform oversized does not", () => {
  // §4.1's |d|=0 row is the only one that varies by fit, and this is why:
  // slim on slim is a shape, oversized on oversized is a duvet.
  assertAlmostEquals(pair("slim", "slim"), 0.90, 1e-9);
  assertAlmostEquals(pair("tailored", "tailored"), 0.90, 1e-9);
  assertAlmostEquals(pair("regular", "regular"), 0.85, 1e-9);
  assert(pair("relaxed", "relaxed") < 0.7);
  assert(pair("oversized", "oversized") < 0.6);
});

Deno.test("A looser top over a tighter bottom beats the same volumes reversed", () => {
  // THE ASYMMETRY. Menswear proportion does not commute: an oversized knit over
  // slim trousers is a look someone chose; slim top over oversized bottom reads
  // as clothes that do not fit. A regression to a symmetric table would still
  // pass most of the other tests in this file.
  const volumeOnTop = pair("oversized", "slim");
  const volumeOnBottom = pair("slim", "oversized");
  assert(
    volumeOnTop > volumeOnBottom,
    `looser-on-top ${volumeOnTop} should beat looser-on-bottom ${volumeOnBottom}`,
  );
});

Deno.test("Regular top with relaxed bottom is not penalised — it is what men wear", () => {
  // §4.2 carves out d = −1 deliberately. Penalising it would mark down half of
  // everyday casual dressing.
  const ordinary = pair("regular", "relaxed");
  assertAlmostEquals(ordinary, 0.90, 1e-9);
});

Deno.test("One step of gradation is the sweet spot", () => {
  assertAlmostEquals(pair("tailored", "regular"), 0.90, 1e-9);
  assert(pair("tailored", "regular") > pair("tailored", "relaxed"));
});

Deno.test("Direction only applies to top–bottom, not to outerwear or shoes", () => {
  // Outerwear is conventionally looser than what it covers whichever way round
  // you read it, and a shoe's fit is not a volume axis.
  const a = silhouetteSubscore([
    garment("o", "outerwear", "oversized"),
    garment("t", "top", "slim"),
  ]).value;
  const b = silhouetteSubscore([
    garment("o", "outerwear", "slim"),
    garment("t", "top", "oversized"),
  ]).value;
  assertAlmostEquals(a, b, 1e-9);
});

Deno.test("A missing fit is unjudged rather than penalised, and says so", () => {
  const score = silhouetteSubscore([garment("t", "top", null), garment("b", "bottom", "slim")]);
  assertAlmostEquals(score.value, 0.75, 1e-9);
  assertEquals(score.degraded.length, 1);
  assert(score.degraded[0]!.includes("unjudged"));
});

Deno.test("broad_chest dampens a slim rigid top and exempts a stretch one", () => {
  const rigid = silhouetteSubscore(
    [garment("t", "top", "slim", ["cotton"]), garment("b", "bottom", "slim")],
    ["broad_chest"],
  ).value;
  const stretch = silhouetteSubscore(
    [garment("t", "top", "slim", ["cotton", "elastane stretch"]), garment("b", "bottom", "slim")],
    ["broad_chest"],
  ).value;
  assert(rigid < stretch, `rigid ${rigid} should be dampened below stretch ${stretch}`);
  assertAlmostEquals(stretch, pair("slim", "slim"), 1e-9);
});

Deno.test("large_thighs dampens a slim rigid bottom, and leaves a slim top alone", () => {
  // Each outfit is compared against ITSELF without the fit note. Comparing the
  // two outfits to each other — which the first draft of this test did — is
  // measuring §4.2's directional adjustment instead: a regular top over slim
  // trousers earns +0.08 while a slim top over regular trousers takes −0.10,
  // and that 0.18 swing swamps the 0.85 modifier under test.
  const slimBottom = [garment("t", "top", "regular"), garment("b", "bottom", "slim", ["denim"])];
  const slimTop = [garment("t", "top", "slim", ["cotton"]), garment("b", "bottom", "regular")];

  const bottomPlain = silhouetteSubscore(slimBottom).value;
  const bottomNoted = silhouetteSubscore(slimBottom, ["large_thighs"]).value;
  assertAlmostEquals(bottomNoted, bottomPlain * 0.85, 1e-9);

  // No §4.3 rule reads a slim TOP for large thighs, so the note changes nothing.
  const topPlain = silhouetteSubscore(slimTop).value;
  const topNoted = silhouetteSubscore(slimTop, ["large_thighs"]).value;
  assertAlmostEquals(topNoted, topPlain, 1e-9);
});

Deno.test("Body modifiers can only ever dampen — never lift a score", () => {
  // A values decision as much as a modelling one: an engine that rewarded a
  // garment for a man's chest measurement would be scoring the man. Every
  // multiplier in §4.3 is ≤ 1, and this asserts it across the whole fit matrix.
  const fits: Fit[] = ["slim", "tailored", "regular", "relaxed", "oversized"];
  const allNotes: FitNote[] = ["broad_chest", "short_torso", "long_legs", "large_thighs"];
  for (const topFit of fits) {
    for (const bottomFit of fits) {
      const plain = silhouetteSubscore([
        garment("t", "top", topFit, ["cotton"]),
        garment("b", "bottom", bottomFit, ["cotton"]),
      ]).value;
      const modified = silhouetteSubscore(
        [garment("t", "top", topFit, ["cotton"]), garment("b", "bottom", bottomFit, ["cotton"])],
        allNotes,
      ).value;
      assert(
        modified <= plain + 1e-9,
        `${topFit}/${bottomFit}: modifiers lifted ${plain} to ${modified}`,
      );
    }
  }
});

Deno.test("The two uncomputable fit rules are reported, not silently skipped", () => {
  // A man who told onboarding about a short torso and gets no adjustment for it
  // should not have the app behave as though he never said so. No column stores
  // garment length or break, so the rule cannot run — and says so.
  const score = silhouetteSubscore(
    [garment("t", "top", "relaxed"), garment("b", "bottom", "slim")],
    ["short_torso", "long_legs"],
  );
  assert(score.degraded.some((d) => d.includes("short_torso")));
  assert(score.degraded.some((d) => d.includes("long_legs")));
});

Deno.test("Every fit combination stays inside [0,1]", () => {
  const fits: Fit[] = ["slim", "tailored", "regular", "relaxed", "oversized"];
  for (const a of fits) {
    for (const b of fits) {
      const value = pair(a, b);
      assert(value >= 0 && value <= 1, `${a}/${b} produced ${value}`);
    }
  }
});
