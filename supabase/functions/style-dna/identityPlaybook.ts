// ============================================================================
// style-dna/identityPlaybook.ts
// ============================================================================
// One entry per style identity in spec §6.5's list of ten. This table is the
// reason the deterministic Style DNA provider produces something a man could
// act on rather than something that merely fills the six sections of the
// §6.10 screen.
//
// WHY THIS EXISTS AT ALL, given a live model is the eventual plan.
//
// `docs/01-build-roadmap.md`'s Phase 2 risk list names the failure mode
// directly: "a technically-working endpoint can still produce generic or
// repetitive output". A mock that returns "Your style is versatile and
// modern. Recommended colours: navy, grey, white." for all ten identities is
// exactly that — it passes every schema test, renders correctly, and tells
// the user nothing. So the mock carries real content: ten distinct palettes,
// ten distinct silhouette directions, ten sets of signature pieces. Two users
// who picked different identities get visibly different Style DNA, which is
// the property the screen is being judged on.
//
// It also survives the live provider landing. A prompt for a live
// StylistReasoningProvider needs house taste to ground it — otherwise the
// output is whatever the model's training distribution thinks "quiet luxury"
// means this year, which drifts between model versions and is not a thing
// anyone at Astra decided. This table is that house taste, in a form a prompt
// can embed and an eval can check against.
//
// COPY RULES THESE STRINGS FOLLOW (CLAUDE.md, spec §2, docs/14-frame-fit.md
// §4, and enforced for Swift by scripts/check_ui_conventions.py):
//
//   • The garment is the subject of every sentence, never the wearer's body.
//     "A straight leg keeps the line unbroken", not "straight legs suit your
//     shape".
//   • "Flattering" is banned outright — it is a euphemism for concealment.
//   • No internal ticket ids, no model or vendor names, no "AI" framing.
//
// These strings are user-facing. They are NOT localized: server-generated
// prose is a known, accepted gap for the whole Edge Function layer (every
// `reason` string in `outfits/scorer.ts` has it too) and closing it belongs
// with the wider server-side localization decision, not this endpoint.
// ============================================================================

import type { AccessoryPreferenceValue, FormalityOrdinal } from "./schema.ts";

export interface SignatureItem {
  /** The piece, named concretely enough to shop for. */
  readonly title: string;
  /** Why this piece and not a neighbouring one. Always about what it does. */
  readonly reason: string;
}

export interface IdentityPlaybook {
  readonly displayName: string;
  /** 4-5 colours that carry most outfits in this identity. */
  readonly coreColours: readonly string[];
  /** Added to the palette only when the preference vector says colour is welcome. */
  readonly accentColours: readonly string[];
  /** Colours that fight this identity. Written to `style_profiles.avoided_colors`. */
  readonly avoidColours: readonly string[];
  /** One clause explaining the palette's logic, used in the palette rationale. */
  readonly paletteNote: string;
  readonly silhouetteHeadline: string;
  readonly silhouetteDetail: string;
  readonly signatures: readonly SignatureItem[];
  /** Fallback priorities when lifestyle and goals are both unknown. */
  readonly priorities: readonly SignatureItem[];
  /** Baseline for the four §6.10 summary scalars, before every other input moves them. */
  readonly formality: FormalityOrdinal;
  readonly logoTolerance: number;
  readonly trendTolerance: number;
  readonly accessoryPreference: AccessoryPreferenceValue;
  /** Identities that sit next to this one, used only when the user named no secondaries. */
  readonly neighbours: readonly string[];
}

