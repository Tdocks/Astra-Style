import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import { AppError } from "../../_shared/errors.ts";
import { isUUID } from "../../_shared/validation.ts";
import { assertSafeExternalUrl } from "../../products/urlValidation.ts";
import type { ProductCandidateDTO, ProductEvaluationDTO } from "../../products/schema.ts";

export const analyzeProductDefinition: StylistToolDefinition = {
  name: "analyze_product",
  description:
    "Analyze one product URL or catalog candidate against the user's closet. Returns measured compatibility, redundancy, outfits unlocked and a purchase verdict. Do not invent missing product attributes.",
  parametersSchema: {
    type: "object",
    properties: {
      product_url: { type: "string", format: "uri", nullable: true },
      product_candidate_id: { type: "string", format: "uuid", nullable: true },
    },
  },
};

export interface AnalyzeProductDeps {
  extract(url: string): Promise<ProductCandidateDTO>;
  find(id: string): Promise<ProductCandidateDTO | null>;
  evaluate(id: string): Promise<ProductEvaluationDTO>;
}

export async function executeAnalyzeProduct(
  args: Record<string, unknown>,
  deps: AnalyzeProductDeps,
): Promise<Record<string, unknown>> {
  const url = args.product_url;
  const id = args.product_candidate_id;
  const hasURL = url !== null && url !== undefined;
  const hasID = id !== null && id !== undefined;
  if (hasURL === hasID) {
    return {
      error: "INVALID_ARGUMENTS",
      detail: "Provide exactly one product URL or candidate ID.",
    };
  }
  if (hasID && !isUUID(id)) {
    return { error: "INVALID_ARGUMENTS", detail: "The product candidate ID must be a UUID." };
  }
  if (hasURL) {
    if (typeof url !== "string" || url.length > 2048) {
      return { error: "INVALID_ARGUMENTS", detail: "Provide a valid public retailer URL." };
    }
    try {
      assertSafeExternalUrl(url);
    } catch {
      return { error: "INVALID_ARGUMENTS", detail: "Provide a safe public retailer URL." };
    }
  }
  try {
    const product = hasURL ? await deps.extract(url as string) : await deps.find(id as string);
    if (!product) {
      return { error: "PRODUCT_NOT_FOUND", detail: "That product is not in the catalog." };
    }
    const evaluation = await deps.evaluate(product.id);
    const scores = {
      compatibility_score: evaluation.compatibility_score,
      redundancy_risk: evaluation.redundancy_score / 100,
      outfits_unlocked: evaluation.outfits_unlocked,
      expected_cost_per_wear: evaluation.expected_cost_per_wear,
      verdict: evaluation.verdict,
    };
    return {
      available: true,
      product: {
        product_candidate_id: product.id,
        brand: product.brand ?? null,
        name: product.name,
        category: product.category,
        price: product.price ?? null,
        currency: product.currency ?? null,
        retailer: product.retailer,
        image_url: product.image_url ?? null,
        affiliate_url: product.affiliate_url ?? null,
        is_sponsored: evaluation.sponsored,
        affiliate_disclosure: product.affiliate_url
          ? "Astra Style may earn a commission from this link. This does not affect the recommendation."
          : null,
        ...scores,
      },
      ...scores,
      reasoning: evaluation.reasoning,
      unmeasured: evaluation.unmeasured,
      // A separate gap measurement is needed before claiming fills_gap.
      fills_gap: null,
    };
  } catch (error) {
    if (error instanceof AppError && error.status < 500) {
      return {
        error: error.status === 403 || error.status === 429
          ? "ALLOWANCE_LIMIT"
          : error.status === 401
          ? "AUTH_REQUIRED"
          : "PRODUCT_UNAVAILABLE",
        detail: error.message,
      };
    }
    throw error;
  }
}
