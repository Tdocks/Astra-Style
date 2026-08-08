import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  classifyNeutral,
  colorDistance,
  hueDistance,
  labToLCh,
  type LCh,
  rgbToLab,
  rgbToLCh,
} from "./colorSpace.ts";

// The three garments from `docs/05-wardrobe-graph.md` §2.2's worked example.
// Asserted against values computed FROM THIS PIPELINE, not against the
// document's — see the deltas noted in each test. The document's table is
// explicitly labelled "Approx sRGB" and was worked by hand; where the two
// disagree the tolerance below records by how much, so a future change that
// moves these numbers fails loudly instead of quietly re-deriving a different
// colour space.
const OLIVE_POLO = { r: 110, g: 110, b: 60 };
const STONE_TROUSERS = { r: 200, g: 190, b: 165 };
const WHITE_SNEAKERS = { r: 245, g: 243, b: 238 };

Deno.test("Pure white lands on L*100 with no chroma", () => {
  const white = rgbToLab({ r: 255, g: 255, b: 255 });
  assertAlmostEquals(white.l, 100, 0.01);
  assertAlmostEquals(white.a, 0, 0.01);
  assertAlmostEquals(white.b, 0, 0.01);
});

Deno.test("Pure black lands on L*0", () => {
  const black = rgbToLab({ r: 0, g: 0, b: 0 });
  assertAlmostEquals(black.l, 0, 0.01);
});

Deno.test("Mid grey is achromatic — equal channels can never carry hue", () => {
  const grey = rgbToLCh({ r: 128, g: 128, b: 128 });
  assertAlmostEquals(grey.c, 0, 0.01);
  assert(grey.l > 50 && grey.l < 55, `expected mid lightness, got ${grey.l}`);
});

Deno.test("The olive polo reproduces the doc's L*, a* and h° within a point", () => {
  const lch = rgbToLCh(OLIVE_POLO);
  // Doc: L*45, a*−8, h°105. All three land.
  assertAlmostEquals(lch.l, 45.3, 0.5);
  assertAlmostEquals(lch.h, 105.8, 1.0);
  // Doc: C*31. This pipeline gives 28.9 — the doc's b* of 30 against this
  // pipeline's 27.8 is the whole difference, and it is a hand-arithmetic
  // rounding, not a disagreement about the colour.
  assertAlmostEquals(lch.c, 28.9, 0.5);
});

Deno.test("The olive polo is a NEUTRAL, which reverses the doc's worked example", () => {
  // §2.2 called it chromatic, because its olive-drab band capped chroma at 22
  // and the polo measures 28.9. That cap excluded every real olive-drab
  // garment — see `NEUTRAL_BANDS` — so it has been widened to 32, and the
  // doc's own example moves with it.
  //
  // The new answer is the better one on the merits, not merely the consistent
  // one. Olive is a canonical menswear neutral; it anchors a hue the way navy
  // and khaki do, which is precisely why the band exists at all. An engine
  // that scored an olive polo as a chromatic element competing with stone
  // trousers would be marking down one of the easiest outfits a man owns.
  //
  // Consequence, carried through in the doc's amendment: the outfit's colour
  // subscore goes 0.91 → 0.97, because all three garments are now neutrals
  // and two of the three pairs clear the ≥30 lightness-contrast bonus.
  const classification = classifyNeutral(rgbToLCh(OLIVE_POLO));
  assertEquals(classification.isNeutral, true);
  assertEquals(classification.band, "olive-drab");
});

Deno.test("The widened olive band does not swallow an actual green", () => {
  // The band's chroma ceiling is the only thing between "olive is a neutral"
  // and "every green in the closet is a neutral". Moss is the nearest miss in
  // the whole vocabulary at C*35.2, and it clears the 32 ceiling by three
  // points — which is the margin a future widening would be spending.
  const moss = rgbToLCh({ r: 138, g: 154, b: 91 });
  assertEquals(classifyNeutral(moss).isNeutral, false);
  for (const hex of ["808000", "8DB600", "4CBB17", "7FFF00"]) {
    const lch = rgbToLCh(fromHex(hex));
    assertEquals(
      classifyNeutral(lch).isNeutral,
      false,
      `#${hex} → L${lch.l.toFixed(1)} C${lch.c.toFixed(1)} h${lch.h.toFixed(1)}`,
    );
  }
});