export const IDENTITY_PLAYBOOK: Readonly<Record<string, IdentityPlaybook>> = {
  modern_heritage: {
    displayName: "Modern Heritage",
    coreColours: ["charcoal", "navy", "oatmeal", "tobacco brown", "olive"],
    accentColours: ["rust", "forest green"],
    avoidColours: ["neon brights", "cold silver grey"],
    paletteNote:
      "earth tones with one cold anchor, so a heavy jacket reads considered rather than costume",
    silhouetteHeadline: "Straight and substantial, with a natural shoulder.",
    silhouetteDetail:
      "Heavier cloth holds its own shape, so a straight-leg trouser and an unpadded shoulder let it hang the way it was cut. Cropping a jacket short works against the weight of the fabric.",
    signatures: [
      {
        title: "A waxed cotton jacket in olive or brown",
        reason: "It is the one layer that anchors this whole direction and gets better with wear.",
      },
      {
        title: "A brown leather boot with a welted sole",
        reason: "Dresses up under a trouser and down over denim, so it earns its place twice.",
      },
      {
        title: "A heavy oxford-cloth shirt",
        reason: "Holds a collar without starch and layers under knitwear without bulking.",
      },
    ],
    priorities: [
      {
        title: "One outer layer that does most of the work",
        reason: "This direction is built around a jacket. Get that right and the rest follows.",
      },
      {
        title: "Two trousers that take the same boot",
        reason: "A shared shoe is what turns separate pieces into a wardrobe.",
      },
      {
        title: "Knitwear in a natural fibre",
        reason: "Wool and cotton hold shape across a day; the synthetics in this palette do not.",
      },
    ],
    formality: 2,
    logoTolerance: 20,
    trendTolerance: 30,
    accessoryPreference: "moderate",
    neighbours: ["rugged_utility", "classic_americana"],
  },

  quiet_luxury: {
    displayName: "Quiet Luxury",
    coreColours: ["charcoal", "ivory", "camel", "navy", "stone grey"],
    accentColours: ["deep olive", "oxblood"],
    avoidColours: ["bright primaries", "high-shine metallics"],
    paletteNote: "five neutrals that all sit together, so any two pieces already match",
    silhouetteHeadline: "One unbroken column, cut close but never tight.",
    silhouetteDetail:
      "Tonal dressing does the work: a trouser and a knit within a shade of each other read as one long line. A soft, unstructured shoulder keeps a jacket from announcing itself.",
    signatures: [
      {
        title: "A fine-gauge crew knit in camel or ivory",
        reason: "The single piece this direction is built on — it has to be a good one.",
      },
      {
        title: "An unstructured wool blazer in charcoal",
        reason: "Reads as tailoring without the formality of a suit jacket.",
      },
      {
        title: "A leather loafer in dark brown",
        reason: "Finishes a tonal outfit without adding a second point of contrast.",
      },
    ],
    priorities: [
      {
        title: "Fewer pieces, better cloth",
        reason:
          "This direction shows fabric quality more than any other. Three good knits beat eight ordinary ones.",
      },
      {
        title: "A trouser in each of two neutrals",
        reason: "Tonal outfits need a matching partner for every top, not a contrast one.",
      },
      {
        title: "One coat that covers a jacket",
        reason: "Length and shoulder room decide whether the column survives the outer layer.",
      },
    ],
    formality: 3,
    logoTolerance: 5,
    trendTolerance: 20,
    accessoryPreference: "minimal",
    neighbours: ["minimalist", "executive"],
  },

  smart_casual: {
    displayName: "Smart Casual",
    coreColours: ["navy", "mid grey", "white", "stone", "soft brown"],
    accentColours: ["burgundy", "sage"],
    avoidColours: ["neon brights", "flat black"],
    paletteNote:
      "office neutrals that still work at a bar, with nothing that needs a tie to make sense",
    silhouetteHeadline: "Trim on top, easy below.",
    silhouetteDetail:
      "A shirt or knit cut close to the body against a trouser with a little room reads deliberate. Matching both to the same degree of slimness is what makes an outfit look like a uniform.",
    signatures: [
      {
        title: "A navy overshirt or chore jacket",
        reason:
          "The layer that turns a shirt and trouser into an outfit without reaching for tailoring.",
      },
      {
        title: "A pair of dark, clean-lined leather sneakers",
        reason: "The one shoe that carries this direction across a whole week.",
      },
      {
        title: "A merino polo",
        reason: "Collared enough for a meeting, soft enough that it never reads as a work shirt.",
      },
    ],
    priorities: [
      {
        title: "Two jackets that both work over a shirt",
        reason: "This direction lives or dies on the mid-layer.",
      },
      {
        title: "Trousers that are not jeans and not suit trousers",
        reason: "The gap between those two is exactly where smart casual sits.",
      },
      {
        title: "One shoe that is neither trainer nor dress shoe",
        reason: "It resolves most of the outfits this direction produces.",
      },
    ],
    formality: 2,
    logoTolerance: 25,
    trendTolerance: 45,
    accessoryPreference: "moderate",
    neighbours: ["modern_heritage", "european_summer"],
  },

  minimalist: {
    displayName: "Minimalist",
    coreColours: ["black", "white", "grey", "navy", "ecru"],
    accentColours: ["deep olive", "slate blue"],
    avoidColours: ["saturated brights", "warm tan"],
    paletteNote: "a closed set of five, so every piece already goes with every other piece",
    silhouetteHeadline: "Clean edges, no visible hardware.",
    silhouetteDetail:
      "Shape carries everything here, so the cut has to be right — a straight hem, a plain front trouser, a jacket with no patch pockets. Detail that would read as texture elsewhere reads as noise in this palette.",
    signatures: [
      {
        title: "A heavyweight plain white tee that holds its shape",
        reason:
          "In this palette it is a garment, not an undershirt, and the difference is the fabric weight.",
      },
      {
        title: "A flat-front trouser in black or charcoal",
        reason: "Uninterrupted from waist to hem, which is what the direction is built on.",
      },
      {
        title: "A minimal leather sneaker with no branding",
        reason: "Keeps the line going to the floor instead of stopping it.",
      },
    ],
    priorities: [
      {
        title: "Replace, do not accumulate",
        reason: "A closed palette means a worn-out piece is a hole, not an excuse for variety.",
      },
      {
        title: "Get the fit exact on the basics",
        reason: "With no pattern or colour to look at, the shoulder seam is what the eye lands on.",
      },
      {
        title: "One outer layer in each of black and ecru",
        reason: "Two coats cover the whole palette without introducing a third colour.",
      },
    ],
    formality: 2,
    logoTolerance: 5,
    trendTolerance: 30,
    accessoryPreference: "minimal",
    neighbours: ["quiet_luxury", "executive"],
  },

  luxury_streetwear: {
    displayName: "Luxury Streetwear",
    coreColours: ["black", "bone", "washed grey", "deep green"],
    accentColours: ["cobalt", "acid yellow"],
    avoidColours: ["pastels", "mid business grey"],
    paletteNote: "a dark base that lets one loud piece be the whole outfit",
    silhouetteHeadline: "Volume up top, tapered to the ankle.",
    silhouetteDetail:
      "The proportion is the point: a boxy, dropped-shoulder top over a trouser that narrows below the knee. Matching volume top and bottom loses the shape this direction depends on.",
    signatures: [
      {
        title: "A boxy heavyweight hoodie or crew",
        reason: "The proportion piece. Weight is what separates it from a gym sweatshirt.",
      },
      {
        title: "A technical outer layer in black",
        reason: "Carries the whole outfit and does not compete with a statement piece underneath.",
      },
      {
        title: "One sneaker worth building outfits around",
        reason: "In this direction the shoe is usually the loudest thing, so choose it first.",
      },
    ],
    priorities: [
      {
        title: "Nail the proportion before adding pieces",
        reason:
          "The top-to-bottom ratio is what makes this read as intentional rather than oversized.",
      },
      {
        title: "Keep the base plain so one piece can be loud",
        reason: "Two statement pieces in one outfit cancel each other.",
      },
      {
        title: "Black outerwear that works over volume",
        reason: "A slim coat undoes the silhouette the moment it goes on.",
      },
    ],
    formality: 1,
    logoTolerance: 70,
    trendTolerance: 85,
    accessoryPreference: "bold",
    neighbours: ["creative", "minimalist"],
  },

  rugged_utility: {
    displayName: "Rugged Utility",
    coreColours: ["olive", "sand", "charcoal", "brown", "faded indigo"],
    accentColours: ["rust", "mustard"],
    avoidColours: ["pale pastels", "bright white"],
    paletteNote: "colours that hide a day's wear, so nothing looks wrong by the evening",
    silhouetteHeadline: "Roomy through the body, held at the waist and cuff.",
    silhouetteDetail:
      "Work-derived cuts need room to move, and a cinched waist or a buttoned cuff is what stops that room reading as a size too big. A trouser with a slight taper keeps a boot visible.",
    signatures: [
      {
        title: "A chore jacket in olive or brown duck canvas",
        reason: "The defining layer, and the one that improves rather than degrades with wear.",
      },
      {
        title: "A pair of hard-wearing boots that take a resole",
        reason:
          "This direction rewards repair over replacement, and the sole is where that starts.",
      },
      {
        title: "A flannel or heavy twill shirt",
        reason: "Works as a shirt or as a light layer, which is two pieces of use from one.",
      },
    ],
    priorities: [
      {
        title: "Buy for repair, not for season",
        reason:
          "The whole point of this direction is pieces that last long enough to look worn in.",
      },
      {
        title: "One pair of boots, properly broken in",
        reason: "Rotating three pairs means none of them ever gets there.",
      },
      {
        title: "Layers that work at three temperatures",
        reason: "This wardrobe is used outdoors, where the day changes under you.",
      },
    ],
    formality: 1,
    logoTolerance: 20,
    trendTolerance: 25,
    accessoryPreference: "moderate",
    neighbours: ["modern_heritage", "classic_americana"],
  },

  classic_americana: {
    displayName: "Classic Americana",
    coreColours: ["indigo", "white", "navy", "khaki", "red-brown"],
    accentColours: ["barn red", "hunter green"],
    avoidColours: ["cold silver grey", "neon brights"],
    paletteNote: "indigo and white as the spine, with everything else read against them",
    silhouetteHeadline: "Regular through the body, hemmed to sit on the shoe.",
    silhouetteDetail:
      "These cuts were drawn before slim fits existed and they look wrong forced into one. A straight leg breaking once on the shoe is the proportion the whole direction assumes.",
    signatures: [
      {
        title: "A pair of raw or lightly washed indigo jeans",
        reason: "Everything in this direction is built to sit next to these.",
      },
      {
        title: "An oxford button-down in white or blue",
        reason: "The one shirt that works under a jacket and alone, in this palette.",
      },
      {
        title: "A trucker or varsity jacket",
        reason: "Adds the period detail without turning the outfit into a costume.",
      },
    ],
    priorities: [
      {
        title: "Get the denim right first",
        reason: "It is the reference every other piece in this direction is matched to.",
      },
      {
        title: "Two shirts that layer under the same jacket",
        reason: "The jacket is fixed; variety comes from underneath it.",
      },
      {
        title: "A shoe that reads casual but is not a trainer",
        reason:
          "Boat shoes, moccasins and low boots all finish this palette; running shoes do not.",
      },
    ],
    formality: 1,
    logoTolerance: 30,
    trendTolerance: 25,
    accessoryPreference: "moderate",
    neighbours: ["modern_heritage", "rugged_utility"],
  },

  european_summer: {
    displayName: "European Summer",
    coreColours: ["white", "ecru", "sand", "sky blue", "faded olive"],
    accentColours: ["terracotta", "lemon"],
    avoidColours: ["heavy black", "cold charcoal"],
    paletteNote:
      "light values throughout, because this direction is about how cloth behaves in heat",
    silhouetteHeadline: "Loose and open, with cloth that moves.",
    silhouetteDetail:
      "Linen and open-weave cotton need room or they crease into the wrong shape. A camp collar left open and a trouser with a wide, short leg are what keep this looking relaxed rather than undone.",
    signatures: [
      {
        title: "A linen camp-collar shirt",
        reason: "The defining piece, and the one that has to be real linen to work.",
      },
      {
        title: "A pair of pleated trousers in ecru or sand",
        reason: "The pleat is what gives the leg the room this direction is built around.",
      },
      {
        title: "A leather sandal or an espadrille",
        reason: "Closed shoes fight the whole palette in the season this direction is for.",
      },
    ],
    priorities: [
      {
        title: "Fabric before colour",
        reason:
          "In this direction the weave does the work; a synthetic in the right shade still reads wrong.",
      },
      {
        title: "Two trousers in light neutrals",
        reason: "The palette is narrow, so variety comes from cut rather than colour.",
      },
      {
        title: "One knit for the evening",
        reason: "The temperature drops and this wardrobe otherwise has no answer for it.",
      },
    ],
    formality: 1,
    logoTolerance: 15,
    trendTolerance: 45,
    accessoryPreference: "moderate",
    neighbours: ["smart_casual", "quiet_luxury"],
  },

  executive: {
    displayName: "Executive",
    coreColours: ["navy", "charcoal", "white", "mid grey", "pale blue"],
    accentColours: ["burgundy", "forest green"],
    avoidColours: ["washed pastels", "neon brights"],
    paletteNote:
      "a suiting palette where every colour is a business colour, so nothing has to be explained",
    silhouetteHeadline: "Cut close through the waist, clean at the shoulder.",
    silhouetteDetail:
      "Tailoring reads well when the jacket's shoulder ends where the wearer's does and the trouser breaks once. Anything looser reads as borrowed; anything tighter reads as strained.",
    signatures: [
      {
        title: "A navy suit that can be worn as separates",
        reason: "It doubles the outfits a single purchase produces.",
      },
      {
        title: "A pair of dark brown oxfords or derbies",
        reason: "More versatile than black across this palette, and less severe.",
      },
      {
        title: "A fine-gauge merino crew in charcoal",
        reason:
          "Wears under a jacket in place of a shirt, which is the direction's one relaxed move.",
      },
    ],
    priorities: [
      {
        title: "One suit that fits properly beats three that nearly do",
        reason: "Tailoring is the one category where alteration cost is part of the purchase.",
      },
      {
        title: "Shirts in exactly two colours",
        reason: "White and pale blue cover almost every occasion this direction is for.",
      },
      {
        title: "A coat cut to cover a suit jacket",
        reason: "A short coat over tailoring undoes the line the suit was cut for.",
      },
    ],
    formality: 4,
    logoTolerance: 5,
    trendTolerance: 20,
    accessoryPreference: "minimal",
    neighbours: ["quiet_luxury", "minimalist"],
  },

  creative: {
    displayName: "Creative",
    coreColours: ["black", "cream", "rust", "ink blue", "moss"],
    accentColours: ["saffron", "plum"],
    avoidColours: ["corporate mid grey", "pale blue"],
    paletteNote: "colours chosen to be noticed together, with black holding them in place",
    silhouetteHeadline: "Deliberate mismatch, one strong shape at a time.",
    silhouetteDetail:
      "This direction works by putting one unexpected cut against otherwise plain pieces — a wide trouser under a close knit, or a long coat over both. Two unexpected shapes at once read as chaos.",
    signatures: [
      {
        title: "A wide-leg trouser in a heavy cloth",
        reason: "The shape most of this direction's outfits are built against.",
      },
      {
        title: "A long unstructured coat",
        reason: "Adds the line that holds an otherwise loose outfit together.",
      },
      {
        title: "One piece in a genuinely unusual colour",
        reason: "The whole direction depends on having something to build around.",
      },
    ],
    priorities: [
      {
        title: "Build a plain base first",
        reason: "The interesting pieces only read as interesting against something quiet.",
      },
      {
        title: "One strong shape, then stop",
        reason: "It is the discipline this direction needs most and gets least.",
      },
      {
        title: "Black outerwear as the constant",
        reason: "It lets the pieces underneath change without the outfit falling apart.",
      },
    ],
    formality: 1,
    logoTolerance: 35,
    trendTolerance: 70,
    accessoryPreference: "bold",
    neighbours: ["luxury_streetwear", "minimalist"],
  },
} as const;

