/**
 * Colour NAMES to sRGB, so §1's colour space has something to read.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * WHY THIS FILE HAS TO EXIST, WHICH IS NOT OBVIOUS FROM THE DESIGN DOC.
 *
 * `docs/05-wardrobe-graph.md` §1.3 says "every closet item stores
 * `primary_color_lch` and `is_functional_neutral`, precomputed at analysis
 * time". Neither column exists. `closet_items.primary_color` is `text` — the
 * word "olive" — because that is what a vision provider returns and what the
 * §6.10 palette is written in.
 *
 * The obvious fix is a migration adding the two columns. It is the wrong first
 * move: nothing populates them, so every existing row would be null, and the
 * heaviest component of the compatibility score (colour, 0.25) would be a flat
 * 0.6 prior for the entire closet of every current user. The engine would be
 * shipped and inert.
 *
 * So the vocabulary resolves at scoring time. Every row that has a colour word
 * today gets a real harmony reading today. When a precomputed column does
 * arrive it becomes a cache in front of this function rather than a
 * replacement for it — the words will still be what the providers speak.
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * THE VALUES ARE iOS's, DELIBERATELY. `AstraGarmentColor.swift` already maps
 * these 58 words to swatches for the Style DNA palette, and a man reading
 * "olive" beside a swatch on his result screen and having the engine reason
 * about a different olive would be two answers to one question. There is one
 * vocabulary; this is the server's copy of it, and
 * `scripts/check_color_vocabulary.py` fails the build when the two drift.
 *
 * AN UNKNOWN WORD RETURNS NULL, NEVER A GUESS. The provider vocabulary will
 * grow, and a build that has never heard of "burnt sienna" must say so — the
 * caller then takes §2.2's 0.6 prior and reports the garment as unread. The
 * same rule iOS applies when it declines to draw a swatch it does not know: an
 * invented colour is worse than an absent one, because it is indistinguishable
 * from a measured one downstream.
 */

import { classifyNeutral, type LCh, rgbToLCh } from "./colorSpace.ts";

/** Packed `0xRRGGBB`, keyed by the lowercase colour word. */
const VOCABULARY: ReadonlyMap<string, number> = new Map([
  ["black", 0x111111],
  ["flat black", 0x141414],
  ["heavy black", 0x0E0E0E],
  ["charcoal", 0x36373A],
  ["cold charcoal", 0x33373C],
  ["grey", 0x8A8A8A],
  ["gray", 0x8A8A8A],
  ["mid grey", 0x8C8C8C],
  ["stone grey", 0x9A958C],
  ["washed grey", 0xA6A29B],
  ["cold silver grey", 0xB4B8BC],
  ["corporate mid grey", 0x86888C],
  ["mid business grey", 0x86888C],
  ["stone", 0xC9C1B2],
  ["white", 0xF2F0EB],
  ["bright white", 0xFAFAF8],
  ["bone", 0xEDE6D8],
  ["cream", 0xF0E7D3],
  ["ivory", 0xF4EEDF],
  ["ecru", 0xE6DCC6],
  ["oatmeal", 0xD8CDB6],
  ["sand", 0xD9C9A8],
  ["navy", 0x1F2A44],
  ["ink blue", 0x232E45],
  ["blue", 0x33507F],
  ["indigo", 0x33406B],
  ["faded indigo", 0x5A6B8C],
  ["cobalt", 0x2B4FA2],
  ["slate blue", 0x5A6B80],
  ["sky blue", 0x8FB4D6],
  ["pale blue", 0xB9CFE2],
  ["green", 0x3B5A40],
  ["olive", 0x5A5F3C],
  ["deep olive", 0x454A2E],
  ["faded olive", 0x757A5C],
  ["moss", 0x5E6B4A],
  ["sage", 0x9AA48C],
  ["forest green", 0x2C4433],
  ["hunter green", 0x2A4331],
  ["deep green", 0x27412F],
  ["brown", 0x5C4433],
  ["soft brown", 0x7A5F49],
  ["tobacco brown", 0x6B4A2F],
  ["camel", 0xC19A6B],
  ["tan", 0xC49A6C],
  ["khaki", 0xA89A73],
  ["red", 0x9B3A2E],
  ["barn red", 0x8E2B22],
  ["burgundy", 0x5E2233],
  ["oxblood", 0x4A1B23],
  ["rust", 0xA4552B],
  ["terracotta", 0xB0603C],
  ["yellow", 0xD6B23C],
  ["acid yellow", 0xD3DC22],
  ["mustard", 0xC9A227],
  ["saffron", 0xD8A128],
  ["lemon", 0xE8D24A],
  ["plum", 0x5A3752],
]);

export interface ResolvedColor {
  readonly lch: LCh;
  readonly isNeutral: boolean;
}

/**
 * Normalises a provider's colour string to a vocabulary key.
 *
 * Providers are not consistent about case, spacing or trailing punctuation, and
 * "Navy Blue" losing to "navy" over a capital letter would be a silent quarter
 * of the score. Deliberately conservative: it tidies, it does not interpret.
 */
function normalise(raw: string): string {
  return raw.trim().toLowerCase().replace(/[.,;]+$/, "").replace(/\s+/g, " ");
}

/**
 * Resolve a colour word to LCh plus its §1.3 neutral classification.
 *
 * Returns null for a word this build does not know — see the header. Tries the
 * whole string first, then its last word, so "washed olive" reaches "olive"
 * rather than falling off a cliff. The last word is the right one to keep:
 * English puts the head noun there, and the modifiers ("washed", "deep",
 * "faded") shift lightness rather than hue, which is the axis the harmony rules
 * are least sensitive to.
 */
export function resolveColorName(raw: string | null | undefined): ResolvedColor | null {
  if (!raw) return null;
  const key = normalise(raw);
  if (key.length === 0) return null;

  let packed = VOCABULARY.get(key);
  if (packed === undefined) {
    const words = key.split(" ");
    if (words.length > 1) {
      packed = VOCABULARY.get(words[words.length - 1]!);
    }
  }
  if (packed === undefined) return null;

  const lch = rgbToLCh({
    r: (packed >> 16) & 0xFF,
    g: (packed >> 8) & 0xFF,
    b: packed & 0xFF,
  });
  return { lch, isNeutral: classifyNeutral(lch).isNeutral };
}

/** Every word this build knows. Used by the drift checker and by tests. */
export function knownColorNames(): readonly string[] {
  return [...VOCABULARY.keys()];
}
