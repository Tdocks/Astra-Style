import type { SupabaseClient } from "@supabase/supabase-js";
import type { EdgeEnv } from "../_shared/supabaseClient.ts";
import { AppError, serverError } from "../_shared/errors.ts";
import {
  mapProductCandidateRowToDTO,
  type ProductCandidateRow,
} from "../products/candidateMapper.ts";
import type { ProductCandidateDTO, ProductEvaluationDTO } from "../products/schema.ts";
import type { AnalyzeProductDeps } from "./tools/analyzeProduct.ts";

/** Reuse the product service's extraction guards, evaluation and entitlement checks.
 * The destination is deployment configuration, never a model-supplied URL.
 * Every request forwards the caller JWT; no service role is used by Kyra.
 */
export function buildProductServices(
  env: EdgeEnv,
  authorization: string,
  supabase: SupabaseClient,
  fetcher: typeof fetch = fetch,
): AnalyzeProductDeps {
  async function call<T>(route: string, body: Record<string, unknown>): Promise<T> {
    const response = await fetcher(`${env.supabaseUrl}/functions/v1/products/${route}`, {
      method: "POST",
      headers: {
        Authorization: authorization,
        apikey: env.supabaseAnonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ body, request_id: crypto.randomUUID() }),
      signal: AbortSignal.timeout(20_000),
    });
    const payload = await response.json();
    if ([400, 401, 403, 404, 429].includes(response.status)) {
      const category = response.status === 401
        ? "auth"
        : response.status === 429
        ? "rate_limited"
        : "validation";
      const detail = response.status === 403 || response.status === 429
        ? "Product advice is limited for this account. Open the product page to review your allowance."
        : response.status === 404
        ? "That product could not be found."
        : response.status === 401
        ? "Please sign in again to use product advice."
        : "That product could not be analyzed. Try another product link.";
      throw new AppError(category, response.status, detail);
    }
    if (!response.ok || payload.data === null || payload.data === undefined) {
      // Infrastructure is handled by Kyra's retry/degrade policy. Never expose
      // upstream raw errors, JWTs or response bodies in a tool trace.
      throw serverError("Product advice is unavailable. Please try the product page again.");
    }
    return payload.data as T;
  }
  return {
    extract: (url) => call<ProductCandidateDTO>("extract", { url }),
    evaluate: (id) => call<ProductEvaluationDTO>("evaluate", { product_candidate_id: id }),
    async find(id) {
      const { data, error } = await supabase.from("product_candidates").select("*")
        .eq("id", id).maybeSingle();
      if (error) throw serverError("Couldn't load that product.");
      return data ? mapProductCandidateRowToDTO(data as ProductCandidateRow) : null;
    },
  };
}
