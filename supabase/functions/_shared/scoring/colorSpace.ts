/**
 * sRGB → CIE LCh, and the neutral classification the harmony rules key on.
 *
 * `docs/05-wardrobe-graph.md` §1. Every function here is pure and takes no
 * database, provider or clock, which is the whole reason that document exists:
 * the 25%-weighted component of the compatibility score has to be testable
 * without a network.
 *
 * WHY NOT RGB, IN ONE LINE. Equal RGB steps are not equal perceived steps, and
 * "analogous", "complementary" and "monochrome" are statements about a hue
 * angle that RGB has no axis for. §1.1 has the long version.
 *
 * HUE IS MEANINGLESS AT LOW CHROMA, AND THIS BIT US IN THE FIRST TEST. Working
 * the doc's own stone-trousers example through this pipeline gives a* = −0.79
 * where the doc wrote +1, which moves h° from 86 to 93 — a seven-degree swing
 * off a rounding difference in the second decimal place of a*. That is not a
 * bug in either: at C* ≈ 1 the hue angle is the direction of a vector whose
 * length is nearly zero, so it is numerically unstable by construction. It is
 * the reason `classifyNeutral` tests `C* ≤ 12` FIRST and only then consults the
 * curated bands, and the reason no rule in this file branches on hue without a
 * chroma floor in front of it.
 */

/** A colour in the cylindrical CIE LAB space. */
export interface LCh {
  /** Perceptual lightness, 0–100. */
  readonly l: number;
  /** Chroma. 0 is fully desaturated; textiles rarely exceed ~90. */
  readonly c: number;
  /** Hue angle in degrees, 0–360. Meaningless below `c ≈ 2` — see the header. */
  readonly h: number;
}

/** A colour in CIE LAB. Kept because ΔE is defined on it, not on LCh. */
export interface Lab {
  readonly l: number;
  readonly a: number;
  readonly b: number;
}

/** 8-bit sRGB, the form colour vocabularies and photo pipelines speak. */
export interface RGB {
  readonly r: number;
  readonly g: number;
  readonly b: number;
}

/** D65 white point, the reference sRGB is defined against. */
const WHITE_POINT = { x: 95.047, y: 100.0, z: 108.883 } as const;

/** The CIE LAB companding threshold, (6/29)³. */
const EPSILON = 216 / 24389;
/** The linear segment's slope, (29/3)³. */
const KAPPA = 24389 / 27;

function clamp8(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(255, Math.max(0, value));
}

/**
 * Undoes sRGB's transfer function.
 *
 * The piecewise linear segment near black is not a rounding detail: without it
 * every near-black garment lands on a slightly different L* and charcoal stops
 * separating from black, which is a distinction menswear actually makes.
 */
function toLinear(channel8Bit: number): number {
  const c = clamp8(channel8Bit) / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function labCompand(ratio: number): number {
  return ratio > EPSILON ? Math.cbrt(ratio) : (KAPPA * ratio + 16) / 116;
}

/** sRGB → CIE LAB (D65). */
export function rgbToLab(rgb: RGB): Lab {
  const r = toLinear(rgb.r);
  const g = toLinear(rgb.g);
  const b = toLinear(rgb.b);

  // sRGB primaries against D65, scaled to the 0–100 convention LAB expects.
  const x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) * 100;
  const y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) * 100;
  const z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) * 100;

  const fx = labCompand(x / WHITE_POINT.x);
  const fy = labCompand(y / WHITE_POINT.y);
  const fz = labCompand(z / WHITE_POINT.z);

  return {
    l: 116 * fy - 16,
    a: 500 * (fx - fy),
    b: 200 * (fy - fz),
  };
}

/** CIE LAB → LCh. Hue is normalised into [0, 360). */
export function labToLCh(lab: Lab): LCh {
  const c = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
  const degrees = (Math.atan2(lab.b, lab.a) * 180) / Math.PI;
  return { l: lab.l, c, h: (degrees + 360) % 360 };
}

/** sRGB → LCh, the pipeline every caller actually wants. */
export function rgbToLCh(rgb: RGB): LCh {
  return labToLCh(rgbToLab(rgb));
}

/**
 * CIE76 ΔE — plain Euclidean distance in LAB.
 *
 * §1.2's judgment call, restated so nobody "improves" it by accident:
 * CIEDE2000 is more accurate, and its corrections matter most below ΔE ≈ 2 —
 * far under the noise floor of a colour extracted from a photograph of a
 * jumper on a bed. It is a drop-in replacement behind this signature if
 * photo-derived colour ever gets accurate enough to deserve it.
 */
export function colorDistance(a: Lab, b: Lab): number {
  const dl = a.l - b.l;
  const da = a.a - b.a;
  const db = a.b - b.b;
  return Math.sqrt(dl * dl + da * da + db * db);
}

/** Circular hue distance, 0–180. */
export function hueDistance(h1: number, h2: number): number {
  const raw = Math.abs(h1 - h2) % 360;
  return raw > 180 ? 360 - raw : raw;
}

