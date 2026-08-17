// ============================================================================
// products/handler.ts
// ============================================================================
// P6-SHOP-03 and P6-SHOP-04's request logic, with every I/O edge behind the
// `ProductsDependencies` seam so `handler_test.ts` exercises the real
// decisions against fixtures rather than a live Supabase project and a live
// retailer. Same shape as `outfits/handler.ts` and for the same reason.
//
// THE SPONSORSHIP GUARANTEE, RESTATED WHERE IT IS ACTUALLY AT RISK.
// `evaluation.ts` cannot see `sponsored` — its types make that impossible.
// This file CAN see it, because the wire response has to carry the label.
// So the rule here is positional and worth stating plainly: `sponsored` is
// read only AFTER `evaluateProductCandidate` has returned, and only to
// attach `sponsored:` to the DTO. It is never passed into evaluation, never
// consulted when choosing which alternatives to fetch, and never used to
// order them — `rankProductCandidates` sorts on `organicScore` alone.
//
// Spec §11's wording is "affiliate availability must not change Kyra's
// verdict". The failure it describes is not usually somebody deciding to
// cheat; it is a `sponsored` flag drifting into a sort comparator during a
// refactor, six months later, in a file nobody re-reads. The type boundary
// in `evaluation.ts` and this paragraph are the two things standing between
// this code and that.
//
// WHY EXTRACTION UPSERTS RATHER THAN INSERTS. `canonical_url` is the de-dup
// key (`20260728100600_commerce.sql`), and two men pasting the same jacket
// must reach one row — otherwise every evaluation is against a private copy
// and the shared-read RLS that makes `product_candidates` a catalog buys
// nothing.
// ============================================================================

import { badRequest, notFound, serverError } from "../_shared/errors.ts";
import type { ProductExtractionProvider } from "../_shared/providers/productExtraction.ts";
import type { ProductCandidateUpsertRow } from "./candidateMapper.ts";
import {
  mapExtractionToUpsertRow,
  mapProductCandidateRowToDTO,
  mapProductCandidateRowToEvaluationInput,
  type ProductCandidateRow,
} from "./candidateMapper.ts";
import { evaluateProductCandidate, type LifestyleInputs } from "./evaluation.ts";
import { rankProductCandidates } from "./ranking.ts";
import type { AlternativeProductDTO, ProductCandidateDTO, ProductEvaluationDTO } from "./schema.ts";
import { parseEvaluateProductBody, parseExtractProductBody } from "./schema.ts";
import { assertSafeExternalUrl } from "./urlValidation.ts";
import type { ScorableItem } from "../_shared/scoring/types.ts";
import type { RedundancyItem } from "../_shared/scoring/redundancy.ts";

/**
 * How long a retailer page gets before extraction gives up.
 *
 * A man has pasted a link and is watching a spinner, so this is a UX budget
 * rather than a network one — `docs/08` §N.4 asks each provider to state its
 * own. Ten seconds is long enough for a slow retailer and short enough that
 * the failure arrives while he is still looking at the screen.
 */
const EXTRACTION_TIMEOUT_MS = 10_000;

/** One owned garment, in both the shapes the two engines want it in. */
export interface OwnedGarment {
  readonly scorable: ScorableItem;
  readonly redundancy: RedundancyItem;
}

export interface ProductsDependencies {
  readonly extractionProvider: ProductExtractionProvider;
  /** Upserts on `canonical_url` and returns the resulting row. */
  readonly upsertCandidate: (row: ProductCandidateUpsertRow) => Promise<ProductCandidateRow>;
  readonly fetchCandidate: (id: string) => Promise<ProductCandidateRow | null>;
  /** The caller's wearable closet, already mapped. */
  readonly fetchCloset: (userID: string) => Promise<readonly OwnedGarment[]>;
  readonly fetchLifestyle: (userID: string) => Promise<LifestyleInputs>;
  /** Other catalog rows in the same category, for §5.5's alternatives. */
  readonly fetchAlternatives: (
    category: string | null,
    excludingID: string,
  ) => Promise<readonly ProductCandidateRow[]>;
  readonly persistEvaluation: (row: {
    readonly user_id: string;
    readonly product_candidate_id: string;
    readonly compatibility_score: number;
    readonly redundancy_score: number;
    readonly outfits_unlocked: number;
    readonly expected_cost_per_wear: number | null;
    readonly verdict: string;
    readonly reasoning: string;
  }) => Promise<{ readonly created_at: string }>;
  readonly requestID: string;
}

export async function handleExtractProduct(
  rawBody: unknown,
  userID: string,
  deps: ProductsDependencies,
): Promise<ProductCandidateDTO> {
  const body = parseExtractProductBody(rawBody);
  // SSRF guard before the fetch, not after: the URL arrives from a text field
  // and the provider is about to make a server-side request with it.
  assertSafeExternalUrl(body.url);
  const url = body.url;

  const result = await deps.extractionProvider.extractProduct(
    { url },
    { requestId: deps.requestID, userId: userID, timeoutMs: EXTRACTION_TIMEOUT_MS },
  );

  const mapped = mapExtractionToUpsertRow(result);
  if (mapped === null) {
    // Not a server error and not the user's fault: the page was reachable and
    // simply is not a product page, or is one this provider cannot read. Say
    // that, rather than persisting a row named after a URL.
    throw badRequest(
      "That link didn't look like a product page — nothing on it named a garment.",
    );
  }

  const row = await deps.upsertCandidate(mapped.upsertRow);
  return mapProductCandidateRowToDTO(row);
}

