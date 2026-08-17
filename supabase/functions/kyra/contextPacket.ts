// ============================================================================
// kyra/contextPacket.ts
// ============================================================================
// The context-packet builder (P5-KYRA-03), implementing docs/06 §1: a
// retrieved, budgeted subset rebuilt fresh per turn — never a full data dump.
// Pure function over already-fetched rows, so `contextPacket_test.ts` can
// exercise the budget and the truncation order with no network.
//
// TOKEN COUNTING. Budgets are enforced against `ceil(serializedJSON / 4)` —
// the classic chars-per-token heuristic — not a real tokenizer. §1.2 already
// anticipates this: budgets are "measured against the packet's serialized
// JSON, not the eventual model-specific tokenization", with a 15% safety
// margin built into each cap for tokenizer variance. Shipping a vendor
// tokenizer here would pin the packet to one vendor's vocabulary, which is
// exactly what the provider abstraction forbids.
//
// TRUNCATION IS AN EXPLICIT ORDERED LIST (§1.3), not ad-hoc trimming: each
// step names what it cuts, cuts it, re-measures, and stops the moment the
// packet fits. `requested_task`, `weather`, `body_fit_profile.fit_notes` and
// `budget_constraints` are never touched — they are small and load-bearing.
// If the closet floor (K=20) is reached and the packet still does not fit,
// the builder reports `overflowed: true` and the handler logs
// `context_packet_overflow`; the request proceeds with the floor packet
// rather than failing (§1.3's explicit instruction).
//
// WHERE THIS DELIBERATELY FALLS SHORT OF §1.5, AND WHY THAT IS HONEST.
// §1.5's retrieval strategy leads with pgvector embedding similarity between
// the request text and `closet_items.embedding`. No EmbeddingProvider is
// wired in this codebase (spec §25's `EMBEDDING_PROVIDER_API_KEY` is named
// but nothing implements the protocol), and `closet_items.embedding` is
// never written by any shipped endpoint — the column is uniformly NULL. A
// cosine ranking over NULLs would be theater. Until embeddings exist, the
// ranking uses the two signals that ARE real:
//   1. keyword relevance — request words matched against category /
//      subcategory / color / brand (crude, but it is a measurement of the
//      actual request, not a fabricated similarity), and
//   2. rotation — least-recently-worn first among equally-relevant items,
//      which doubles as §1.5's diversification (turn-over-turn fixation on
//      the same five items is what recency-penalty was for; nothing here
//      re-reads prior turns' packets, which are not persisted anywhere).
// The availability hard-filter and the category-balance backfill are
// implemented as specified. §1.4's "force-include an occasion referenced
// outside the 14-day window" requires date NLU over free text this build
// does not have; the window is applied as-is and the gap is recorded in
// this function's report rather than half-guessed.
// ============================================================================

// ---------------------------------------------------------------------------
// Source row shapes (as fetched by the store, RLS-scoped)
// ---------------------------------------------------------------------------

export interface StyleProfileSourceRow {
  readonly primary_identity: string | null;
  readonly secondary_identities: unknown;
  readonly preferred_colors: unknown;
  readonly avoided_colors: unknown;
  readonly preferred_fit: string | null;
  readonly formality_preference: string | null;
  readonly logo_tolerance: number | null;
  readonly trend_tolerance: number | null;
}

export interface BodyProfileSourceRow {
  readonly fit_notes: unknown;
  readonly shirt_size: string | null;
  readonly trouser_size: string | null;
  readonly shoe_size: string | null;
}

export interface LifestyleProfileSourceRow {
  readonly monthly_budget: number | string | null;
  readonly currency: string | null;
  readonly sustainability_preference: string | null;
}

export interface OccasionSourceRow {
  readonly id: string;
  readonly title: string;
  readonly starts_at: string;
  readonly dress_code: string | null;
  readonly location: string | null;
}

/** The compact-representation columns §1.5 names, plus laundry for filtering. */
export interface PacketClosetItemRow {
  readonly id: string;
  readonly category: string;
  readonly subcategory: string | null;
  readonly brand: string | null;
  readonly primary_color: string | null;
  readonly formality_score: number | null;
  readonly fit: string | null;
  readonly availability_state: string;
  readonly laundry_state: string;
  readonly wear_count: number;
  readonly last_worn_at: string | null;
}

export interface FeedbackSourceRow {
  readonly target_type: string;
  readonly target_id: string;
  readonly signal: string;
  readonly reason_tags: unknown;
  readonly created_at: string;
}

export interface MemorySourceRow {
  readonly id: string;
  readonly memory_type: string;
  readonly content: string;
  readonly confidence: number | string | null;
}

