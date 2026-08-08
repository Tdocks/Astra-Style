import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import { colorSubscore, UNKNOWN_COLOR_PRIOR } from "./color.ts";
import { classifyNeutral, rgbToLCh } from "../colorSpace.ts";
import type { Pattern, PatternScale, ScorableItem } from "../types.ts";

function hex(value: string) {
  const v = Number.parseInt(value, 16);
  return { r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255 };
}

function garment(
  id: string,
  role: ScorableItem["role"],
  colorHex: string | null,
  extras: { pattern?: Pattern; patternScale?: PatternScale; secondaries?: string[] } = {},
): ScorableItem {
  const lch = colorHex === null ? null : rgbToLCh(hex(colorHex));
  return {
    id,
    category: role === "accessory" ? "accessory" : role,
    role,
    primaryColor: lch,
    isNeutral: lch === null ? false : classifyNeutral(lch).isNeutral,
    secondaryColors: (extras.secondaries ?? []).map((h) => rgbToLCh(hex(h))),
    pattern: extras.pattern ?? "solid",
    patternScale: extras.patternScale ?? null,
    materials: [],
    formalityScore: null,
    fit: null,
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
  };
}

// §2.2's canonical outfit.
const OLIVE_POLO = garment("polo", "top", "6E6E3C");
const STONE_TROUSERS = garment("trousers", "bottom", "C8BEA5");
const WHITE_SNEAKERS = garment("sneakers", "shoes", "F5F3EE");

Deno.test("The doc's canonical outfit scores 0.97 — three neutrals, two contrasting", () => {
  // NOT the doc's printed 0.91. Its arithmetic ran the olive polo down the
  // chromatic path because its olive-drab band capped chroma at 22; the
  // corrected band (see colorSpace.ts) makes the polo a neutral, so all three
  // pairs take the neutral route and two clear the ≥30 lightness bonus:
  //   polo(L45)–trousers(L77) → 0.95 + 0.03 = 0.98
  //   polo(L45)–sneakers(L96) → 0.95 + 0.03 = 0.98
  //   trousers(L77)–sneakers(L96) → |Δ|=19 < 30 → 0.95
  //   (0.35×0.98 + 0.20×0.98 + 0.20×0.95) / 0.75 = 0.972
  const score = colorSubscore([OLIVE_POLO, STONE_TROUSERS, WHITE_SNEAKERS]);
  assertAlmostEquals(score.value, 0.972, 0.005);
  assertEquals(score.degraded, []);
});

Deno.test("A neutral anchors a saturated hue better than two saturated hues anchor each other", () => {
  // The single most load-bearing property of the whole component: it is why a
  // man is told a navy jacket works with almost anything.
  const navy = garment("navy", "top", "1F2A44");
  const red = garment("red", "bottom", "B03030");
  const green = garment("green", "bottom", "2E7D32");
  const neutralPair = colorSubscore([navy, red]).value;
  const clashPair = colorSubscore([green, red]).value;
  assert(
    neutralPair > clashPair,
    `neutral+red ${neutralPair} should beat green+red ${clashPair}`,
  );
});

Deno.test("The clash zone scores worse than either analogous or complementary", () => {
  // Harmony is not monotonic in hue distance — this is the shape §1.4 encodes,
  // and the reason it is a zone table rather than a curve. A regression that
  // made it monotonic would still pass most other tests here.
  const base = garment("base", "top", "B03030"); // red, h ≈ 40
  const analogous = colorSubscore([base, garment("x", "bottom", "B06A30")]).value;
  const clash = colorSubscore([base, garment("x", "bottom", "7A9A2E")]).value;
  const complementary = colorSubscore([base, garment("x", "bottom", "2E6FA0")]).value;
  assert(clash < analogous, `clash ${clash} should be worse than analogous ${analogous}`);
  assert(
    clash < complementary,
    `clash ${clash} should be worse than complementary ${complementary}`,
  );
});

Deno.test("Same hue with no value separation reads accidental, not monochrome-chic", () => {
  // Two navies an inch apart in lightness look like a suit whose halves do not
  // match. Separate them and the same pairing reads deliberate.
  const flat = colorSubscore([
    garment("a", "top", "38517A"),
    garment("b", "bottom", "3A5480"),
  ]).value;
  const separated = colorSubscore([
    garment("a", "top", "9FB3D9"),
    garment("b", "bottom", "1B2A4A"),
  ]).value;
  assert(separated > flat, `separated ${separated} should beat flat ${flat}`);
});

Deno.test("Neutral on neutral gains a bonus only with real value contrast", () => {
  const contrasting = colorSubscore([
    garment("charcoal", "bottom", "36393D"),
    garment("white", "top", "F5F3EE"),
  ]).value;
  const flat = colorSubscore([
    garment("charcoal", "bottom", "36393D"),
    garment("charcoal2", "top", "3A3D42"),
  ]).value;
  assert(contrasting > flat);
  assert(contrasting <= 0.98, `the neutral bonus must stay capped, got ${contrasting}`);
});

