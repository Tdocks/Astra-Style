import type { ProviderPattern } from "./visionAnalysis.ts";

/** Enforce taxonomy only when foreground evidence explicitly supports it. */
export function resolveGarmentPattern(
  raw: ProviderPattern,
  evidence: string,
  category: string,
): { value: ProviderPattern; corrected: boolean } {
  const text = evidence.toLowerCase();
  const result = (value: ProviderPattern) => ({ value, corrected: value !== raw });
  // Do not derive a garment attribute from background descriptions or negated cues.
  if (/\b(background|bedding|rug|floor|wall|outside)\b/.test(text)) return result(raw);
  const negated = /\b(no|not|without|lacks?)\b/.test(text);
  const decorative =
    /\b(embossed|embossing|braided|braiding|woven|weave|perforated|perforations?|quilted|reptile|crocodile|snakeskin|ostrich|knit|knitted|ribbed|cable|herringbone|chevron)\b/
      .test(text);
  if (
    category === "shoes" && !decorative &&
    !/\b(floral|camouflage|camo|plaid|checks|striped|dots|graphic|printed|animal)\b/.test(text) &&
    /\b(leather|suede)\b/.test(text) &&
    /\b(grain|nap|crease(?:s|d|ing)?|wrinkl(?:e[sd]?|ing))\b/.test(text)
  ) {
    return result("solid");
  }
  const smallLogo = /\b(small|tiny|isolated|discreet)\b.{0,40}\b(logo|emblem|brand mark)\b/.test(
    text,
  );
  const strongMotif =
    /\b(camouflage|camo|floral|plaid|tartan|gingham|houndstooth|checkered|striped|chevron|herringbone)\b/
      .test(text);
  if (smallLogo && !strongMotif && /\b(plain|solid|uniform|unpatterned|otherwise)\b/.test(text)) {
    return result("solid");
  }
  if (negated) return result(raw);
  const check = /\b(plaid|tartan|gingham|houndstooth|checkered|checks)\b/.test(text);
  const print = /\b(camouflage|camo|floral)\b/.test(text);
  const herringbone = /\bherringbone\b|\bchevron\b.{0,30}\bweave\b/.test(text);
  // Multiple competing motifs are ambiguous; preserve the model's choice.
  if (Number(check) + Number(print) + Number(herringbone) !== 1) return result(raw);
  if (check) return result("check");
  if (print) return result("print");
  return result("herringbone");
}