export interface ContextPacketInput {
  readonly now: Date;
  readonly requestText: string;
  readonly attachments: ReadonlyArray<{ readonly type: string; readonly value: string }>;
  readonly styleProfile: StyleProfileSourceRow | null;
  readonly bodyProfile: BodyProfileSourceRow | null;
  readonly lifestyleProfile: LifestyleProfileSourceRow | null;
  readonly weather: {
    readonly temperatureHigh: number;
    readonly temperatureLow: number;
    readonly condition: string;
  } | null;
  readonly occasions: readonly OccasionSourceRow[];
  readonly closetItems: readonly PacketClosetItemRow[];
  readonly recentFeedback: readonly FeedbackSourceRow[];
  readonly memories: readonly MemorySourceRow[];
}

export interface ContextPacketResult {
  readonly packet: Record<string, unknown>;
  /** Mirrors the packet's own `truncation_applied`, for logging. */
  readonly truncationApplied: readonly string[];
  /** §1.3's pathological case: still over budget at the closet floor. */
  readonly overflowed: boolean;
  /** Every closet item id present in the packet — the hallucination guard's ground truth. */
  readonly closetItemIds: ReadonlySet<string>;
}

// §1.2's total; per-section caps below are §1.2's table.
const TOTAL_BUDGET_TOKENS = 4_000;
const OCCASION_WINDOW_DAYS = 14;
const MAX_OCCASIONS = 5;
const MAX_FEEDBACK = 8;
const CLOSET_K_START = 60;
const CLOSET_K_STEP = 10;
const CLOSET_K_FLOOR = 20;
// §1.3 steps 1-3's reduced counts.
const MEMORIES_TRUNCATED = 5;
const FEEDBACK_TRUNCATED = 5;
const OCCASIONS_TRUNCATED = 3;
const ESSENTIAL_CATEGORIES = ["top", "bottom", "shoes"] as const;
const CATEGORY_FLOOR = 3;

