import { assert, assertEquals } from "jsr:@std/assert@1";
import { knownColorNames, resolveColorName } from "./colorVocabulary.ts";
import { hueDistance } from "./colorSpace.ts";

Deno.test("The words the mock vision provider emits all resolve", () => {
  // If any of these stopped resolving, every scan through the mock would score
  // its colour on the 0.6 prior and nobody would notice.
  for (
    const name of [
      "black",
      "charcoal",
      "grey",
      "navy",
      "olive",
      "brown",
      "burgundy",
      "cream",
      "white",
    ]
  ) {
    assert(resolveColorName(name) !== null, `provider vocabulary word "${name}" does not resolve`);
  }
});

Deno.test("Menswear's core neutrals classify as neutral", () => {
  // The whole reason §1.3's band table exists, verified through the words the
  // product actually speaks rather than through raw hex.
  for (
    const name of ["black", "charcoal", "grey", "white", "navy", "stone", "camel", "tan", "khaki"]
  ) {
    const resolved = resolveColorName(name)!;
    assert(resolved.isNeutral, `"${name}" should be a functional neutral`);
  }
});

Deno.test("Saturated colours do not classify as neutral", () => {
  for (const name of ["cobalt", "barn red", "acid yellow", "terracotta", "mustard"]) {
    const resolved = resolveColorName(name)!;
    assert(!resolved.isNeutral, `"${name}" should be chromatic`);
  }
});

Deno.test("Case, padding and trailing punctuation do not lose a match", () => {
  // A provider returning "Navy Blue." and losing to "navy" over a capital
  // letter would be a silent quarter of the compatibility score.
  const base = resolveColorName("navy")!;
  for (const variant of ["Navy", "  navy  ", "NAVY", "navy.", "navy,"]) {
    const resolved = resolveColorName(variant);
    assert(resolved !== null, `"${variant}" did not resolve`);
    assertEquals(resolved!.lch.h.toFixed(4), base.lch.h.toFixed(4));
  }
});

Deno.test("Internal whitespace is collapsed", () => {
  assert(resolveColorName("forest   green") !== null);
});

Deno.test("An unknown modifier falls back to the head noun", () => {
  // "washed olive" should reach olive rather than falling off a cliff. English
  // puts the head noun last, and the modifiers shift lightness rather than hue
  // — the axis the harmony rules care about least.
  const olive = resolveColorName("olive")!;
  const washed = resolveColorName("washed olive");
  assert(washed !== null, "a modified colour should fall back to its head noun");
  assert(hueDistance(washed!.lch.h, olive.lch.h) < 1);
});

Deno.test("An entirely unknown word returns null rather than a guess", () => {
  // The rule iOS already applies when it declines to draw a swatch: an
  // invented colour is worse than an absent one, because downstream it is
  // indistinguishable from a measured one.
  assertEquals(resolveColorName("burnt sienna"), null);
  assertEquals(resolveColorName("zzzz"), null);
  assertEquals(resolveColorName(""), null);
  assertEquals(resolveColorName("   "), null);
  assertEquals(resolveColorName(null), null);
  assertEquals(resolveColorName(undefined), null);
});

Deno.test("A multi-word unknown whose head noun is also unknown returns null", () => {
  assertEquals(resolveColorName("shimmering unobtanium"), null);
});

Deno.test("The vocabulary is the size the drift checker expects", () => {
  // Not a magic number for its own sake: scripts/check_color_vocabulary.py
  // pins this against iOS, and a silent shrink here would mean words that
  // render a swatch but score on the unknown prior.
  assertEquals(knownColorNames().length, 58);
});

Deno.test("Both British and American spellings of grey resolve identically", () => {
  const grey = resolveColorName("grey")!;
  const gray = resolveColorName("gray")!;
  assertEquals(grey.lch.l, gray.lch.l);
  assertEquals(grey.isNeutral, gray.isNeutral);
});
