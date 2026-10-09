import {
  type ClosetItemMapperRow,
  mapClosetItemRowToScorableItem,
} from "../_shared/scoring/closetItemMapper.ts";
import { labFromLCh } from "../_shared/scoring/redundancy.ts";
import type { OwnedGarment } from "./handler.ts";

/** Maps one caller-owned closet row onto product evaluation's two score shapes. */
export function mapOwnedGarmentForProductEvaluation(
  row: ClosetItemMapperRow,
): OwnedGarment | null {
  const scorable = mapClosetItemRowToScorableItem(row);
  if (scorable === null) return null;

  return {
    scorable,
    redundancy: {
      id: scorable.id,
      category: scorable.category,
      role: scorable.role,
      primaryColorLab: scorable.primaryColor ? labFromLCh(scorable.primaryColor) : null,
      formalityScore: scorable.formalityScore,
      fit: scorable.fit,
      materials: scorable.materials,
      seasonality: scorable.seasonality,
    },
  };
}