/** chars/4 heuristic — see the header on why not a vendor tokenizer. */
export function estimateTokens(value: unknown): number {
  return Math.ceil(JSON.stringify(value).length / 4);
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

function asNumberOrNull(value: number | string | null | undefined): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

const WEARABLE_LAUNDRY_STATES = new Set(["clean", "worn_once"]);

/**
 * §1.5's availability hard-filter, including its inversion: a request that is
 * itself about laundry/availability planning should see exactly the items an
 * availability filter would hide.
 */
function isLaundryQuery(requestText: string): boolean {
  return /\b(laundry|clean right now|what'?s clean|available to wear|in the wash)\b/i
    .test(requestText);
}

function keywordRelevance(item: PacketClosetItemRow, requestWords: ReadonlySet<string>): number {
  let score = 0;
  const fields = [item.category, item.subcategory, item.brand, item.primary_color];
  for (const field of fields) {
    if (field === null) continue;
    for (const word of field.toLowerCase().split(/[^a-z0-9]+/)) {
      if (word.length >= 3 && requestWords.has(word)) score += 1;
    }
  }
  return score;
}

function lastWornMs(item: PacketClosetItemRow): number {
  if (item.last_worn_at === null) return 0;
  const ms = new Date(item.last_worn_at).getTime();
  return Number.isNaN(ms) ? 0 : ms;
}

/**
 * Ranks and trims the closet to `k` items: availability filter (or its
 * inversion), keyword relevance, rotation, then the §1.5 category-balance
 * backfill so no essential category is starved by relevance ranking alone.
 */
export function selectClosetItems(
  items: readonly PacketClosetItemRow[],
  requestText: string,
  k: number,
): PacketClosetItemRow[] {
  const laundryQuery = isLaundryQuery(requestText);
  const eligible = items.filter((item) => {
    const wearable = item.availability_state === "available" &&
      WEARABLE_LAUNDRY_STATES.has(item.laundry_state);
    return laundryQuery ? !wearable : wearable;
  });

  const requestWords = new Set(
    requestText.toLowerCase().split(/[^a-z0-9]+/).filter((word) => word.length >= 3),
  );

  const ranked = [...eligible].sort((a, b) => {
    const relevance = keywordRelevance(b, requestWords) - keywordRelevance(a, requestWords);
    if (relevance !== 0) return relevance;
    // Rotation: least-recently-worn first; never-worn (0) sorts first.
    return lastWornMs(a) - lastWornMs(b);
  });

  const selected = ranked.slice(0, k);
  const selectedIds = new Set(selected.map((item) => item.id));

  // Category-balance backfill: guarantee CATEGORY_FLOOR per essential
  // category when the (filtered) closet contains that many, displacing the
  // lowest-ranked non-essential surplus rather than growing past k.
  for (const category of ESSENTIAL_CATEGORIES) {
    const have = selected.filter((item) => item.category === category).length;
    if (have >= CATEGORY_FLOOR) continue;
    const candidates = ranked.filter(
      (item) => item.category === category && !selectedIds.has(item.id),
    );
    let needed = Math.min(CATEGORY_FLOOR - have, candidates.length);
    for (const candidate of candidates) {
      if (needed === 0) break;
      // Displace from the end: the lowest-ranked item not in an essential
      // category below its own floor.
      let displaced = false;
      for (let i = selected.length - 1; i >= 0; i--) {
        const tail = selected[i]!;
        const tailCategory = tail.category;
        const tailIsEssential = (ESSENTIAL_CATEGORIES as readonly string[]).includes(tailCategory);
        const tailCount = selected.filter((item) => item.category === tailCategory).length;
        if (!tailIsEssential || tailCount > CATEGORY_FLOOR) {
          selected.splice(i, 1);
          selectedIds.delete(tail.id);
          displaced = true;
          break;
        }
      }
      if (!displaced && selected.length >= k) break;
      selected.push(candidate);
      selectedIds.add(candidate.id);
      needed -= 1;
    }
  }

  return selected;
}

function compactClosetItem(item: PacketClosetItemRow): Record<string, unknown> {
  return {
    id: item.id,
    category: item.category,
    subcategory: item.subcategory,
    primary_color: item.primary_color,
    formality_score: item.formality_score,
    fit: item.fit,
    availability_state: item.availability_state,
    wear_count: item.wear_count,
    last_worn_at: item.last_worn_at === null ? null : item.last_worn_at.slice(0, 10),
  };
}

function daysAgo(iso: string, now: Date): number {
  const ms = new Date(iso).getTime();
  if (Number.isNaN(ms)) return 0;
  return Math.max(0, Math.floor((now.getTime() - ms) / 86_400_000));
}

// ---------------------------------------------------------------------------
// Assembly + §1.3 truncation
// ---------------------------------------------------------------------------

interface MutableSections {
  memories: MemorySourceRow[];
  feedback: FeedbackSourceRow[];
  occasions: OccasionSourceRow[];
  closetK: number;
  styleProfileFull: boolean;
}

export function buildContextPacket(input: ContextPacketInput): ContextPacketResult {
  const { now } = input;

  // §1.4: occasions within [now, now + 14 days], soonest first, capped at 5.
  // (The "force-include a referenced far-future occasion" clause needs date
  // NLU this build does not have — see the header.)
  const windowEndMs = now.getTime() + OCCASION_WINDOW_DAYS * 86_400_000;
  const upcomingOccasions = input.occasions
    .filter((occasion) => {
      const startsMs = new Date(occasion.starts_at).getTime();
      return !Number.isNaN(startsMs) && startsMs >= now.getTime() && startsMs <= windowEndMs;
    })
    .sort((a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime())
    .slice(0, MAX_OCCASIONS);

  // Memories arrive pre-filtered (is_user_visible, confidence threshold) by
  // the store; ordering here is confidence-descending as the relevance proxy
  // until memory embeddings exist (§4.3's relevance score needs them).
  const rankedMemories = [...input.memories].sort(
    (a, b) => (asNumberOrNull(b.confidence) ?? 0) - (asNumberOrNull(a.confidence) ?? 0),
  );

  const recentFeedback = [...input.recentFeedback]
    .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
    .slice(0, MAX_FEEDBACK);

  const sections: MutableSections = {
    memories: rankedMemories,
    feedback: recentFeedback,
    occasions: upcomingOccasions,
    closetK: CLOSET_K_START,
    styleProfileFull: true,
  };
  const truncationApplied: string[] = [];

  const assemble = (): Record<string, unknown> => {
    const style = input.styleProfile;
    const styleProfile = style === null ? null : {
      primary_identity: style.primary_identity,
      ...(sections.styleProfileFull
        ? {
          secondary_identities: asStringArray(style.secondary_identities),
          logo_tolerance: style.logo_tolerance,
          trend_tolerance: style.trend_tolerance,
        }
        : {}),
      preferred_colors: asStringArray(style.preferred_colors),
      avoided_colors: asStringArray(style.avoided_colors),
      preferred_fit: style.preferred_fit,
      // The schema stores a formality ENUM, not §1.6's illustrative number;
      // the stored word is passed through rather than invented into a scale.
      formality_preference: style.formality_preference,
    };

    const body = input.bodyProfile;
    const weather = input.weather;

    return {
      packet_version: "1.0",
      requested_task: {
        raw_text: input.requestText,
        // No intent classifier runs before the model call; a guessed hint
        // would be noise presented as signal. The model classifies intent
        // itself in the response schema.
        intent_hint: null,
        attachments: input.attachments.map((attachment) => ({
          type: attachment.type,
          ref: attachment.value,
        })),
      },
      style_profile: styleProfile,
      body_fit_profile: body === null ? null : {
        fit_notes: asStringArray(body.fit_notes),
        shirt_size: body.shirt_size,
        trouser_size: body.trouser_size,
        shoe_size: body.shoe_size,
      },
      weather: weather === null ? { available: false } : {
        available: true,
        high_c: weather.temperatureHigh,
        low_c: weather.temperatureLow,
        condition: weather.condition,
      },
      occasions: sections.occasions.map((occasion) => ({
        id: occasion.id,
        title: occasion.title,
        starts_at: occasion.starts_at,
        dress_code: occasion.dress_code,
        location: occasion.location,
      })),
      closet_items: selectClosetItems(input.closetItems, input.requestText, sections.closetK)
        .map(compactClosetItem),
      recent_feedback: sections.feedback.map((feedback) => ({
        target_type: feedback.target_type,
        target_id: feedback.target_id,
        signal: feedback.signal,
        reason_tags: asStringArray(feedback.reason_tags),
        days_ago: daysAgo(feedback.created_at, now),
      })),
      budget_constraints: input.lifestyleProfile === null ? null : {
        monthly_budget: asNumberOrNull(input.lifestyleProfile.monthly_budget),
        currency: input.lifestyleProfile.currency,
        sustainability_preference: input.lifestyleProfile.sustainability_preference,
      },
      durable_memories: sections.memories.map((memory) => ({
        id: memory.id,
        memory_type: memory.memory_type,
        content: memory.content,
        confidence: asNumberOrNull(memory.confidence),
      })),
      truncation_applied: [...truncationApplied],
    };
  };

  // §1.3's ordered truncation: least essential first, stop as soon as it
  // fits. Each closure returns true when it changed something.
  const steps: Array<{ label: string; apply: () => boolean }> = [
    {
      label: `durable_memories_truncated_to_${MEMORIES_TRUNCATED}`,
      apply: () => {
        if (sections.memories.length <= MEMORIES_TRUNCATED) return false;
        sections.memories = sections.memories.slice(0, MEMORIES_TRUNCATED);
        return true;
      },
    },
    {
      label: `recent_feedback_truncated_to_${FEEDBACK_TRUNCATED}`,
      apply: () => {
        if (sections.feedback.length <= FEEDBACK_TRUNCATED) return false;
        sections.feedback = sections.feedback.slice(0, FEEDBACK_TRUNCATED);
        return true;
      },
    },
    {
      label: `occasions_truncated_to_${OCCASIONS_TRUNCATED}`,
      apply: () => {
        if (sections.occasions.length <= OCCASIONS_TRUNCATED) return false;
        sections.occasions = sections.occasions.slice(0, OCCASIONS_TRUNCATED);
        return true;
      },
    },
  ];

  let packet = assemble();
  let overflowed = false;

  if (estimateTokens(packet) > TOTAL_BUDGET_TOKENS) {
    for (const step of steps) {
      if (step.apply()) {
        truncationApplied.push(step.label);
        packet = assemble();
        if (estimateTokens(packet) <= TOTAL_BUDGET_TOKENS) break;
      }
    }
    // Step 4: closet K in steps of 10 down to the floor.
    while (
      estimateTokens(packet) > TOTAL_BUDGET_TOKENS && sections.closetK > CLOSET_K_FLOOR
    ) {
      sections.closetK = Math.max(CLOSET_K_FLOOR, sections.closetK - CLOSET_K_STEP);
      truncationApplied.push(`closet_items_reduced_to_k${sections.closetK}`);
      packet = assemble();
    }
    // Step 5: shed style_profile secondary fields.
    if (estimateTokens(packet) > TOTAL_BUDGET_TOKENS && sections.styleProfileFull) {
      sections.styleProfileFull = false;
      truncationApplied.push("style_profile_reduced_to_primary");
      packet = assemble();
    }
    if (estimateTokens(packet) > TOTAL_BUDGET_TOKENS) {
      // §1.3: proceed with the floor packet, report rather than fail.
      overflowed = true;
    }
  }

  const closetItemIds = new Set<string>();
  for (const entry of packet["closet_items"] as Array<Record<string, unknown>>) {
    closetItemIds.add(entry["id"] as string);
  }

  return {
    packet,
    truncationApplied: [...truncationApplied],
    overflowed,
    closetItemIds,
  };
}