Deno.test("Pale yellows above the stone band stay chromatic, and that is known", () => {
  // Wheat (L89 C24) and butter (L91 C30) sit above the stone band's chroma
  // ceiling of 20 and are read as chromatic. Recorded rather than fixed: they
  // are pale yellows, the cost is 0.90 instead of 0.95 against a neutral —
  // half a point on a 100-point score — and lifting stone's ceiling to catch
  // them would start catching saffron, which is not a neutral by any reading.
  assertEquals(classifyNeutral(rgbToLCh(fromHex("F5DEB3"))).isNeutral, false);
  assertEquals(classifyNeutral(rgbToLCh(fromHex("F3E5AB"))).isNeutral, false);
});

Deno.test("The stone trousers are neutral by band, not by chroma", () => {
  const lch = rgbToLCh(STONE_TROUSERS);
  assert(lch.c > 12, `stone should exceed the chroma ceiling, got C*${lch.c}`);
  const classification = classifyNeutral(lch);
  assertEquals(classification.isNeutral, true);
  assertEquals(classification.band, "stone");
});

Deno.test("The white sneakers take the low-chroma fast path", () => {
  const classification = classifyNeutral(rgbToLCh(WHITE_SNEAKERS));
  assertEquals(classification.isNeutral, true);
  assertEquals(classification.band, "low-chroma");
});

function fromHex(hex: string) {
  const v = Number.parseInt(hex, 16);
  return { r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255 };
}

// THE BAND TABLE HAS TWO HALVES AND THE SECOND ONE MATTERS MORE.
//
// A band that is too narrow makes navy score like a clash. A band that is too
// wide makes a cobalt shirt score like a neutral, which is worse: it hands the
// user a confidently wrong pairing rather than an over-cautious one. So every
// band is pinned from both sides, and the chromatic list below is deliberately
// stocked with the near misses — saturated blues at navy's own hue angle,
// mustard at khaki's, forest green next to olive.
//
// These are also the measurements that corrected the doc's table. See
// `colorSpace.ts`'s `NEUTRAL_BANDS` comment for the diagnosis.

const MUST_BE_NEUTRAL: readonly [string, string, string][] = [
  ["navy blazer", "1F2A44", "navy"],
  ["navy chino", "2B3A55", "navy"],
  ["dark navy", "141E33", "navy"],
  ["french navy", "1D2951", "navy"],
  ["slate navy", "36455E", "navy"],
  ["olive drab", "54592E", "olive-drab"],
  ["army olive", "4B5320", "olive-drab"],
  ["field olive", "5A5F3C", "olive-drab"],
  ["sage olive", "6E7355", "olive-drab"],
  ["camel coat", "C19A6B", "tan"],
  ["tan chino", "C3A57B", "tan"],
  ["khaki", "BDB283", "tan"],
  ["stone", "C8BEA5", "stone"],
];

for (const [name, hex, expectedBand] of MUST_BE_NEUTRAL) {
  Deno.test(`${name} classifies as the ${expectedBand} neutral`, () => {
    const lch = rgbToLCh(fromHex(hex));
    const classification = classifyNeutral(lch);
    assertEquals(
      classification.isNeutral,
      true,
      `#${hex} → L${lch.l.toFixed(1)} C${lch.c.toFixed(1)} h${lch.h.toFixed(1)}`,
    );
    assertEquals(classification.band, expectedBand);
  });
}

const MUST_BE_CHROMATIC: readonly [string, string][] = [
  // Same hue angle as navy. Only the chroma tells them apart.
  ["cobalt", "0047AB"],
  ["royal blue", "2B4FBF"],
  ["bright blue", "1560BD"],
  ["sky blue", "6CA6DC"],
  // Same hue region as khaki, three times the chroma.
  ["mustard", "C9A227"],
  // Next door to olive-drab.
  ["forest green", "1B4D2E"],
  ["burgundy", "6E1F2A"],
  ["rust", "A8442A"],
  ["barn red", "8C2318"],
];

