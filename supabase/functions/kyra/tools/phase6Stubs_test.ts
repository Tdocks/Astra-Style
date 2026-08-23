import { assert, assertEquals } from "@std/assert";
import { executePhase6Stub, PHASE6_STUB_DEFINITIONS } from "./phase6Stubs.ts";

const STUB_NAMES = [
  "analyze_product",
  "search_products",
  "generate_studio_preview",
];

Deno.test("the three remaining Phase-6 tools are declared with pinned parameter schemas", () => {
  assertEquals(PHASE6_STUB_DEFINITIONS.map((definition) => definition.name), STUB_NAMES);
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
