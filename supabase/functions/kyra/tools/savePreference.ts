// ============================================================================
// kyra/tools/savePreference.ts
// ============================================================================
// The `save_preference` tool (P5-KYRA-09, docs/06 §3.9 + §5). Mutating:
// writes `style_memories`. Every write is `is_user_visible = true` by
// construction (§5.4: no hidden memory tier), and every write is surfaced in
// the same turn's `memory_proposals` by the handler (§4.4's soft
// confirmation) — the handler builds that array from THIS tool's actual
// results, never from the model's unexecuted claims.
//
// `source_message_id` is required by §3.9's schema and is kept in the
// declared parameters so the model states its provenance — but the executor
// OVERRIDES it with the server-known id of the user message that triggered
// this turn. The model does not know real row ids; trusting whatever UUID it
// produced would attach memories to arbitrary rows (or fail the FK), and the
// honest provenance of a memory proposed this turn is this turn.
//
// CONFIDENCE THRESHOLD (§5.2). The tool call carries a single confidence
// number and no explicit-vs-inferred marker, so the server cannot apply two
// different bars to two cases it cannot distinguish. It enforces the
// EXPLICIT bar — ≥ 0.7 — as the single floor: §5.2's implicit path
// ("≥3 same-direction signals, avg ≥ 0.6") describes evidence accumulated
// across turns that only the model sees, and a model following its prompt
// reports such a corroborated pattern at ≥ 0.7 anyway. Below the floor the
// candidate is DISCARDED, not stored at reduced confidence — §5.2 is
// explicit that there is no "maybe" tier. This choice is recorded as a
// deviation in the function README.
//
// DEDUP / CONTRADICTION (§5.3), degraded honestly. §5.3 wants cosine
// similarity over embeddings and an NLI-style contradiction check; no
// embedding provider exists (nothing has ever written
// `style_memories.embedding`). The stand-in is token-set Jaccard similarity
// plus a polarity heuristic over fit/sentiment vocabulary — cruder
// thresholds, same three outcomes, and the thresholds live in named
// constants so the embedding upgrade is a drop-in. §5.3's SOFT supersession
// (`superseded_by`) is unimplementable: `style_memories` has no such column
// (P5-KYRA-01 shipped without one) and this ticket may not write
// migrations. A contradicted memory is therefore HARD-deleted — the mode
// the table's own header endorses ("privacy-sensitive tables
// (style_memories) are hard-delete") — and the change is surfaced in the
// same turn's memory_proposals with `supersedes_memory_id`, so it is never
// a silent overwrite even though the history row is gone.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import { MEMORY_TYPES, type MemoryType } from "../schema.ts";
import { containsSensitiveTraitInference } from "../guardrails.ts";

export interface ExistingMemoryRow {
  readonly id: string;
  readonly memory_type: string;
  readonly content: string;
  readonly confidence: number | string | null;
}

export interface SavePreferenceDeps {
  /** The id of the user message that triggered this turn — server-known. */
  readonly sourceMessageId: string;
  /** Configurable floor, default 0.7 (§5.2 explicit-statement bar). */
  readonly minimumConfidence: number;
  listMemoriesByType(memoryType: MemoryType): Promise<ExistingMemoryRow[]>;
  insertMemory(record: {
    readonly memoryType: MemoryType;
    readonly content: string;
    readonly confidence: number;
    readonly sourceMessageId: string;
  }): Promise<string>;
  updateMemoryConfidence(memoryId: string, confidence: number): Promise<void>;
  /** Hard delete — see the header on why supersession cannot be soft. */
  deleteMemory(memoryId: string): Promise<void>;
}

export const savePreferenceDefinition: StylistToolDefinition = {
  name: "save_preference",
  description:
    "Record a durable style memory from the conversation. Only for preferences that change " +
    "how future, unrelated requests should be handled — never one-off situational facts. " +
    "The memory is user-visible and deletable; write it as the user would want to read it.",
  parametersSchema: {
    type: "object",
    properties: {
      memory_type: { type: "string", enum: [...MEMORY_TYPES] },
      content: {
        type: "string",
        description: "Plain-language statement, written as the user would want to read it back.",
      },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      source_message_id: { type: "string", format: "uuid" },
    },
    required: ["memory_type", "content", "confidence", "source_message_id"],
  },
};