for (const [name, hex] of MUST_BE_CHROMATIC) {
  Deno.test(`${name} stays chromatic — a neutral band must not swallow it`, () => {
    const lch = rgbToLCh(fromHex(hex));
    const classification = classifyNeutral(lch);
    assertEquals(
      classification.isNeutral,
      false,
      `#${hex} → L${lch.l.toFixed(1)} C${lch.c.toFixed(1)} h${lch.h.toFixed(1)} ` +
        `was swallowed by the "${classification.band}" band`,
    );
  });
}

Deno.test("Cobalt and navy share a hue angle — chroma is the only separator", () => {
  // If this ever stops being true, the navy band's chroma ceiling is the thing
  // holding the whole classification together and it should be widened with
  // considerable care.
  const navy = rgbToLCh(fromHex("1D2951"));
  const cobalt = rgbToLCh(fromHex("0047AB"));
  assert(
    hueDistance(navy.h, cobalt.h) < 10,
    `expected near-identical hue, got ${navy.h} vs ${cobalt.h}`,
  );
  assert(
    cobalt.c > navy.c * 2,
    `expected cobalt to be far more saturated, got C*${cobalt.c} vs C*${navy.c}`,
  );
});

Deno.test("Hue distance is circular and never exceeds 180", () => {
  assertEquals(hueDistance(10, 350), 20);
  assertEquals(hueDistance(350, 10), 20);
  assertEquals(hueDistance(0, 180), 180);
  assertEquals(hueDistance(90, 90), 0);
  // 190° apart the short way round is 170°, not 190°.
  assertEquals(hueDistance(0, 190), 170);
});

Deno.test("ΔE is zero for identical colours and symmetric otherwise", () => {
  const a = rgbToLab(OLIVE_POLO);
  const b = rgbToLab(STONE_TROUSERS);
  assertEquals(colorDistance(a, a), 0);
  assertAlmostEquals(colorDistance(a, b), colorDistance(b, a), 1e-9);
  assert(colorDistance(a, b) > 20, "olive and stone are not near-identical");
});

Deno.test("Out-of-range channels are clamped rather than producing NaN", () => {
  // A provider that hands back 300 or −5 for a channel should cost us a
  // slightly wrong colour, not a NaN that propagates into every subscore and
  // silently zeroes an outfit's rank.
  const over = rgbToLCh({ r: 300, g: 300, b: 300 });
  assertAlmostEquals(over.l, 100, 0.01);
  const under = rgbToLCh({ r: -5, g: -5, b: -5 });
  assertAlmostEquals(under.l, 0, 0.01);
  const nonsense = rgbToLCh({ r: Number.NaN, g: 0, b: 0 });
  assert(Number.isFinite(nonsense.l), "NaN input must not produce NaN output");
});

Deno.test("Charcoal separates from black, which the linear segment is what preserves", () => {
  // Menswear distinguishes these. If sRGB's near-black linear segment were
  // dropped for a plain 2.2 gamma, they would collapse toward each other.
  const black = rgbToLCh({ r: 12, g: 12, b: 12 });
  const charcoal = rgbToLCh({ r: 60, g: 60, b: 62 });
  assert(
    charcoal.l - black.l > 15,
    `expected visible lightness separation, got ${black.l} vs ${charcoal.l}`,
  );
  assertEquals(classifyNeutral(black).band, "low-chroma");
  assertEquals(classifyNeutral(charcoal).band, "low-chroma");
});

Deno.test("labToLCh normalises a negative hue angle into [0,360)", () => {
  const lch: LCh = labToLCh({ l: 50, a: 10, b: -10 });
  assert(lch.h >= 0 && lch.h < 360, `hue out of range: ${lch.h}`);
  assertAlmostEquals(lch.h, 315, 0.5);
});
