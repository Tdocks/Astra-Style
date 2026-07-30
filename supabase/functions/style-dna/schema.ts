// ============================================================================
// style-dna/schema.ts
// ============================================================================
// The wire contract for `POST /style-dna/generate` (spec §14, ticket
// P2-CORE-02), plus the validator every provider's output must pass before
// anything is persisted or returned.
//
// THE RESPONSE MAPS 1:1 ONTO SPEC §6.10's SCREEN. That is P2-CORE-02's first
// acceptance criterion, so the mapping is written out here rather than left
// to be inferred:
//
//   §6.10 "Primary style identity"        -> primary_identity (+ identity_basis)
//   §6.10 "Secondary influences"          -> secondary_influences
//   §6.10 "Preferred palette"             -> palette
//   §6.10 "Best silhouette direction"     -> silhouette
//   §6.10 "Signature item opportunities"  -> signature_opportunities
//   §6.10 "Initial wardrobe priorities"   -> wardrobe_priorities
//
// Four fields beyond the six sections carry the §6.10 summary that
// `style_profiles` stores as columns — formality_preference, logo_tolerance,
// trend_tolerance, accessory_preference. Per
// 20260730180000_style_preference_vector.sql those columns are THIS
// endpoint's output, "a considered read across goals, identity, lifestyle AND
// this vector", which is why they appear here and nowhere in
// `profile/complete-onboarding`.
//
// Three more (known_inputs, open_questions, measured_dimensions) exist for
// one reason: sparse input is the normal case, not the edge case. Five of the
// eight preference dimensions have no imagery today
// (docs/03-progress.md blocker 4), so most Style DNA is generated from an
// identity, a dress code, and three measured axes. A result that does not say
// what it was built from — and what would sharpen it — is indistinguishable
// from one built from everything, and that indistinguishability is exactly
// how "generic output that reads as complete" ships without anyone noticing.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import { isRecord } from "../_shared/validation.ts";

/** Index into `FORMALITY_LEVELS`, matching `FormalityLevel.ordinal` on the client. */
export type FormalityOrdinal = 0 | 1 | 2 | 3 | 4;

/** `formality_preference` (Postgres enum), ordered casual -> formal. */
export const FORMALITY_LEVELS = [
  "very_casual",
  "casual",
  "balanced",
  "formal",
  "very_formal",
] as const;

export type FormalityValue = typeof FORMALITY_LEVELS[number];

/** `accessory_preference` (Postgres enum), ordered by how much they do. */
export const ACCESSORY_PREFERENCES = ["minimal", "moderate", "bold"] as const;

export type AccessoryPreferenceValue = typeof ACCESSORY_PREFERENCES[number];

export interface NamedRecommendation {
  title: string;
  reason: string;
}

export interface RankedRecommendation extends NamedRecommendation {
  rank: number;
}

export interface PaletteDTO {
  preferred_colors: string[];
  avoided_colors: string[];
  rationale: string;
}

export interface SilhouetteDTO {
  headline: string;
  detail: string;
}

/**
 * The provider's own output, before the handler stamps provenance on it.
 * Split from `StyleDnaDTO` so `generated_at` and `model_identifier` cannot be
 * claimed by a provider — they are facts about the call, recorded by the
 * caller, and a provider that could set them could misattribute its own
 * output.
 */
export interface StyleDnaDocument {
  primary_identity: string | null;
  /**
   * Which input produced the identity, in the user's own terms ("the three
   * identities you picked", "your work dress code, since the identity step
   * was skipped"). Present so the screen can be honest about an inferred
   * identity instead of presenting a guess in the same voice as a choice.
   */
  identity_basis: string;
  secondary_influences: string[];
  palette: PaletteDTO;
  silhouette: SilhouetteDTO;
  signature_opportunities: NamedRecommendation[];
  wardrobe_priorities: RankedRecommendation[];
  summary: string;
  formality_preference: FormalityValue;
  logo_tolerance: number;
  trend_tolerance: number;
  accessory_preference: AccessoryPreferenceValue;
  known_inputs: string[];
  open_questions: string[];
  measured_dimensions: string[];
}

export interface StyleDnaDTO extends StyleDnaDocument {
  generated_at: string;
  /**
   * The exact model/version string behind this result. Provider-neutral by
   * construction — it is whatever the adapter reports, and the client only
   * ever stores or displays it, never branches on it. Present because a
   * quality regression that cannot be attributed to a version is a quality
   * regression nobody can fix.
   */
  model_identifier: string;
}

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

