export {
  coWearContext,
  formalityCenter,
  loadOwnedPreferenceCoWearContext,
  preferenceContextFromRow,
} from "../_shared/scoring/ownedScoringContext.ts";
export type { WearHistoryRow, WornItemRow } from "../_shared/scoring/ownedScoringContext.ts";

const DRESS_CODE_CENTER: Readonly<Record<string, number>> = {
  ultra_casual: 0,
  casual: 25,
  athletic: 25,
  smart_casual: 50,
  business_casual: 50,
  business_formal: 75,
  formal: 75,
  black_tie: 100,
};

export function dressCodeCenter(value: unknown): number | null {
  return typeof value === "string" ? DRESS_CODE_CENTER[value] ?? null : null;
}

export function resolveTargetFormality(
  dressCode: unknown,
  request: string | undefined,
): number | null {
  return dressCodeCenter(dressCode) ?? inferRequestFormality(request);
}

/** Deterministic interpretation of the same event/request vocabulary used by Home's schedule snapshot. */
export function inferRequestFormality(request: string | undefined): number | null {
  if (!request) return null;
  // Home appends a separate context block to this field. Only the user's
  // request text should set the occasion target; profile preferences such as
  // "formality: formal" are already scored by §2.6 and are not an event.
  const metadataStart = request.search(
    /\b(?:Date|Wardrobe direction|Style|Weather|Today's calendar):/i,
  );
  const userText = metadataStart < 0 ? request : request.slice(0, metadataStart);
  const negated = userText.replace(
    /\b(?:not|no|without|avoid(?:ing)?|don't|do not)(?:\s+\w+){0,6}\s+(?:black\s+tie|very\s+formal|formal|dressy|dress\s+up|more\s+formal|less\s+formal|smart\s+casual|business\s+casual|very\s+casual|more\s+casual|casual|gala|wedding|interview|client\s+meeting|presentation|board\s+meeting|court|meeting|office|work|conference|date\s+night|date|dinner|restaurant|drinks|gym|workout|run|practice)\b/gi,
    " ",
  );
  const text = negated.toLowerCase();
  const matches: readonly [number, readonly string[]][] = [
    [100, ["black tie", "gala", "wedding", "very formal"]],
    [75, [
      "interview",
      "client meeting",
      "presentation",
      "board meeting",
      "court",
      "dressy",
      "dress up",
      "more formal",
      "formal",
    ]],
    [50, ["smart casual", "business casual", "meeting", "office", "work", "conference"]],
    [0, ["very casual", "gym", "workout", "run", "practice"]],
    [25, [
      "date night",
      "date",
      "dinner",
      "restaurant",
      "drinks",
      "more casual",
      "less formal",
      "casual",
    ]],
  ];
  for (const [center, phrases] of matches) {
    if (
      phrases.some((phrase) =>
        new RegExp(`(^|[^a-z])${phrase.replaceAll(" ", "\\s+")}([^a-z]|$)`).test(text)
      )
    ) {
      return center;
    }
  }
  return null;
}
