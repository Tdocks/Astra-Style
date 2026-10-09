/** Server-owned confirmation context. Never populate this from tool arguments.
 * A pending prompt must be bound to the exact normalized preview selection.
 */
export interface PendingStudioConfirmation {
  selectionKey: string;
  askedAboutGenerationCost: boolean;
}

export function studioGenerationConfirmed(
  userText: string,
  selectionKey: string,
  pending: PendingStudioConfirmation | null,
): boolean {
  const text = userText.trim().toLowerCase().replace(/[’]/g, "'");
  if (
    !text || /^(no|nope|nah|cancel|stop)\b/.test(text) ||
    /\b(don't|do not|never)\b.{0,60}\b(generate|create|show|spend|use|charge)\b/.test(text)
  ) return false;
  // A yes is meaningful only for the same selection and an explicit cost prompt.
  if (/^(yes|yeah|yep|sure|go ahead|please do|do it)[.!\s]*$/.test(text)) {
    return pending?.askedAboutGenerationCost === true && pending.selectionKey === selectionKey;
  }
  // Direct imperatives are confirmation; questions about capability or advice
  // must not initiate a paid job. Photo consent remains a separate requirement.
  return /^(please\s+)?(generate|create|make)\s+(me\s+)?(an?\s+|this\s+|the\s+)?(studio\s+|outfit\s+)?(preview|image)(\s+(of|for)\s+(this|that|the outfit))?(\s+on me)?[.!\s]*$/
    .test(text) ||
    /^(please\s+)?show me\s+(this|that|the outfit|these clothes)\s+on me[.!\s]*$/.test(text);
}