export async function handleEvaluateProduct(
  rawBody: unknown,
  userID: string,
  deps: ProductsDependencies,
): Promise<ProductEvaluationDTO> {
  const body = parseEvaluateProductBody(rawBody);

  const row = await deps.fetchCandidate(body.productCandidateId);
  if (row === null) {
    throw notFound("That product isn't one we have on file.");
  }

  const mapped = mapProductCandidateRowToEvaluationInput(row);
  if (mapped.item === null || mapped.redundancyItem === null) {
    // Fragrance has no wardrobe-graph role at all, so there is no pairing
    // question to answer. A fabricated verdict here would be a confident
    // answer to a question the engine cannot be asked.
    throw badRequest(
      "Kyra can't judge this kind of product against a wardrobe yet.",
    );
  }

  const [closet, lifestyle] = await Promise.all([
    deps.fetchCloset(userID),
    deps.fetchLifestyle(userID),
  ]);

  const evaluation = evaluateProductCandidate({
    candidate: mapped.item,
    closet: closet.map((g) => g.scorable),
    candidatePrice: row.price,
    redundancyCandidate: mapped.redundancyItem,
    redundancyCloset: closet.map((g) => g.redundancy),
    lifestyle,
  });

  const persisted = await deps.persistEvaluation({
    user_id: userID,
    product_candidate_id: row.id,
    compatibility_score: evaluation.compatibilityScore,
    redundancy_score: evaluation.redundancyScore,
    outfits_unlocked: evaluation.outfitsUnlocked,
    expected_cost_per_wear: evaluation.expectedCostPerWear,
    verdict: evaluation.verdict,
    reasoning: evaluation.reasoning,
  });

  return {
    user_id: userID,
    product_candidate_id: row.id,
    compatibility_score: evaluation.compatibilityScore,
    redundancy_score: evaluation.redundancyScore,
    outfits_unlocked: evaluation.outfitsUnlocked,
    expected_cost_per_wear: evaluation.expectedCostPerWear,
    verdict: evaluation.verdict,
    reasoning: evaluation.reasoning,
    created_at: persisted.created_at,
    color_fit: evaluation.colorFit,
    lifestyle_fit: evaluation.lifestyleFit,
    budget_fit: evaluation.budgetFit,
    // Read here, after the verdict exists, and used only as a label.
    sponsored: row.sponsored,
    unmeasured: [...new Set(evaluation.degraded)],
    alternatives: await buildAlternatives(row, closet, deps),
  };
}

/**
 * §5.5 step 3's alternatives, ranked organically.
 *
 * Each alternative is scored by the same `evaluateProductCandidate` the
 * primary went through — a "compatibility" number produced by a cheaper
 * second formula would be a different quantity wearing the same label, and
 * the two would be shown side by side.
 *
 * A failure here costs the alternatives, never the verdict: the man asked
 * whether to buy the thing he pasted, and answering that does not depend on
 * the catalog having anything else in it.
 */
async function buildAlternatives(
  primary: ProductCandidateRow,
  closet: readonly OwnedGarment[],
  deps: ProductsDependencies,
): Promise<readonly AlternativeProductDTO[]> {
  let rows: readonly ProductCandidateRow[];
  try {
    rows = await deps.fetchAlternatives(primary.category, primary.id);
  } catch {
    return [];
  }
  if (rows.length === 0) return [];

  const scored = rows.flatMap((candidate) => {
    const mapped = mapProductCandidateRowToEvaluationInput(candidate);
    if (mapped.item === null || mapped.redundancyItem === null) return [];
    const evaluation = evaluateProductCandidate({
      candidate: mapped.item,
      closet: closet.map((g) => g.scorable),
      candidatePrice: candidate.price,
      redundancyCandidate: mapped.redundancyItem,
      redundancyCloset: closet.map((g) => g.redundancy),
      lifestyle: { monthlyBudget: null, dressCode: null },
    });
    return [{
      row: candidate,
      organicScore: evaluation.compatibilityScore,
      sponsored: candidate.sponsored,
    }];
  });

  const ranked = rankProductCandidates(
    scored.map((s) => ({
      id: s.row.id,
      organicScore: s.organicScore,
      sponsored: s.sponsored,
    })),
  );

  return ranked.flatMap((r) => {
    const source = scored.find((s) => s.row.id === r.id);
    if (source === undefined) return [];
    return [{
      product_candidate_id: source.row.id,
      ...(source.row.price !== null ? { price: source.row.price } : {}),
      currency: source.row.currency,
      name: source.row.name,
      compatibility_score: source.organicScore,
      sponsored: source.sponsored,
    }];
  });
}

/** Re-exported so `index.ts` reports a consistent envelope for both routes. */
export { serverError };