/** Parses the outer `AstraRequestEnvelope` and returns its (still-raw) `body`. */
export function parseEnvelope(raw: unknown): { requestId?: string; body: unknown } {
  if (!isRecord(raw)) {
    throw badRequest("Request body must be a JSON object.");
  }
  if (!("body" in raw)) {
    throw badRequest('Request envelope is missing the required "body" field.');
  }
  const requestId = typeof raw["request_id"] === "string" ? raw["request_id"] : undefined;
  return { requestId, body: raw["body"] };
}

/**
 * Validates the request body, which is empty by design.
 *
 * `LiveProfileRepository.generateStyleDNA()` sends `AstraEmptyPayload` — `{}`
 * — and that is the right shape: this endpoint reads the user's stored
 * profile, so every input it needs is already server-side and nothing the
 * client could send would be more trustworthy than what is in the database.
 * §6.10's "allow user to edit and regenerate" works by writing the edit
 * through `ProfileRepository.updateStyleProfile` first and then calling this,
 * rather than by carrying edits in this request — one write path instead of
 * two that could disagree.
 *
 * A non-object body is still rejected rather than ignored: silently accepting
 * anything trains a client to send anything.
 */
export function parseGenerateStyleDnaBody(rawBody: unknown): Record<string, never> {
  if (rawBody === undefined || rawBody === null) {
    return {};
  }
  if (!isRecord(rawBody)) {
    throw badRequest('Request envelope must contain a JSON object at "body".');
  }
  return {};
}

// ---------------------------------------------------------------------------
// Provider output validation
// ---------------------------------------------------------------------------
//
// WHY THIS EXISTS EVEN THOUGH TODAY'S PROVIDER IS DETERMINISTIC.
//
// The deterministic provider cannot produce a malformed document — it builds
// one in TypeScript. This validator is not for it. It is the seam a live
// provider lands behind: `docs/09-model-routing.md` §2.2 specifies a
// repair-retry path that fires when "the response fails JSON Schema
// validation against the call's response schema", and that path needs a
// validator that already exists and is already exercised. Writing it later,
// against the first live adapter, would mean the first time this code runs is
// against real user data.
//
// It is also the guardrail boundary ADR 0004 describes: a model's output
// reaches the client only after passing through code the client cannot route
// around. An identity the model invented, a formality value outside the
// Postgres enum, or a wardrobe priority list of two hundred items all stop
// here rather than at an INSERT or on a user's screen.

const MAX_LIST = 12;
const MAX_TITLE = 200;
const MAX_REASON = 400;
const MAX_SUMMARY = 1200;