Deno.test("An unanalysed colour takes the 0.6 prior and names the garment", () => {
  const score = colorSubscore([garment("mystery", "top", null), STONE_TROUSERS]);
  assertEquals(score.value, UNKNOWN_COLOR_PRIOR);
  assertEquals(score.degraded.length, 1);
  assert(score.degraded[0]!.includes("mystery"));
});

Deno.test("The prior neither tanks nor inflates — it sits between clash and harmony", () => {
  // The property that makes 0.6 the right number. If it drifted to 0.2 every
  // unanalysed garment would be buried; at 0.95 they would outrank measured
  // ones. Both would be the app lying about what it knows.
  const clash = colorSubscore([
    garment("a", "top", "B03030"),
    garment("b", "bottom", "7A9A2E"),
  ]).value;
  const harmony = colorSubscore([OLIVE_POLO, STONE_TROUSERS]).value;
  assert(clash < UNKNOWN_COLOR_PRIOR, `clash ${clash} should be below the prior`);
  assert(harmony > UNKNOWN_COLOR_PRIOR, `harmony ${harmony} should be above the prior`);
});

Deno.test("Two patterns are not penalised while no column stores their scale", () => {
  // §1.5's rule turns entirely on scale separation, and nothing stores a
  // scale. Guessing one would invent the fact the rule reads, so the penalty
  // is skipped and the gap is reported instead.
  const plain = colorSubscore([
    garment("a", "top", "1F2A44"),
    garment("b", "bottom", "C8BEA5"),
  ]);
  const patterned = colorSubscore([
    garment("a", "top", "1F2A44", { pattern: "stripe" }),
    garment("b", "bottom", "C8BEA5", { pattern: "check" }),
  ]);
  assertEquals(patterned.value, plain.value);
  assert(patterned.degraded.some((d) => d.includes("pattern scale")));
});

Deno.test("With scales known, similar-weight patterns are penalised and separated ones less so", () => {
  const competing = colorSubscore([
    garment("a", "top", "1F2A44", { pattern: "stripe", patternScale: "small" }),
    garment("b", "bottom", "C8BEA5", { pattern: "check", patternScale: "medium" }),
  ]);
  const layered = colorSubscore([
    garment("a", "top", "1F2A44", { pattern: "stripe", patternScale: "micro" }),
    garment("b", "bottom", "C8BEA5", { pattern: "check", patternScale: "large" }),
  ]);
  assert(
    competing.value < layered.value,
    `same-scale ${competing.value} should be worse than separated ${layered.value}`,
  );
  assertEquals(competing.degraded, []);
});

Deno.test("A solid never triggers a pattern penalty however loud its partner", () => {
  const withSolid = colorSubscore([
    garment("a", "top", "1F2A44", { pattern: "solid" }),
    garment("b", "bottom", "C8BEA5", { pattern: "print", patternScale: "large" }),
  ]);
  assertEquals(withSolid.degraded, []);
  assert(withSolid.value > 0.9);
});

Deno.test("Texture-only counts as solid, because a texture is not a pattern to clash with", () => {
  const score = colorSubscore([
    garment("a", "top", "1F2A44", { pattern: "texture-only", patternScale: "micro" }),
    garment("b", "bottom", "C8BEA5", { pattern: "herringbone", patternScale: "micro" }),
  ]);
  assertEquals(score.degraded, []);
  assert(score.value > 0.9, `a texture should not be penalised, got ${score.value}`);
});

Deno.test("A secondary colour shifts the pair but never dominates it", () => {
  // §2.2 blends the best secondary cross-pairing at 20%. A pocket square must
  // be able to help, and must not be able to rescue a genuine clash.
  const withoutSecondary = colorSubscore([
    garment("a", "top", "B03030"),
    garment("b", "bottom", "7A9A2E"),
  ]).value;
  const withSecondary = colorSubscore([
    garment("a", "top", "B03030", { secondaries: ["C8BEA5"] }),
    garment("b", "bottom", "7A9A2E"),
  ]).value;
  assert(withSecondary > withoutSecondary, "a harmonious secondary should help");
  assert(
    withSecondary - withoutSecondary < 0.2,
    `a secondary moved the pair by ${withSecondary - withoutSecondary}; it must not dominate`,
  );
});

Deno.test("One garment reports no reading rather than scoring a clash", () => {
  const score = colorSubscore([OLIVE_POLO]);
  assertEquals(score.value, UNKNOWN_COLOR_PRIOR);
  assert(score.degraded[0]!.includes("second garment"));
});

Deno.test("Every score stays inside [0,1] across a wide sweep of pairings", () => {
  const swatches = ["1F2A44", "C8BEA5", "B03030", "7A9A2E", "F5F3EE", "0047AB", "C9A227", "36393D"];
  for (const a of swatches) {
    for (const b of swatches) {
      const value = colorSubscore([
        garment("a", "top", a, { pattern: "check", patternScale: "small" }),
        garment("b", "bottom", b, { pattern: "stripe", patternScale: "small" }),
      ]).value;
      assert(value >= 0 && value <= 1, `#${a}/#${b} produced ${value}`);
    }
  }
});