// Jaccard stand-ins for §5.3's cosine thresholds (0.92 / 0.75). Token-set
// Jaccard runs lower than embedding cosine for paraphrases, so the bands are
// set lower; both are named so the eventual embedding-backed version changes
// two constants, not the flow.
const SAME_STATEMENT_JACCARD = 0.6;
const RELATED_SUBJECT_JACCARD = 0.2;

const STOPWORDS = new Set([
  "a",
  "an",
  "the",
  "i",
  "me",
  "my",
  "you",
  "your",
  "is",
  "are",
  "was",
  "be",
  "been",
  "it",
  "its",
  "that",
  "this",
  "and",
  "or",
  "of",
  "to",
  "in",
  "on",
  "for",
  "with",
  "at",
  "he",
  "user",
  "prefers",
  "prefer",
  "really",
  "very",
]);

export function normalizedTokens(text: string): Set<string> {
  const tokens = new Set<string>();
  for (const word of text.toLowerCase().split(/[^a-z0-9]+/)) {
    if (word.length >= 2 && !STOPWORDS.has(word)) tokens.add(word);
  }
  return tokens;
}

export function jaccardSimilarity(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const token of a) {
    if (b.has(token)) intersection += 1;
  }
  return intersection / (a.size + b.size - intersection);
}

/**
 * Directional-contradiction heuristic: two statements about a shared subject
 * that pull opposite ways on the same axis. Axes covered are the ones style
 * memories actually move along — fit direction and like/dislike polarity —
 * plus bare negation of an otherwise-shared statement.
 */
const POLARITY_AXES: ReadonlyArray<readonly [ReadonlySet<string>, ReadonlySet<string>]> = [
  [
    new Set(["slim", "fitted", "tailored", "tight", "close"]),
    new Set(["relaxed", "oversized", "loose", "baggy", "roomy", "wide"]),
  ],
  [
    new Set(["like", "likes", "love", "loves", "want", "wants", "favorite", "favourite"]),
    new Set(["dislike", "dislikes", "hate", "hates", "avoid", "avoids", "never"]),
  ],
];

const NEGATIONS = new Set(["not", "no", "dont", "doesnt", "won't", "wont", "never"]);

