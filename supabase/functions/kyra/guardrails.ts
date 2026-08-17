// ============================================================================
// kyra/guardrails.ts
// ============================================================================
// docs/06 §2's "WHAT YOU NEVER DO" as an ENFORCED validation layer
// (P5-KYRA-12) — not prompt text. The system prompt asks the model to behave;
// this module runs after every turn and makes the prohibited outcomes
// unrepresentable on the wire, because ADR 0004's whole argument for the Edge
// Function boundary is that guardrails must not depend on a model's
// cooperation. Same duplication-on-purpose `style-dna/handler.ts` practices.
//
// Enforcement is deterministic pattern/structure checking. That has known
// limits — a regex cannot read intent — so every check is tuned to fail in
// the SAFE direction for its category:
//   - Medical/body-change and sensitive-trait violations REPLACE the whole
//     response with an in-voice redirect: a partially-scrubbed answer built
//     around a prohibited premise is still built around it.
//   - Fit-certainty violations REWRITE the offending claims to hedged
//     equivalents, append the §2-mandated caveat, and cap `confidence` below
//     0.6 (docs/06 §6's fit-certainty row) — the answer survives, the
//     overclaim does not.
//   - Unlabelled generated-image references and missing affiliate
//     disclosures APPEND the required labelling in Kyra's own words — the
//     §2 requirement is that the label is present in the same turn, and
//     adding it is strictly safe.
//   - Hallucinated references (a card naming a closet item / outfit /
//     product id that no tool returned and no packet contained) DROP the
//     card. Absent is honest; a card pointing at a row that does not exist
//     is the single most damaging correctness failure this system can
//     produce (docs/06 §7.3 treats any nonzero rate as a P1).
//   - Sponsored-reordering cannot be unfixed after the model has already
//     read the mis-ordered list, so it is DETECTED and reported (the real
//     `search_products` implementation must order organically before
//     results ever reach the model; its stub returns nothing today). The
//     detector exists now so the contract has a test the Phase 6
//     implementation inherits.
//
// One test per prohibited category lives in `guardrails_test.ts`.
// ============================================================================

import type { KyraCardWire, KyraStructuredResponse } from "./schema.ts";
import type { ToolExecution } from "./tools/registry.ts";

export type GuardrailViolation =
  | "medical_body_advice"
  | "sensitive_trait_inference"
  | "fit_certainty_claim"
  | "generated_image_unlabelled"
  | "affiliate_disclosure_missing"
  | "sponsored_reordering"
  | "sponsored_labelling_missing"
  | "hallucinated_reference";

export interface GuardrailInput {
  readonly response: KyraStructuredResponse;
  readonly toolTrace: readonly ToolExecution[];
  /** Ids the packet or a tool result actually surfaced this turn. */
  readonly knownClosetItemIds: ReadonlySet<string>;
  readonly knownOutfitIds: ReadonlySet<string>;
  readonly knownProductCandidateIds: ReadonlySet<string>;
}

export interface GuardrailOutcome {
  readonly response: KyraStructuredResponse;
  readonly violations: readonly GuardrailViolation[];
}

// ---------------------------------------------------------------------------
// Sensitive-trait inference (§2: never infer or state)
// ---------------------------------------------------------------------------

