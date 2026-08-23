/**
 * Which required-role sets an outfit must fill (ADR 0019).
 *
 * Men's graph is unchanged: top + bottom + shoes. Women's graph accepts
 * dress + shoes OR top + bottom + shoes. Unlocks ranking stays
 * `computeUnlockCount`; only these role sets change.
 */

import type { GarmentRole } from "./types.ts";

export type WardrobeGraphId = "menswear_3_role" | "womenswear";

export function parseWardrobeGraph(value: unknown): WardrobeGraphId {
  return value === "womenswear" ? "womenswear" : "menswear_3_role";
}

const MENSWEAR_SET: readonly GarmentRole[] = ["top", "bottom", "shoes"];
const WOMENSWEAR_DRESS_SET: readonly GarmentRole[] = ["dress", "shoes"];
const WOMENSWEAR_SEPARATES_SET: readonly GarmentRole[] = ["top", "bottom", "shoes"];

/** Beams for Wear This / generate (no anchor). */
export function requiredRoleSetsForGeneration(
  graph: WardrobeGraphId,
): readonly (readonly GarmentRole[])[] {
  if (graph === "womenswear") {
    return [WOMENSWEAR_DRESS_SET, WOMENSWEAR_SEPARATES_SET];
  }
  return [MENSWEAR_SET];
}

/**
 * Roles still to fill after the anchor occupies its slot.
 * Women's shoes try both a dress fill and a separates fill.
 */
export function requiredRoleSetsForAnchor(
  anchor: GarmentRole,
  graph: WardrobeGraphId,
): readonly (readonly GarmentRole[])[] {
  const withoutAnchor = (set: readonly GarmentRole[]): GarmentRole[] =>
    set.filter((role) => role !== anchor);

  if (graph !== "womenswear") {
    return [withoutAnchor(MENSWEAR_SET)];
  }

  switch (anchor) {
    case "dress":
      return [withoutAnchor(WOMENSWEAR_DRESS_SET)];
    case "shoes":
      return [
        withoutAnchor(WOMENSWEAR_DRESS_SET),
        withoutAnchor(WOMENSWEAR_SEPARATES_SET),
      ];
    case "top":
    case "bottom":
      return [withoutAnchor(WOMENSWEAR_SEPARATES_SET)];
    default:
      return [
        withoutAnchor(WOMENSWEAR_DRESS_SET),
        withoutAnchor(WOMENSWEAR_SEPARATES_SET),
      ];
  }
}

/** Locked required roles that a beam cannot satisfy make that beam unusable. */
export function roleSetAcceptsLocks(
  set: readonly GarmentRole[],
  lockedRoles: readonly GarmentRole[],
): boolean {
  for (const role of lockedRoles) {
    if (role === "outerwear" || role === "accessory") continue;
    if (!set.includes(role)) return false;
  }
  return true;
}