export function isContradictory(oldContent: string, newContent: string): boolean {
  const oldTokens = normalizedTokens(oldContent);
  const newTokens = normalizedTokens(newContent);
  for (const [positive, negative] of POLARITY_AXES) {
    const oldPositive = [...oldTokens].some((token) => positive.has(token));
    const oldNegative = [...oldTokens].some((token) => negative.has(token));
    const newPositive = [...newTokens].some((token) => positive.has(token));
    const newNegative = [...newTokens].some((token) => negative.has(token));
    if (
      (oldPositive && newNegative && !newPositive) || (oldNegative && newPositive && !newNegative)
    ) {
      return true;
    }
  }
  // "likes X" vs "doesn't like X": same axis words, negation flips one side.
  const rawOld = oldContent.toLowerCase().split(/[^a-z0-9']+/);
  const rawNew = newContent.toLowerCase().split(/[^a-z0-9']+/);
  const oldNegated = rawOld.some((word) => NEGATIONS.has(word.replace("'", "")));
  const newNegated = rawNew.some((word) => NEGATIONS.has(word.replace("'", "")));
  return oldNegated !== newNegated &&
    jaccardSimilarity(normalizedTokens(oldContent), normalizedTokens(newContent)) >=
      SAME_STATEMENT_JACCARD;
}

export interface SavePreferenceArgs {
  readonly memoryType: MemoryType;
  readonly content: string;
  readonly confidence: number;
}

export function parseSavePreferenceArgs(raw: Record<string, unknown>): SavePreferenceArgs | null {
  const memoryType = raw["memory_type"];
  const content = raw["content"];
  const confidence = raw["confidence"];
  if (typeof memoryType !== "string" || !MEMORY_TYPES.includes(memoryType as MemoryType)) {
    return null;
  }
  if (typeof content !== "string" || content.trim().length === 0) return null;
  if (typeof confidence !== "number" || confidence < 0 || confidence > 1) return null;
  return {
    memoryType: memoryType as MemoryType,
    content: content.trim().slice(0, 500),
    confidence,
  };
}

function asConfidence(value: number | string | null): number {
  const parsed = typeof value === "string" ? Number(value) : value;
  return typeof parsed === "number" && Number.isFinite(parsed) ? parsed : 0;
}

export async function executeSavePreference(
  raw: Record<string, unknown>,
  deps: SavePreferenceDeps,
): Promise<Record<string, unknown>> {
  const args = parseSavePreferenceArgs(raw);
  if (args === null) {
    return {
      error: "INVALID_ARGUMENTS",
      detail: "memory_type must be a known type, content non-empty, confidence in 0-1.",
    };
  }

  // Guardrail at the WRITE, not just on the outgoing text: a sensitive-trait
  // inference must never be persisted, whatever the model does downstream.
  if (containsSensitiveTraitInference(args.content)) {
    return {
      error: "GUARDRAIL_SENSITIVE_TRAIT",
      detail: "Sensitive personal traits are never stored as memories. Nothing was saved.",
    };
  }

  if (args.confidence < deps.minimumConfidence) {
    // §3.9: a normal result, not an error state the model handles specially.
    return { memory_id: null, action_taken: "below_threshold_discarded" };
  }

  const existing = await deps.listMemoriesByType(args.memoryType);
  const newTokens = normalizedTokens(args.content);

  let bestMatch: ExistingMemoryRow | null = null;
  let bestSimilarity = 0;
  for (const row of existing) {
    const similarity = jaccardSimilarity(newTokens, normalizedTokens(row.content));
    if (similarity > bestSimilarity) {
      bestSimilarity = similarity;
      bestMatch = row;
    }
  }

  // §5.3.2: same memory restated — recency-biased confidence merge, no new row.
  if (
    bestMatch !== null && bestSimilarity >= SAME_STATEMENT_JACCARD &&
    !isContradictory(bestMatch.content, args.content)
  ) {
    const merged = Math.min(
      1,
      0.6 * args.confidence + 0.4 * asConfidence(bestMatch.confidence),
    );
    await deps.updateMemoryConfidence(bestMatch.id, Number(merged.toFixed(2)));
    return {
      memory_id: bestMatch.id,
      action_taken: "updated_existing",
      content: bestMatch.content,
      confidence: Number(merged.toFixed(2)),
    };
  }

  // §5.3.3: related subject, opposite direction — supersede (hard delete +
  // new row; see header), surfaced to the user via memory_proposals.
  if (
    bestMatch !== null && bestSimilarity >= RELATED_SUBJECT_JACCARD &&
    isContradictory(bestMatch.content, args.content)
  ) {
    await deps.deleteMemory(bestMatch.id);
    const newId = await deps.insertMemory({
      memoryType: args.memoryType,
      content: args.content,
      confidence: args.confidence,
      sourceMessageId: deps.sourceMessageId,
    });
    return {
      memory_id: newId,
      action_taken: "superseded_conflict",
      supersedes_memory_id: bestMatch.id,
      superseded_content: bestMatch.content,
      content: args.content,
      confidence: args.confidence,
    };
  }

  // §5.3.4: genuinely new.
  const memoryId = await deps.insertMemory({
    memoryType: args.memoryType,
    content: args.content,
    confidence: args.confidence,
    sourceMessageId: deps.sourceMessageId,
  });
  return {
    memory_id: memoryId,
    action_taken: "created",
    content: args.content,
    confidence: args.confidence,
  };
}
