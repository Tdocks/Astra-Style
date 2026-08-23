import { assertEquals } from "@std/assert";
import { roleFor } from "./types.ts";
import {
  parseWardrobeGraph,
  requiredRoleSetsForAnchor,
  requiredRoleSetsForGeneration,
  roleSetAcceptsLocks,
} from "./wardrobeGraph.ts";

Deno.test("roleFor: dress is its own role; skirt is a bottom", () => {
  assertEquals(roleFor("dress"), "dress");
  assertEquals(roleFor("skirt"), "bottom");
  assertEquals(roleFor("top"), "top");
  assertEquals(roleFor("fragrance"), null);
});

Deno.test("parseWardrobeGraph defaults to menswear", () => {
  assertEquals(parseWardrobeGraph(undefined), "menswear_3_role");
  assertEquals(parseWardrobeGraph("womenswear"), "womenswear");
  assertEquals(parseWardrobeGraph("nope"), "menswear_3_role");
});

Deno.test("women's generate beams are dress+shoes or separates", () => {
  const sets = requiredRoleSetsForGeneration("womenswear");
  assertEquals(sets.length, 2);
  assertEquals([...sets[0]!], ["dress", "shoes"]);
  assertEquals([...sets[1]!], ["top", "bottom", "shoes"]);
});

Deno.test("men's generate beam is unchanged", () => {
  assertEquals(
    requiredRoleSetsForGeneration("menswear_3_role").map((s) => [...s]),
    [["top", "bottom", "shoes"]],
  );
});

Deno.test("women's shoes anchor tries dress or top+bottom", () => {
  const sets = requiredRoleSetsForAnchor("shoes", "womenswear");
  assertEquals(sets.map((s) => [...s]), [["dress"], ["top", "bottom"]]);
});

Deno.test("a locked dress cannot ride the separates beam", () => {
  assertEquals(roleSetAcceptsLocks(["dress", "shoes"], ["dress"]), true);
  assertEquals(roleSetAcceptsLocks(["top", "bottom", "shoes"], ["dress"]), false);
});