// Statements ABOUT the user's traits — "you are/seem/might be <trait>" — not
// mere topic mentions, so a legitimate dress-code answer ("church wedding
// dress codes usually mean...") does not trip it.
const SENSITIVE_TRAIT_PATTERN =
  /\b(you( a|')re|you are|you seem|you appear( to be)?|you might be|you must be|you look|user (is|seems|appears|might be)|he (is|seems|appears|might be))\s+(probably\s+|likely\s+|clearly\s+)?(gay|straight|bisexual|trans(gender)?|muslim|christian|jewish|hindu|buddhist|religious|conservative|liberal|republican|democrat|pregnant|diabetic|depressed|anxious|anorexic|bulimic|autistic|disabled|an? (undocumented|illegal) immigrant|undocumented)\b/i;

/**
 * Shared with `tools/savePreference.ts`, which refuses to persist such
 * content at the write — the same trait must be unstatable and unstorable.
 */
export function containsSensitiveTraitInference(text: string): boolean {
  return SENSITIVE_TRAIT_PATTERN.test(text);
}

// ---------------------------------------------------------------------------
// Medical / body-change advice (§2: never give it)
// ---------------------------------------------------------------------------

const MEDICAL_ADVICE_PATTERN =
  /\b((lose|losing|drop|dropping|shed|shedding)\s+(some\s+|a few\s+|the\s+)?(weight|pounds|lbs|kilos|kg)|calorie[s]?|caloric deficit|diet(ing)? plan|intermittent fasting|keto\b|supplement[s]?\b|protein (intake|shake)|build muscle|bulk(ing)? up|burn(ing)? fat|fat.burn|liposuction|botox|cosmetic surgery)\b/i;

// A proper §6 decline MENTIONS the topic while refusing it. These markers
// distinguish "I can't help with that side of it" from advice.
const DECLINE_MARKER_PATTERN =
  /\b(can't help with|cannot help with|can't advise|not something I (can|do)|outside what I|isn't something I|I don't give|I can't speak to|that side of it)\b/i;

function givesMedicalBodyAdvice(message: string): boolean {
  return MEDICAL_ADVICE_PATTERN.test(message) && !DECLINE_MARKER_PATTERN.test(message);
}

// ---------------------------------------------------------------------------
// Fit-certainty claims (§2: never claim certainty from imagery/description)
// ---------------------------------------------------------------------------

const FIT_CERTAINTY_REWRITES: ReadonlyArray<readonly [RegExp, string]> = [
  [/\bguaranteed to fit( you)?( perfectly)?\b/gi, "likely to fit well"],
  [/\bguarantees? (a |the )?(perfect )?fit\b/gi, "points toward a good fit"],
  [/\bwill (definitely|certainly|absolutely) fit( you)?( perfectly)?\b/gi, "should fit"],
  [/\bwill fit( you)? perfectly\b/gi, "should fit well"],
  [/\bfits? you perfectly\b/gi, "should sit well on you"],
  [/\b(a |the )perfect fit\b/gi, "a strong fit on paper"],
  [/\bdefinitely (your|the right) size\b/gi, "probably the right size"],
];

const FIT_CAVEAT =
  "I can't promise the exact fit without you trying it — but the size and cut point in the " +
  "right direction.";

/** docs/06 §6: an inherently-uncertain fit claim keeps confidence below 0.6. */
const FIT_CONFIDENCE_CAP = 0.5;

// ---------------------------------------------------------------------------
// Generated-image labelling (§2: an estimate, every time it's referenced)
// ---------------------------------------------------------------------------

const IMAGE_LABEL_PATTERN = /\b(estimate|not a guarantee)\b/i;
const IMAGE_LABEL =
  "A generated preview is always an estimate of how this could look — not a guarantee of fit " +
  "or finish.";

function traceHasRealStudioGeneration(trace: readonly ToolExecution[]): boolean {
  return trace.some(
    (execution) =>
      execution.name === "generate_studio_preview" &&
      execution.result["error"] === undefined &&
      execution.result["generation_id"] !== undefined,
  );
}

// ---------------------------------------------------------------------------
// Affiliate disclosure + sponsored/organic separation (§2, spec §17)
// ---------------------------------------------------------------------------

const DISCLOSURE_PATTERN = /\b(commission|affiliate)\b/i;
const DISCLOSURE =
  "Heads up — I may earn a small commission if you buy through a link here. It doesn't " +
  "change what I'd recommend.";

interface TraceProduct {
  readonly isSponsored: boolean | undefined;
  readonly hasAffiliateUrl: boolean;
  readonly relevance: number | null;
}

/** Pulls product entries out of any tool result carrying a `products` array. */
function traceProducts(trace: readonly ToolExecution[]): TraceProduct[] {
  const products: TraceProduct[] = [];
  for (const execution of trace) {
    const list = execution.result["products"];
    if (!Array.isArray(list)) continue;
    for (const entry of list) {
      if (typeof entry !== "object" || entry === null || Array.isArray(entry)) continue;
      const record = entry as Record<string, unknown>;
      const sponsored = record["is_sponsored"];
      const relevance = record["relevance"] ?? record["compatibility_score"];
      products.push({
        isSponsored: typeof sponsored === "boolean" ? sponsored : undefined,
        hasAffiliateUrl: typeof record["affiliate_url"] === "string" &&
          record["affiliate_url"].length > 0,
        relevance: typeof relevance === "number" ? relevance : null,
      });
    }
  }
  return products;
}

/**
 * A sponsored entry ranked above an organic entry with strictly higher
 * relevance is a reordering violation: labelling is allowed, promotion in
 * rank is not (docs/06 §3.5, spec §17).
 */
function detectSponsoredReordering(products: readonly TraceProduct[]): boolean {
  for (let i = 0; i < products.length; i++) {
    const candidate = products[i]!;
    if (candidate.isSponsored !== true || candidate.relevance === null) continue;
    for (let j = i + 1; j < products.length; j++) {
      const later = products[j]!;
      if (
        later.isSponsored === false && later.relevance !== null &&
        later.relevance > candidate.relevance
      ) {
        return true;
      }
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Hallucinated references
// ---------------------------------------------------------------------------

function cardReferenceIsKnown(card: KyraCardWire, input: GuardrailInput): boolean {
  switch (card.type) {
    case "outfit":
      return input.knownOutfitIds.has(card.outfit_id);
    case "closet_item":
      return input.knownClosetItemIds.has(card.closet_item_id);
    case "product":
      return input.knownProductCandidateIds.has(card.product_candidate_id);
    case "comparison_table":
    case "action":
      // No row reference to verify; tables carry text, actions carry labels.
      return true;
  }
}

// ---------------------------------------------------------------------------
// Forced replacements, in Kyra's voice (docs/06 §6's exact register)
// ---------------------------------------------------------------------------

const MEDICAL_REDIRECT =
  "I can't help with that side of it — what someone eats or does with their body isn't " +
  "styling, and I don't give that kind of advice. What I can do is help you dress in a way " +
  "that feels sharper for this, exactly as you are right now. Want me to?";

const SENSITIVE_TRAIT_REDIRECT =
  "That's not something I'd read into, and it wouldn't help me dress you better anyway. " +
  "Tell me the occasion and the look you're after, and I'll work from there.";

function forcedReplacement(
  original: KyraStructuredResponse,
  message: string,
): KyraStructuredResponse {
  return {
    message,
    intent: "general",
    // Cards built around a prohibited premise do not survive the premise.
    cards: [],
    suggested_actions: [],
    // Memory proposals reflect writes that actually happened this turn
    // (handler builds them from the tool trace); hiding them would violate
    // §4.4's visibility requirement, so they ride through the replacement.
    memory_proposals: original.memory_proposals,
    confidence: 0.3,
  };
}

// ---------------------------------------------------------------------------
// The layer
// ---------------------------------------------------------------------------

export function applyGuardrails(input: GuardrailInput): GuardrailOutcome {
  const violations: GuardrailViolation[] = [];
  let response = input.response;

  // 1. Hallucinated references: drop unverifiable cards first, so a
  //    later replacement never resurrects them.
  const keptCards: KyraCardWire[] = [];
  for (const card of response.cards) {
    if (cardReferenceIsKnown(card, input)) keptCards.push(card);
    else if (!violations.includes("hallucinated_reference")) {
      violations.push("hallucinated_reference");
    }
  }
  if (keptCards.length !== response.cards.length) {
    response = {
      ...response,
      cards: keptCards,
      // The dropped card was part of the answer's substance; the remaining
      // text may lean on it. The message survives, the stated certainty
      // does not.
      confidence: Math.min(response.confidence, 0.5),
    };
  }

  // 2. Whole-response replacements. Checked on message + memory contents;
  //    proposals themselves are pre-screened at the write (savePreference),
  //    so a violating proposal here means the screen was bypassed — same
  //    forced outcome either way.
  const textsToScreen = [
    response.message,
    ...response.memory_proposals.map((proposal) => proposal.content),
  ];
  if (textsToScreen.some(containsSensitiveTraitInference)) {
    violations.push("sensitive_trait_inference");
    response = forcedReplacement(response, SENSITIVE_TRAIT_REDIRECT);
    response = {
      ...response,
      memory_proposals: response.memory_proposals.filter(
        (proposal) => !containsSensitiveTraitInference(proposal.content),
      ),
    };
  } else if (givesMedicalBodyAdvice(response.message)) {
    violations.push("medical_body_advice");
    response = forcedReplacement(response, MEDICAL_REDIRECT);
  }

  // 3. Fit-certainty rewrite. Detected via replace-and-compare rather than
  //    `.test()`: these are `/g` regexes shared across requests, and `.test`
  //    on a global regex mutates its `lastIndex`, silently skipping matches
  //    on the next call. `String.replace` always scans from the start.
  let message = response.message;
  let hadFitClaim = false;
  for (const [pattern, replacement] of FIT_CERTAINTY_REWRITES) {
    const rewritten = message.replace(pattern, replacement);
    if (rewritten !== message) {
      hadFitClaim = true;
      message = rewritten;
    }
  }
  if (hadFitClaim) {
    violations.push("fit_certainty_claim");
    response = {
      ...response,
      message: `${message} ${FIT_CAVEAT}`,
      confidence: Math.min(response.confidence, FIT_CONFIDENCE_CAP),
    };
  }

  // 4. Generated-image labelling: only when a REAL generation happened this
  //    turn (the Phase 5 stub cannot produce one) and the label is absent.
  if (
    traceHasRealStudioGeneration(input.toolTrace) && !IMAGE_LABEL_PATTERN.test(response.message)
  ) {
    violations.push("generated_image_unlabelled");
    response = { ...response, message: `${response.message} ${IMAGE_LABEL}` };
  }

  // 5. Affiliate disclosure + sponsored/organic separation over whatever
  //    product payloads tools actually returned this turn.
  const products = traceProducts(input.toolTrace);
  if (
    products.some((product) => product.hasAffiliateUrl) &&
    !DISCLOSURE_PATTERN.test(response.message)
  ) {
    violations.push("affiliate_disclosure_missing");
    response = { ...response, message: `${response.message} ${DISCLOSURE}` };
  }
  if (products.some((product) => product.isSponsored === undefined)) {
    violations.push("sponsored_labelling_missing");
  }
  if (detectSponsoredReordering(products)) {
    violations.push("sponsored_reordering");
    response = { ...response, confidence: Math.min(response.confidence, 0.5) };
  }

  return { response, violations };
}
