// ============================================================================
// outfits/reason.ts
// ============================================================================
// Turns a `CompatibilityScore` into the one sentence `ScoredOutfitWire.reason`
// carries. Shared by `/generate` and `/rank` (`handler.ts`) so the two
// endpoints cannot drift into describing the same score two different ways.
//
// THE RULE THIS FILE EXISTS TO ENFORCE, FROM CLAUDE.md: "absent is honest; a
// confounded reading is not." `CompatibilityScore.components[x].degraded` is
// non-empty exactly when that component fell back to a prior instead of
// measuring something — and a sentence built from a prior is not a claim
// about the garments, it is a claim about the DEFAULT. So `buildReason` only
// ever reads a component whose OWN `degraded` list (not the outfit-level
// one) is empty. Nothing here checks `score.degraded` directly, because that
// list is deduplicated text, not a per-component flag — `components[x]`'s own
// `degraded` array is the thing that actually answers "can I say this?".
//
// OCCASION IS DELIBERATELY EXCLUDED FROM THE PHRASE TABLE, EVEN THOUGH IT CAN
// BE "MEASURED". `context.ts`'s `occasionSubscore` returns `measured(0.8)` —
// not degraded — for the overwhelmingly common case where nobody asked about
// an occasion at all (§2.8: "penalising an outfit for failing to match an
// occasion nobody named"). That reading is honest as a SCORE contribution but
// would be misleading as a SENTENCE: "it matches the occasion" implies the
// caller named one. Nothing in a `Subscore` distinguishes "genuinely matched
// occasion X" from "no occasion was asked about", so the only way to avoid
// manufacturing that implication is to never phrase this component at all —
// this endpoint's call sites never populate `ScoringContext.targetOccasion`
// today (see `handler.ts`'s header), which makes the omission moot in
// practice, but the rule holds regardless of that.
//
// THE FALLBACK IS DELIBERATELY STRUCTURAL, NOT A SCORE CLAIM. When every
// phraseable component is degraded (the coldest of cold starts: no colours
// read, no formality classified, no fit recorded), the honest sentence is
// about the one thing that is always true and always measured —
// `availability`'s subscore is `measured()` unconditionally (see
// `context.ts`; it has no degraded branch at all) — so falling back to a
// plain "from what you own" line is never a claim resting on a prior.
// ============================================================================

import type { CompatibilityScore, ComponentName } from "../_shared/scoring/compatibility.ts";
import type { GarmentRole, ScorableItem } from "../_shared/scoring/types.ts";

/**
 * One phrase per component, in the order they are tried. Order follows §10's
 * own weights (heaviest first) so that when several components are safely
 * measured, the sentence leads with the one that mattered most to the score.
 */
const PHRASE_ORDER: readonly ComponentName[] = [
  "color",
  "formality",
  "silhouette",
  "seasonWeather",
  "userPreference",
  "coWear",
];

/** The value a component must clear before it is worth naming out loud. */
const STRONG_ENOUGH = 0.8;

const PHRASES: Partial<Record<ComponentName, string>> = {
  color: "the colors work well together",
  formality: "the formality lines up",
  silhouette: "the fits balance each other",
  seasonWeather: "it suits today's weather",
  userPreference: "it fits what you've told us you like",
  coWear: "you've worn pieces like these together before",
};

const ROLE_LABEL: Record<GarmentRole, string> = {
  top: "top",
  bottom: "bottom",
  outerwear: "outerwear",
  shoes: "shoes",
  accessory: "accessory",
};

/** Irregular/uncountable plurals `${role}s` would get wrong. */
const ROLE_LABEL_PLURAL: Record<GarmentRole, string> = {
  top: "tops",
  bottom: "bottoms",
  outerwear: "outerwear pieces",
  shoes: "shoes",
  accessory: "accessories",
};

function capitalize(text: string): string {
  return text.length === 0 ? text : text[0]!.toUpperCase() + text.slice(1);
}

function uniqueColorNames(items: readonly ScorableItem[]): string[] {
  const seen = new Set<string>();
  const names: string[] = [];
  for (const item of items) {
    const raw = item.colorName?.trim();
    if (raw == null || raw === "") continue;
    const key = raw.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    names.push(capitalize(raw));
  }
  return names;
}

function listWords(words: readonly string[]): string {
  switch (words.length) {
    case 0:
      return "";
    case 1:
      return words[0]!;
    case 2:
      return `${words[0]} and ${words[1]}`;
    default: {
      const head = words.slice(0, -1).join(", ");
      return `${head}, and ${words[words.length - 1]}`;
    }
  }
}

/**
 * Colour copy names the words on the garments, not a generic "the colors
 * work." Two named colours is the honest sentence; one named colour is not
 * a pairing; zero falls back to the generic phrase so a measured-but-unnamed
 * score is still sayable.
 */
function colorPhrase(items: readonly ScorableItem[]): string {
  const names = uniqueColorNames(items);
  if (names.length >= 2) return `${listWords(names)} work together`;
  return PHRASES.color!;
}

function phraseFor(name: ComponentName, items: readonly ScorableItem[]): string | undefined {
  if (name === "color") return colorPhrase(items);
  return PHRASES[name];
}

/** The structural fallback: true of every outfit this function is ever called with, and never a scored claim. */
function structuralFallback(items: readonly ScorableItem[]): string {
  const roleCounts = new Map<GarmentRole, number>();
  for (const item of items) {
    roleCounts.set(item.role, (roleCounts.get(item.role) ?? 0) + 1);
  }
  const parts = [...roleCounts.entries()]
    .map(([role, count]) => count > 1 ? `${count} ${ROLE_LABEL_PLURAL[role]}` : ROLE_LABEL[role]);
  return `From what you own: ${parts.join(", ")}.`;
}

/**
 * Builds a one-sentence reason, defensible entirely from components this
 * particular score actually measured. Picks up to two of the highest-weight
 * measured components that clear `STRONG_ENOUGH`, in `PHRASE_ORDER`.
 */
export function buildReason(
  items: readonly ScorableItem[],
  score: CompatibilityScore,
): string {
  const claims: string[] = [];
  for (const name of PHRASE_ORDER) {
    const component = score.components[name];
    if (component.degraded.length > 0) continue; // not defensible — see header
    if (component.value < STRONG_ENOUGH) continue;
    const phrase = phraseFor(name, items);
    if (!phrase) continue;
    claims.push(phrase);
    if (claims.length >= 2) break;
  }

  if (claims.length === 0) {
    return structuralFallback(items);
  }
  return capitalize(claims.join(" and ")) + ".";
}
