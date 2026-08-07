import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { formalityPairScore, formalitySubscore, outfitFormality } from "./formality.ts";
import type { ScorableItem } from "../types.ts";

function garment(id: string, role: ScorableItem["role"], formality: number | null): ScorableItem {
  return {
    id,
    category: role === "accessory" ? "accessory" : role,
    role,
    primaryColor: null,
    isNeutral: false,
    secondaryColors: [],
    pattern: null,
    patternScale: null,
    formalityScore: formality,
    fit: null,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
  };
}

// §2.3 / §3.1's worked example: olive knit polo 40, tailored chino 50,
// casual leather sneaker 22.
const POLO = garment("polo", "top", 40);
const CHINO = garment("chino", "bottom", 50);
const SNEAKER = garment("sneaker", "shoes", 22);

Deno.test("The doc's three pair scores reproduce, within its own rounding", () => {
  // §2.3's worked values: 0.875, 0.698, 0.417.
  //
  // The third needs a wider tolerance than the other two, and the difference is
  // the doc's arithmetic rather than ours: it writes (28/40)^1.5 = 0.583, where
  // the true value is 0.58566, giving 0.41434 against its 0.417. Two and a half
  // thousandths on a component weighted 0.20 is a quarter of a point on a
  // 100-point score. Recorded rather than smoothed over, because the next
  // person to check this by hand will hit the same gap.
  assertAlmostEquals(formalityPairScore(40, 50), 0.875, 0.001);
  assertAlmostEquals(formalityPairScore(40, 22), 0.698, 0.001);
  assertAlmostEquals(formalityPairScore(50, 22), 0.417, 0.003);
});

Deno.test("The doc's worked formality subscore of 0.71 reproduces", () => {
  // (0.35×0.875 + 0.20×0.698 + 0.20×0.417)/0.75 = 0.706
  const score = formalitySubscore([POLO, CHINO, SNEAKER]);
  assertAlmostEquals(score.value, 0.706, 0.002);
  assertEquals(score.degraded, []);
});

Deno.test("The penalty is super-linear, which is the entire design of §2.3", () => {
  // A small gap must cost almost nothing and a large one must cost nearly
  // everything. If this ever becomes linear, dress shoes with gym shorts start
  // scoring like a polo with a chino.
  const small = 1 - formalityPairScore(40, 45); // 5-point gap
  const large = 1 - formalityPairScore(40, 75); // 35-point gap
  assert(small < 0.05, `a 5-point gap should be barely felt, cost ${small}`);
  assert(large > 0.75, `a 35-point gap should be severe, cost ${large}`);

  // Compared against the LINEAR expectation rather than a number picked out of
  // the air. The gaps differ by 7× (5 → 35), so a linear penalty would cost 7×
  // as much; the exponent has to beat that by a clear margin or it is not doing
  // its job. The measured ratio is ~18.5×.
  const gapRatio = 35 / 5;
  assert(
    large / small > gapRatio * 2,
    `penalty ratio ${(large / small).toFixed(1)}× barely exceeds the linear ${gapRatio}×`,
  );
});

Deno.test("A 40-point gap zeroes, and nothing goes negative beyond it", () => {
  assertEquals(formalityPairScore(20, 60), 0);
  assertEquals(formalityPairScore(0, 100), 0);
  assert(formalityPairScore(0, 100) >= 0);
});

Deno.test("Identical formality scores 1", () => {
  assertEquals(formalityPairScore(50, 50), 1);
});

Deno.test("An unclassified garment uses its category default and says so", () => {
  const score = formalitySubscore([garment("mystery", "top", null), CHINO, SNEAKER]);
  assertEquals(score.degraded.length, 1);
  assert(score.degraded[0]!.includes("mystery"));
  assert(score.degraded[0]!.includes("default"));
  // 45 for a top: the value is still usable, just not measured.
  assert(score.value > 0 && score.value < 1);
});

Deno.test("One garment cannot disagree with itself, so it scores 1 and reports why", () => {
  // Zero would say the garment clashes with something. There is nothing.
  const score = formalitySubscore([POLO]);
  assertEquals(score.value, 1);
  assert(score.degraded[0]!.includes("second garment"));
});

// ── §3.1, the outfit's register ──────────────────────────────────────────────

Deno.test("The doc's worked outfit formality of 30 reproduces", () => {
  // M = (40+50+22)/3 = 37.33; min 22; deviation 15.33 > 10;
  // penalty 7.67; 37.33 - 7.67 = 29.66 → 30 ("smart casual").
  assertEquals(outfitFormality([POLO, CHINO, SNEAKER]), 30);
});

Deno.test("Minor register mixing is not penalised at all", () => {
  // A 40 and a 50 together is deliberate casualisation, not a mistake. The
  // deviation gate exists so the engine does not charge for texture.
  const mean = outfitFormality([garment("a", "top", 40), garment("b", "bottom", 50)]);
  assertEquals(mean, 45);
});

Deno.test("A genuine outlier drags the register down, which is the styling rule", () => {
  const coherent = outfitFormality([
    garment("shirt", "top", 70),
    garment("trouser", "bottom", 70),
    garment("oxford", "shoes", 70),
  ])!;
  const withTrainers = outfitFormality([
    garment("shirt", "top", 70),
    garment("trouser", "bottom", 70),
    garment("trainer", "shoes", 10),
  ])!;
  assertEquals(coherent, 70);
  // M = (70+70+10)/3 = 50; min 10; deviation 40 > 10; penalty 20 → 30.
  // Asserted as a drop from the coherent outfit rather than an absolute
  // threshold: what the rule promises is that the outlier moves the register a
  // long way, and 70 → 30 is the whole gap between "business" and "casual".
  assertEquals(withTrainers, 30);
  assert(
    coherent - withTrainers >= 30,
    `one trainer only moved the register by ${coherent - withTrainers}`,
  );
});

Deno.test("A casual accessory does not drag a formal outfit down", () => {
  // The minimum is taken over VISIBLE non-accessory items on purpose. A woven
  // bracelet at 20 must not read a suit down to shorts.
  const withoutBracelet = outfitFormality([
    garment("shirt", "top", 80),
    garment("trouser", "bottom", 80),
    garment("oxford", "shoes", 80),
  ])!;
  const withBracelet = outfitFormality([
    garment("shirt", "top", 80),
    garment("trouser", "bottom", 80),
    garment("oxford", "shoes", 80),
    garment("bracelet", "accessory", 20),
  ])!;
  assert(
    withoutBracelet - withBracelet < 12,
    `a bracelet moved the register by ${withoutBracelet - withBracelet}`,
  );
});

Deno.test("The register stays inside 0–100 for extreme outfits", () => {
  const veryMixed = outfitFormality([
    garment("tux", "top", 100),
    garment("shorts", "bottom", 0),
    garment("slides", "shoes", 0),
  ])!;
  assert(veryMixed >= 0 && veryMixed <= 100, `out of range: ${veryMixed}`);
});

Deno.test("An empty outfit has no register rather than a zero one", () => {
  assertEquals(outfitFormality([]), null);
});
