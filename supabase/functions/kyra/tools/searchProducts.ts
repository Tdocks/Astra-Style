import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import type { ProductCandidateDTO } from "../../products/schema.ts";

export interface ProductSearchArgs {
  queryText: string;
  category: string | null;
  priceMax: number | null;
  formalityRange: readonly [number, number] | null;
  color: string | null;
  limit: number;
}
export interface ProductSearchMatch {
  product: ProductCandidateDTO;
  /** Organic relevance supplied by catalog search; sponsorship must not enter it. */
  relevance: number;
}
export interface SearchProductsDeps {
  search(args: ProductSearchArgs): Promise<readonly ProductSearchMatch[]>;
}
export const searchProductsDefinition: StylistToolDefinition = {
  name: "search_products",
  description:
    "Search the curated product catalog using style, category, color, formality and budget. Returns actual catalog products only. Affiliate status does not affect relevance ranking.",
  parametersSchema: {
    type: "object",
    properties: {
      query_text: { type: "string" },
      category: { type: "string", nullable: true },
      price_max: { type: "number", nullable: true },
      formality_range: {
        type: "array",
        items: { type: "integer" },
        minItems: 2,
        maxItems: 2,
        nullable: true,
      },
      color: { type: "string", nullable: true },
      limit: { type: "integer", default: 10, maximum: 25 },
    },
    required: ["query_text"],
  },
};

export function parseProductSearch(args: Record<string, unknown>): ProductSearchArgs | null {
  if (
    typeof args.query_text !== "string" || !args.query_text.trim() || args.query_text.length > 500
  ) return null;
  for (const key of ["category", "color"]) {
    const value = args[key];
    if (value != null && (typeof value !== "string" || !value.trim() || value.length > 80)) {
      return null;
    }
  }
  const price = args.price_max;
  if (price != null && (typeof price !== "number" || !Number.isFinite(price) || price < 0)) {
    return null;
  }
  const limit = args.limit ?? 10;
  if (typeof limit !== "number" || !Number.isInteger(limit) || limit < 1 || limit > 25) return null;
  const range = args.formality_range;
  if (
    range != null && (!Array.isArray(range) || range.length !== 2 ||
      !range.every((value) => Number.isInteger(value) && value >= 0 && value <= 100) ||
      range[0] > range[1])
  ) return null;
  return {
    queryText: args.query_text.trim(),
    category: typeof args.category === "string" ? args.category.trim() : null,
    color: typeof args.color === "string" ? args.color.trim() : null,
    priceMax: typeof price === "number" ? price : null,
    formalityRange: range == null ? null : [range[0], range[1]],
    limit,
  };
}

/** Unknown extracted fields cannot satisfy a strict filter. In particular the
 * mapper's fallback category must not masquerade as a verified category match.
 */
export function matchesProductFilters(
  product: ProductCandidateDTO,
  args: ProductSearchArgs,
): boolean {
  if (
    args.category && (product.fields_below_confidence_threshold.includes("category") ||
      product.category.toLowerCase() !== args.category.toLowerCase())
  ) return false;
  if (
    args.priceMax !== null && (product.price === undefined ||
      !Number.isFinite(product.price) || product.price > args.priceMax)
  ) return false;
  if (
    args.color && (typeof product.attributes.color !== "string" ||
      product.attributes.color.trim().toLowerCase() !== args.color.toLowerCase())
  ) return false;
  if (args.formalityRange) {
    const formality = product.attributes.formality_score;
    if (
      typeof formality !== "number" || !Number.isFinite(formality) ||
      formality < args.formalityRange[0] || formality > args.formalityRange[1]
    ) return false;
  }
  return true;
}

export async function executeSearchProducts(
  args: Record<string, unknown>,
  deps: SearchProductsDeps,
): Promise<Record<string, unknown>> {
  const parsed = parseProductSearch(args);
  if (!parsed) {
    return {
      error: "INVALID_ARGUMENTS",
      detail: "Provide a search phrase, valid filters and a limit from 1 to 25.",
    };
  }
  const matches = await deps.search(parsed);
  const seen = new Set<string>();
  const products = [...matches].filter((match) =>
    Number.isFinite(match.relevance) && matchesProductFilters(match.product, parsed)
  )
    .sort((a, b) => b.relevance - a.relevance)
    .filter(({ product }) => {
      if (seen.has(product.id)) return false;
      seen.add(product.id);
      return true;
    })
    .slice(0, parsed.limit).map(({ product }) => ({
      product_candidate_id: product.id,
      name: product.name,
      brand: product.brand ?? null,
      category: product.category,
      retailer: product.retailer,
      price: product.price ?? null,
      currency: product.currency ?? null,
      image_url: product.image_url ?? null,
      affiliate_url: product.affiliate_url ?? null,
      is_sponsored: product.sponsored,
      affiliate_disclosure: product.affiliate_url
        ? "Astra Style may earn a commission from this link. This does not affect the recommendation."
        : null,
    }));
  return products.length ? { available: true, products } : {
    error: "NO_RESULTS",
    products: [],
    detail: "No catalog products matched. Try broader filters.",
  };
}