/**
 * The §1.3 curated bands, CORRECTED — the shipped table is not the one in
 * `docs/05-wardrobe-graph.md` as originally written, and the amendment is
 * recorded there and in `docs/03-progress.md`.
 *
 * These exist for navy and olive-drab, which carry C* well above the `≤ 12`
 * cutoff and still function as neutrals in menswear — a navy blazer anchors a
 * hue the way charcoal does, and a scorer that called it chromatic would mark
 * every navy-plus-anything pairing down for a clash nobody sees.
 *
 * WHY THE ORIGINAL RANGES CAUGHT NOTHING. The doc's navy band was `h° 240–270`.
 * Run five real navies through the pipeline above and they land at **274–289**;
 * not one falls inside it. Olive-drab was `C* 10–22` and real olive-drabs
 * measure **18–31**. So both bands — the only two the table exists for — were
 * dead code that classified their own subject as chromatic.
 *
 * The cause is worth naming, because it is the trap this document's own §1.1
 * warns about. 240° is where blue sits in **HSL**, whose hue is a geometric
 * artifact of the RGB cube. In CIE LCh, blue is near 280–300°. The table was
 * reasoned in one hue space and applied in another.
 *
 * The ranges below were measured, not reasoned: sRGB values for real garments
 * pushed through `rgbToLCh` and widened to the observed envelope. The test file
 * pins both halves — the colours that must land inside, and a set of saturated
 * blues, greens, reds and yellows that must stay outside.
 *
 * CHROMA IS WHAT SEPARATES NAVY FROM COBALT, NOT HUE. Cobalt measures h° 291,
 * squarely between two of the navies. What makes navy a neutral is that its
 * saturation has been taken out: navy C* 15–28, cobalt C* 63. Every band below
 * therefore leans on its chroma ceiling to do the discriminating, and a future
 * widening of one of those ceilings is the change most likely to start calling
 * a royal-blue shirt a neutral.
 */
interface NeutralBand {
  readonly name: string;
  readonly l: readonly [number, number];
  readonly c: readonly [number, number];
  /** Omitted where the band is defined by lightness and chroma alone. */
  readonly h?: readonly [number, number];
}

const NEUTRAL_BANDS: readonly NeutralBand[] = [
  { name: "black", l: [0, 20], c: [0, 10] },
  { name: "charcoal", l: [20, 35], c: [0, 12] },
  { name: "gray", l: [35, 75], c: [0, 10] },
  { name: "white", l: [90, 100], c: [0, 8] },
  // Measured envelopes. Doc said stone h° 70–95; khaki and sand measure 86–98.
  { name: "stone", l: [75, 92], c: [5, 20], h: [70, 100] },
  // Doc said L 15–30, C 10–25, h 240–270. Measured across five navies:
  // L 11.4–29.0, C 15.5–27.7, h 274.4–289.2. The L floor goes to 8 for the
  // near-black midnight blues, which are navies a man would call navy.
  { name: "navy", l: [8, 32], c: [12, 30], h: [270, 295] },
  // Doc said L 30–45, C 10–22, h 95–115. Measured: L 33.5–47.3, C 17.7–30.6,
  // h 111.3–114.9 — the doc's chroma ceiling excluded every real one.
  { name: "olive-drab", l: [28, 50], c: [12, 32], h: [100, 120] },
  // Doc said L 55–75, C 15–30, h 60–80. Measured camel/tan/khaki/sand:
  // L 66.1–79.6, C 19.6–31.3, h 74.5–97.5. Khaki at h 97.5 is the one the
  // doc's 80° ceiling missed, and khaki is not an exotic case.
  { name: "tan", l: [60, 80], c: [15, 33], h: [60, 100] },
];

/** Chroma at or below which a colour is neutral whatever its hue says. */
export const NEUTRAL_CHROMA_CEILING = 12;

export interface NeutralClassification {
  readonly isNeutral: boolean;
  /** Which band matched, or `"low-chroma"`, or null when chromatic. */
  readonly band: string | null;
}

function within(value: number, range: readonly [number, number]): boolean {
  return value >= range[0] && value <= range[1];
}

/**
 * Is this colour a functional neutral — something that anchors other hues
 * rather than competing with them?
 *
 * Chroma is tested first and separately, not folded into the band loop. Two
 * reasons: it is the fast path for the black/white/grey majority of a closet,
 * and it keeps every hue-dependent band behind a chroma floor, which the header
 * explains is not optional.
 */
export function classifyNeutral(color: LCh): NeutralClassification {
  if (color.c <= NEUTRAL_CHROMA_CEILING) {
    return { isNeutral: true, band: "low-chroma" };
  }
  for (const band of NEUTRAL_BANDS) {
    if (!within(color.l, band.l)) continue;
    if (!within(color.c, band.c)) continue;
    if (band.h && !within(color.h, band.h)) continue;
    return { isNeutral: true, band: band.name };
  }
  return { isNeutral: false, band: null };
}
