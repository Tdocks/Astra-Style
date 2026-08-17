// ============================================================================
// kyra/tools/phase6Stubs.ts
// ============================================================================
// Stub interfaces for the four Phase-6+ tools (P5-KYRA-11): analyze_product,
// search_products, generate_studio_preview, create_packing_list. They exist
// so the tool-calling surface is complete NOW — the model can be told about
// all eleven tools and gracefully decline the four it cannot yet deliver —
// and so the parameter schemas the real implementations will use are pinned
// today (P5-KYRA-11's second acceptance criterion: no breaking change when
// Waves 5-6 replace the executors).
//
// A STUB MUST ANNOUNCE ITSELF IN ITS RETURN VALUE, not just in a comment.
// Every executor below returns `available: false` + `error: "NOT_BUILT"` +
// a plain-language `detail` the model can relay in Kyra's voice. None of
// them returns a fabricated verdict, product list, generation id, or packing
// list — a made-up "skip" verdict from a stub would be indistinguishable
// from a real one downstream, which is exactly the failure this codebase
// refuses. The parameter schemas are copied verbatim from docs/06 §3.4,
// §3.5, §3.8 and §3.11.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";

function stubResult(toolName: string, detail: string): Record<string, unknown> {
  return {
    available: false,
    error: "NOT_BUILT",
    tool: toolName,
    detail,
  };
}

export const analyzeProductDefinition: StylistToolDefinition = {
  name: "analyze_product",
  description:
    "Analyze a product URL or product candidate against the user's closet (compatibility, " +
    "redundancy, cost-per-wear, verdict). NOT YET AVAILABLE — returns a not-built result; " +
    "tell the user plainly this arrives with product advice in a later release.",
  parametersSchema: {
    type: "object",
    properties: {
      product_url: { type: "string", format: "uri", nullable: true },
      product_candidate_id: { type: "string", format: "uuid", nullable: true },
    },
  },
};

export const searchProductsDefinition: StylistToolDefinition = {
  name: "search_products",
  description:
    "Search the curated/affiliate product catalog. NOT YET AVAILABLE — returns a not-built " +
    "result; do not invent products or retailers in its place.",
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

export const generateStudioPreviewDefinition: StylistToolDefinition = {
  name: "generate_studio_preview",
  description: "Queue a Style Studio preview of an outfit on the user's reference image. NOT YET " +
    "AVAILABLE — returns a not-built result; never claim a preview is being generated.",
  parametersSchema: {
    type: "object",
    properties: {
      outfit_id: { type: "string", format: "uuid", nullable: true },
      item_ids: { type: "array", items: { type: "string", format: "uuid" }, nullable: true },
      reference_image_id: { type: "string", format: "uuid" },
      pose: {
        type: "string",
        enum: ["standing", "walking", "three-quarter"],
        default: "standing",
      },
      background: { type: "string", default: "studio-neutral" },
      resolution: { type: "string", enum: ["draft", "hi_res"], default: "draft" },
    },
    required: ["reference_image_id"],
  },
};

export const createPackingListDefinition: StylistToolDefinition = {
  name: "create_packing_list",
  description: "Generate and persist a packing list and daily outfit plan for a trip. NOT YET " +
    "AVAILABLE — returns a not-built result; do not improvise a persisted packing list.",
  parametersSchema: {
    type: "object",
    properties: {
      destination: { type: "string" },
      start_date: { type: "string", format: "date" },
      end_date: { type: "string", format: "date" },
      activities: { type: "array", items: { type: "string" } },
      dress_codes: { type: "array", items: { type: "string" } },
      laundry_access: { type: "boolean", default: false },
      luggage_constraint: {
        type: "string",
        enum: ["carry_on", "checked", "none"],
        default: "none",
      },
    },
    required: ["destination", "start_date", "end_date"],
  },
};

/** Executor for all four stubs; dispatched by tool name from the registry. */
export function executePhase6Stub(toolName: string): Record<string, unknown> {
  switch (toolName) {
    case "analyze_product":
      return stubResult(
        toolName,
        "Product analysis isn't built yet — it arrives with product advice in a later " +
          "release. Say so plainly; do not offer a verdict, score, or price judgment as if " +
          "this tool had produced one. General styling judgment (no computed numbers) is fine.",
      );
    case "search_products":
      return stubResult(
        toolName,
        "The product catalog isn't connected yet. Say so plainly; do not name specific " +
          "products, prices, or retailers as if they came from a search.",
      );
    case "generate_studio_preview":
      return stubResult(
        toolName,
        "Style Studio previews aren't available yet. Say so plainly; never imply an image " +
          "is being generated.",
      );
    case "create_packing_list":
      return stubResult(
        toolName,
        "The packing assistant isn't built yet. You may still reason about what to pack " +
          "conversationally from the closet you can see — but no persisted packing list " +
          "exists, so do not claim one was created.",
      );
    default:
      // A registry bug, not a model error: only the four names above route here.
      return stubResult(toolName, "Unknown stubbed tool.");
  }
}

export const PHASE6_STUB_DEFINITIONS: readonly StylistToolDefinition[] = [
  analyzeProductDefinition,
  searchProductsDefinition,
  generateStudioPreviewDefinition,
  createPackingListDefinition,
];
