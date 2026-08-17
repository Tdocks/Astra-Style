import { assert, assertEquals } from "@std/assert";
import { executePhase6Stub, PHASE6_STUB_DEFINITIONS } from "./phase6Stubs.ts";

const STUB_NAMES = [
  "analyze_product",
  "search_products",
  "generate_studio_preview",
  "create_packing_list",
];

Deno.test("all four Phase-6 tools are declared with pinned parameter schemas", () => {
  assertEquals(PHASE6_STUB_DEFINITIONS.map((definition) => definition.name), STUB_NAMES);
  // Spot-check the pinned schemas match docs/06 §3's required fields, so the
  // real implementations land without a breaking change (P5-KYRA-11).
  const packing = PHASE6_STUB_DEFINITIONS.find((d) => d.name === "create_packing_list")!;
  assertEquals(
    (packing.parametersSchema as { required: string[] }).required,
    ["destination", "start_date", "end_date"],
  );
  const products = PHASE6_STUB_DEFINITIONS.find((d) => d.name === "search_products")!;
  assertEquals((products.parametersSchema as { required: string[] }).required, ["query_text"]);
});

Deno.test("every stub announces itself as not built — never a fabricated result", () => {
  for (const name of STUB_NAMES) {
    const result = executePhase6Stub(name);
    assertEquals(result["available"], false);
    assertEquals(result["error"], "NOT_BUILT");
    assertEquals(result["tool"], name);
    assert(typeof result["detail"] === "string" && (result["detail"] as string).length > 0);
    // The specific fabrications each real tool would produce must be absent.
    assertEquals(result["verdict"], undefined);
    assertEquals(result["products"], undefined);
    assertEquals(result["generation_id"], undefined);
    assertEquals(result["packing_list_id"], undefined);
  }
});

Deno.test("stub descriptions tell the model the tool is unavailable up front", () => {
  for (const definition of PHASE6_STUB_DEFINITIONS) {
    assert(definition.description.includes("NOT YET AVAILABLE"));
  }
});
