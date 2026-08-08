// ============================================================================
// _shared/providers/openaiVisionAnalysis_test.ts
// ============================================================================
// Contract tests for the live vision adapter's response schema.
//
// Every assertion here exists because the corresponding mistake was already
// made, and none of them were caught by `deno task check` — a JSON Schema is
// just an object literal to the compiler, and a vocabulary that disagrees with
// `closet/mapper.ts` is two valid string sets that happen not to overlap.
// They surfaced instead as an HTTP 400 from the vendor, or worse, as a correct
// answer quietly discarded downstream. The `docs/08` §2.5 pilot gate found all
// of them in one sitting; this file is what stops the next one needing a
// production round-trip to find.
//
// These tests make no network call. They read the schema as data.
// ============================================================================

import { assert, assertEquals } from "@std/assert";
import { RESULT_SCHEMA } from "./openaiVisionAnalysis.ts";
import { CATEGORIES, FITS, SEASONS } from "../../closet/mapper.ts";

type SchemaNode = {
  type?: string | string[];
  description?: string;
  enum?: readonly string[];
  anyOf?: readonly SchemaNode[];
  items?: SchemaNode;
  properties?: Record<string, SchemaNode>;
  required?: readonly string[];
  additionalProperties?: boolean;
};

const schema = RESULT_SCHEMA as unknown as SchemaNode;

/** Walks `anyOf` branches to find the one non-null branch, if there is exactly one. */
function unwrapNullable(node: SchemaNode): SchemaNode {
  if (!node.anyOf) return node;
  const nonNull = node.anyOf.filter((branch) => branch.type !== "null");
  assertEquals(nonNull.length, 1, "expected exactly one non-null branch");
  return nonNull[0]!;
}

/**
 * A nullable field carries its `description` on the outer node, beside `anyOf`,
 * while its `enum` sits on the inner branch. Read both rather than assuming.
 */
function descriptionOf(node: SchemaNode): string {
  return node.description ?? unwrapNullable(node).description ?? "";
}

/** Every object node in the schema, so the strict-mode rules can be checked everywhere. */
function objectNodes(node: SchemaNode, path = "$"): Array<[string, SchemaNode]> {
  const found: Array<[string, SchemaNode]> = [];
  if (node.properties) found.push([path, node]);
  for (const branch of node.anyOf ?? []) found.push(...objectNodes(branch, `${path}|anyOf`));
  if (node.items) found.push(...objectNodes(node.items, `${path}[]`));
  for (const [key, child] of Object.entries(node.properties ?? {})) {
    found.push(...objectNodes(child, `${path}.${key}`));
  }
  return found;
}

Deno.test("every property is listed in required, at every level", () => {
  // `strict: true` rejects the whole request otherwise — not the offending
  // field, the whole request. Five optional-by-omission fields (fit, size,
  // seasonality, warmth_score, water_resistance_score) failed the entire scan
  // with: "'required' is required to be supplied and to be an array including
  // every key in properties. Missing 'fit'." Optionality is expressed by a
  // nullable type instead, which is why `unwrapNullable` exists above.
  for (const [path, node] of objectNodes(schema)) {
    const properties = Object.keys(node.properties ?? {}).sort();
    const required = [...(node.required ?? [])].sort();
    assertEquals(required, properties, `${path}: required must list every property`);
  }
});

Deno.test("every object node forbids additional properties", () => {
  // The other half of the same strict-mode contract.
  for (const [path, node] of objectNodes(schema)) {
    assertEquals(node.additionalProperties, false, `${path}: additionalProperties must be false`);
  }
});

Deno.test("category's enum is exactly the mapper's vocabulary", () => {
  // Asked for a free string, the model answered "menswear top" — accurate, and
  // absent from `CATEGORIES`, so `resolveCategory` fell to the device-hint
  // branch at confidence 0.4 and flagged the field for user review. A 0.97
  // reading was presented to the user as a guess. If either vocabulary moves,
  // this fails before a scan does.
  const category = schema.properties!.category!;
  assertEquals([...(category.enum ?? [])].sort(), [...CATEGORIES].sort());
});

Deno.test("fit's enum is exactly the mapper's vocabulary", () => {
  const fit = unwrapNullable(schema.properties!.fit!);
  assertEquals([...(fit.enum ?? [])].sort(), [...FITS].sort());
});

Deno.test("seasonality's item enum is exactly the mapper's vocabulary", () => {
  // "early fall" was a real answer. `mapper.ts` filters against `SEASONS` and
  // drops non-members silently, so the item came back a season short with
  // nothing recorded to say a reading had been thrown away.
  const seasonality = unwrapNullable(schema.properties!.seasonality!);
  assertEquals([...(seasonality.items?.enum ?? [])].sort(), [...SEASONS].sort());
});

Deno.test("the two numeric conventions are both stated in the schema", () => {
  // The 0-100 attribute scores and the 0-1 confidences sit side by side, and
  // the model will not infer either. Asked bare, it returned formality 3 for a
  // casual shirt — right on an unstated 0-10 scale, and near-pyjamas on the
  // 0-100 scale `closet_items.formality_score` enforces, which the check
  // constraint accepts without complaint. Stating only the 0-100 convention
  // then moved the confidences onto 0-100 too (0.93 became 93), defeating
  // `mapper.ts`'s `< 0.6` gate. Both conventions have to be named, always.
  const hundredScale = ["formality_score", "warmth_score", "water_resistance_score"];
  for (const field of hundredScale) {
    const text = descriptionOf(schema.properties![field]!);
    assert(text.includes("0-100"), `${field} must state the 0-100 scale`);
    // Naming the scale is not enough on its own — the wrong answer this field
    // gave was a coherent 0-10 reading, so the description has to rule 0-10
    // out by name rather than leave it as the unstated default.
    assert(text.includes("Not a 0-10 scale"), `${field} must rule out the 0-10 scale by name`);
  }

  const unitScale = ["confidence", "condition_confidence"];
  for (const field of unitScale) {
    const text = descriptionOf(schema.properties![field]!);
    assert(text.includes("0-1"), `${field} must state the 0-1 scale`);
    // Same reasoning mirrored: these fields sit beside 0-100 fields, and the
    // one time the 0-100 convention was stated without this negation, every
    // confidence in the response moved onto 0-100.
    assert(text.includes("Not 0-100"), `${field} must rule out the 0-100 scale by name`);
  }

  const brand = unwrapNullable(schema.properties!.brand_guess!);
  assert(
    descriptionOf(brand.properties!.confidence!).includes("0-1"),
    "brand_guess.confidence must state the 0-1 scale",
  );
});

Deno.test("the fields the mapper reads are all present in the schema", () => {
  // A field the adapter never asks for is a field the closet never gets. This
  // is the list `closet/mapper.ts` actually consumes.
  const consumed = [
    "category",
    "subcategory",
    "confidence",
    "pattern",
    "material",
    "formality_score",
    "brand_guess",
    "normalized_title",
    "condition",
    "condition_confidence",
    "fields_below_confidence_threshold",
    "fit",
    "size",
    "seasonality",
    "warmth_score",
    "water_resistance_score",
  ];
  for (const field of consumed) {
    assert(field in schema.properties!, `schema is missing ${field}, which the mapper reads`);
  }
});