function requireString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string") {
    throw providerContractError(`${field} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw providerContractError(`${field} must not be empty.`);
  }
  if (trimmed.length > maxLength) {
    throw providerContractError(`${field} must be at most ${maxLength} characters.`);
  }
  return trimmed;
}

function requireStringList(value: unknown, field: string, maxLength: number): string[] {
  if (!Array.isArray(value)) {
    throw providerContractError(`${field} must be an array.`);
  }
  if (value.length > MAX_LIST) {
    throw providerContractError(`${field} must contain at most ${MAX_LIST} items.`);
  }
  return value.map((entry, index) => requireString(entry, `${field}[${index}]`, maxLength));
}

function requireBoundedInt(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw providerContractError(`${field} must be a number.`);
  }
  const rounded = Math.round(value);
  if (rounded < min || rounded > max) {
    throw providerContractError(`${field} must be between ${min} and ${max}.`);
  }
  return rounded;
}

function requireEnum<T extends string>(value: unknown, field: string, allowed: readonly T[]): T {
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    throw providerContractError(`${field} must be one of: ${allowed.join(", ")}.`);
  }
  return value as T;
}

/**
 * A provider produced something this endpoint cannot use.
 *
 * Category "provider" (HTTP 502) rather than "server": the client maps it to
 * `AstraError.Category.provider`, which is retryable
 * (`AstraError.isRetryable`), and a retry is the correct user-visible
 * behaviour for a model that produced one bad document. It is deliberately
 * NOT "validation" — nothing about the user's request was wrong, and telling
 * him it was would send him to change an answer that was fine.
 */
function providerContractError(detail: string): Error {
  return new StyleDnaContractError(detail);
}

export class StyleDnaContractError extends Error {
  constructor(detail: string) {
    super(detail);
    this.name = "StyleDnaContractError";
  }
}

function parseNamedRecommendation(raw: unknown, field: string): NamedRecommendation {
  if (!isRecord(raw)) {
    throw providerContractError(`${field} must be a JSON object.`);
  }
  return {
    title: requireString(raw["title"], `${field}.title`, MAX_TITLE),
    reason: requireString(raw["reason"], `${field}.reason`, MAX_REASON),
  };
}

/**
 * Validates a provider's raw JSON string into a `StyleDnaDocument`.
 *
 * `allowedIdentities` is passed in rather than imported so the caller decides
 * what counts — the handler passes the ten values of the `style_identity`
 * Postgres enum, and a document naming an eleventh is rejected here rather
 * than failing at the UPDATE with a 22P02.
 */
export function parseStyleDnaDocument(
  rawJson: string,
  allowedIdentities: readonly string[],
): StyleDnaDocument {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJson);
  } catch {
    throw providerContractError("Provider output was not valid JSON.");
  }
  if (!isRecord(parsed)) {
    throw providerContractError("Provider output must be a JSON object.");
  }

  // `null` is a legitimate value: a user who somehow reached this endpoint
  // with no identity and no dress code has no identity to report, and
  // inventing one would be the exact failure this endpoint is written to
  // avoid. An identity that is present but unrecognised is a different
  // thing — that is a provider fabricating a value — and is rejected.
  let primaryIdentity: string | null = null;
  const rawIdentity = parsed["primary_identity"];
  if (rawIdentity !== null && rawIdentity !== undefined) {
    primaryIdentity = requireEnum(rawIdentity, "primary_identity", allowedIdentities);
  }

  const secondaryRaw = parsed["secondary_influences"];
  const secondary = requireStringList(secondaryRaw, "secondary_influences", MAX_TITLE);
  for (const [index, identity] of secondary.entries()) {
    requireEnum(identity, `secondary_influences[${index}]`, allowedIdentities);
  }
  if (primaryIdentity !== null && secondary.includes(primaryIdentity)) {
    // The primary is excluded from the secondaries rather than duplicated
    // across both, matching `OnboardingDraft.styleProfile(userID:)`. A screen
    // rendering the same identity twice reads as a bug.
    throw providerContractError("secondary_influences must not repeat primary_identity.");
  }

  const rawPalette = parsed["palette"];
  if (!isRecord(rawPalette)) {
    throw providerContractError("palette must be a JSON object.");
  }

  const rawSilhouette = parsed["silhouette"];
  if (!isRecord(rawSilhouette)) {
    throw providerContractError("silhouette must be a JSON object.");
  }

  const rawSignatures = parsed["signature_opportunities"];
  if (!Array.isArray(rawSignatures)) {
    throw providerContractError("signature_opportunities must be an array.");
  }
  if (rawSignatures.length > MAX_LIST) {
    throw providerContractError(`signature_opportunities must contain at most ${MAX_LIST} items.`);
  }

  const rawPriorities = parsed["wardrobe_priorities"];
  if (!Array.isArray(rawPriorities)) {
    throw providerContractError("wardrobe_priorities must be an array.");
  }
  if (rawPriorities.length > MAX_LIST) {
    throw providerContractError(`wardrobe_priorities must contain at most ${MAX_LIST} items.`);
  }

  const priorities: RankedRecommendation[] = rawPriorities.map((entry, index) => {
    const named = parseNamedRecommendation(entry, `wardrobe_priorities[${index}]`);
    return {
      ...named,
      rank: requireBoundedInt(
        isRecord(entry) ? entry["rank"] : undefined,
        `wardrobe_priorities[${index}].rank`,
        1,
        MAX_LIST,
      ),
    };
  });

  return {
    primary_identity: primaryIdentity,
    identity_basis: requireString(parsed["identity_basis"], "identity_basis", MAX_REASON),
    secondary_influences: secondary,
    palette: {
      preferred_colors: requireStringList(
        rawPalette["preferred_colors"],
        "palette.preferred_colors",
        MAX_TITLE,
      ),
      avoided_colors: requireStringList(
        rawPalette["avoided_colors"],
        "palette.avoided_colors",
        MAX_TITLE,
      ),
      rationale: requireString(rawPalette["rationale"], "palette.rationale", MAX_REASON),
    },
    silhouette: {
      headline: requireString(rawSilhouette["headline"], "silhouette.headline", MAX_TITLE),
      detail: requireString(rawSilhouette["detail"], "silhouette.detail", MAX_SUMMARY),
    },
    signature_opportunities: rawSignatures.map((entry, index) =>
      parseNamedRecommendation(entry, `signature_opportunities[${index}]`)
    ),
    wardrobe_priorities: priorities,
    summary: requireString(parsed["summary"], "summary", MAX_SUMMARY),
    formality_preference: requireEnum(
      parsed["formality_preference"],
      "formality_preference",
      FORMALITY_LEVELS,
    ),
    logo_tolerance: requireBoundedInt(parsed["logo_tolerance"], "logo_tolerance", 0, 100),
    trend_tolerance: requireBoundedInt(parsed["trend_tolerance"], "trend_tolerance", 0, 100),
    accessory_preference: requireEnum(
      parsed["accessory_preference"],
      "accessory_preference",
      ACCESSORY_PREFERENCES,
    ),
    known_inputs: requireStringList(parsed["known_inputs"], "known_inputs", MAX_REASON),
    // The one list allowed to be empty: a profile with everything filled in
    // has nothing left to ask about, and manufacturing a question to avoid an
    // empty array would be padding.
    open_questions: Array.isArray(parsed["open_questions"])
      ? requireStringList(parsed["open_questions"], "open_questions", MAX_REASON)
      : (() => {
        throw providerContractError("open_questions must be an array.");
      })(),
    measured_dimensions: Array.isArray(parsed["measured_dimensions"])
      ? requireStringList(parsed["measured_dimensions"], "measured_dimensions", MAX_TITLE)
      : (() => {
        throw providerContractError("measured_dimensions must be an array.");
      })(),
  };
}

/**
 * The JSON Schema handed to the provider as `responseSchema`.
 *
 * A live adapter passes this to a vendor's structured-output mode so the
 * model is constrained rather than merely instructed; `parseStyleDnaDocument`
 * above then re-checks it server-side regardless, because "the vendor said it
 * was constrained" is not a guarantee this codebase is willing to build a
 * database write on.
 */
export function styleDnaResponseSchema(
  allowedIdentities: readonly string[],
): Record<string, unknown> {
  const named = {
    type: "object",
    required: ["title", "reason"],
    properties: { title: { type: "string" }, reason: { type: "string" } },
  };
  return {
    type: "object",
    required: [
      "primary_identity",
      "identity_basis",
      "secondary_influences",
      "palette",
      "silhouette",
      "signature_opportunities",
      "wardrobe_priorities",
      "summary",
      "formality_preference",
      "logo_tolerance",
      "trend_tolerance",
      "accessory_preference",
      "known_inputs",
      "open_questions",
      "measured_dimensions",
    ],
    properties: {
      primary_identity: { type: ["string", "null"], enum: [...allowedIdentities, null] },
      identity_basis: { type: "string" },
      secondary_influences: { type: "array", items: { type: "string", enum: allowedIdentities } },
      palette: {
        type: "object",
        required: ["preferred_colors", "avoided_colors", "rationale"],
        properties: {
          preferred_colors: { type: "array", items: { type: "string" } },
          avoided_colors: { type: "array", items: { type: "string" } },
          rationale: { type: "string" },
        },
      },
      silhouette: {
        type: "object",
        required: ["headline", "detail"],
        properties: { headline: { type: "string" }, detail: { type: "string" } },
      },
      signature_opportunities: { type: "array", items: named },
      wardrobe_priorities: {
        type: "array",
        items: {
          type: "object",
          required: ["rank", "title", "reason"],
          properties: {
            rank: { type: "integer", minimum: 1 },
            title: { type: "string" },
            reason: { type: "string" },
          },
        },
      },
      summary: { type: "string" },
      formality_preference: { type: "string", enum: FORMALITY_LEVELS },
      logo_tolerance: { type: "integer", minimum: 0, maximum: 100 },
      trend_tolerance: { type: "integer", minimum: 0, maximum: 100 },
      accessory_preference: { type: "string", enum: ACCESSORY_PREFERENCES },
      known_inputs: { type: "array", items: { type: "string" } },
      open_questions: { type: "array", items: { type: "string" } },
      measured_dimensions: { type: "array", items: { type: "string" } },
    },
  };
}