/**
 * Signature pieces a specific work dress code calls for, layered ON TOP of
 * the identity's own list.
 *
 * Separate from the identity table because these two inputs answer different
 * questions — identity is what a man wants to look like, dress code is what
 * the room requires — and a wardrobe has to satisfy both. When only one is
 * known, only that one contributes, which is exactly the graceful-degradation
 * behaviour P2-CORE-02 asks for.
 */
export const DRESS_CODE_SIGNATURES: Readonly<Record<string, SignatureItem>> = {
  black_tie: {
    title: "A dinner jacket that actually fits",
    reason:
      "You named black tie. Rented tailoring is visible in photographs, and these are the photographs people keep.",
  },
  formal: {
    title: "A dark suit kept for formal occasions only",
    reason:
      "You named formal occasions. Keeping one suit out of the weekly rotation is what keeps it looking new.",
  },
  business_formal: {
    title: "A second suit in a different neutral",
    reason: "You named business formal. One suit worn daily wears out at the elbows within a year.",
  },
  business_casual: {
    title: "A jacket that works without a tie",
    reason:
      "You named business casual, which is the dress code that needs a jacket and forbids a suit.",
  },
  smart_casual: {
    title: "A collared knit or overshirt",
    reason: "You named smart casual, and this is the layer that lands squarely in it.",
  },
  casual: {
    title: "A jacket that raises a t-shirt to an outfit",
    reason: "You named a casual dress code, so the mid-layer is what does all the lifting.",
  },
  ultra_casual: {
    title: "Two pairs of well-fitting jeans",
    reason:
      "You named an ultra casual dress code, which puts most of the week on a single category.",
  },
  athletic: {
    title: "Technical pieces cut like clothes, not kit",
    reason: "You named an athletic dress code, and the cut is the only thing separating the two.",
  },
};

/**
 * Women's-graph framing layered on the same StyleIdentity playbooks
 * (ADR 0019). Not a parallel identity enum and not a gender field — the
 * identity cases stay identical; only silhouette language and a few
 * signature/priority pieces change when `wardrobe_graph = womenswear`.
 */
export const WOMENSWEAR_SILHOUETTE_FRAMING =
  "A complete look can be a dress with shoes, or a top with a bottom or skirt plus shoes — both count.";

export const WOMENSWEAR_SIGNATURES: readonly SignatureItem[] = [
  {
    title: "A day dress that works with the shoes already owned",
    reason:
      "On the women's graph it is one garment that completes a look, so it earns its place faster than another top.",
  },
  {
    title: "A straight skirt in the same weight as the trousers already owned",
    reason: "It sits in the bottom role of separates days without forcing a second shoe language.",
  },
];

export const WOMENSWEAR_PRIORITIES: readonly SignatureItem[] = [
  {
    title: "Cover dress days and separates days",
    reason:
      "Wear This needs either path. Counting only tops leaves mornings without a look even when the closet is full.",
  },
];
