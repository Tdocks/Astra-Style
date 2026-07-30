// ============================================================================
// style-dna/context_test.ts
// ============================================================================
// Retrieval, tested without a provider. The cases here are the ones where a
// plausible-looking implementation is quietly wrong:
//
//   - PostgREST returns `numeric` columns as STRINGS. Reading only numbers
//     would drop every measurement and every budget, and the symptom — a
//     profile that behaves exactly like a skipped step — is invisible.
//   - The preference vector's three states (measured / asked-and-declined /
//     never-asked) have to survive retrieval as well as submission.
//   - Nothing identifying may reach the context packet, because the packet is
//     what a live provider would be sent.
// ============================================================================

import { assert, assertEquals } from "@std/assert";
import { buildStyleDnaContext, confidenceWeight, isStatable } from "./context.ts";

Deno.test("numeric columns arriving as strings are read, not dropped", () => {
  const context = buildStyleDnaContext(
    null,
    // PostgREST serializes numeric(5,2) as "104.00", not 104.
    { chest_cm: "104.00", waist_cm: "88.00" },
    { monthly_budget: "250.00", currency: "GBP" },
  );
  assertEquals(context.body.hasAnyMeasurement, true);
  assertEquals(context.lifestyle.monthlyBudget, 250);
});

Deno.test("a body row with every measurement null reports no measurements", () => {
  const context = buildStyleDnaContext(null, {
    chest_cm: null,
    waist_cm: null,
    height_value_cm: null,
    weight_value_kg: null,
    inseam_cm: null,
    neck_cm: null,
    fit_notes: [],
  }, null);
  assertEquals(context.body.hasAnyMeasurement, false);
});

Deno.test("three missing rows produce an empty but usable context", () => {
  const context = buildStyleDnaContext(null, null, null);
  assertEquals(context.identity.primary, null);
  assertEquals(context.goals, []);
  assertEquals(context.body.hasAnyMeasurement, false);
  assertEquals(context.lifestyle.dressCode, null);
  assertEquals(Object.keys(context.vector.dimensions).length, 0);
});

Deno.test("an asked-but-declined axis is retrieved, an unasked one is not invented", () => {
  const context = buildStyleDnaContext(
    {
      preference_vector: {
        comparisons_answered: 2,
        comparisons_offered: 3,
        dimensions: {
          formality: { score: 0.5, confidence: "low", observations: 1, agreement: 1 },
          texture: { score: null, confidence: "insufficient", observations: 0, agreement: null },
        },
      },
    },
    null,
    null,
  );

  assertEquals(Object.keys(context.vector.dimensions).sort(), ["formality", "texture"]);
  assertEquals(context.vector.dimensions["texture"]?.score, null);
  assertEquals(context.vector.dimensions["texture"]?.observations, 0);
  assertEquals(context.vector.dimensions["colour_tolerance"], undefined);
  assertEquals(context.vector.comparisonsAnswered, 2);
  assertEquals(context.vector.comparisonsOffered, 3);
});

Deno.test("a frame axis with no confidence is treated as no axis", () => {
  // derive_frame_axes() always writes the pair together, so a value without a
  // confidence means a row predating that trigger. Assuming certainty there
  // would be assuming a measurement.
  const context = buildStyleDnaContext(null, {
    frame_taper: "strong",
    frame_taper_confidence: null,
  }, null);
  assertEquals(context.body.taper, null);
});

Deno.test("a frame axis with a confidence is carried through", () => {
  const context = buildStyleDnaContext(null, {
    frame_scale: "tall",
    frame_scale_confidence: 0.8,
  }, null);
  assertEquals(context.body.scale?.value, "tall");
  assertEquals(context.body.scale?.confidence, 0.8);
});

Deno.test("the appearance blob yields only skin undertone, and nothing identifying", () => {
  const context = buildStyleDnaContext(null, {
    appearance: {
      skin_undertone: "Cool",
      hair_color: "Dark brown",
      reference_selfie_paths: ["users/abc/references/1.jpg"],
    },
  }, null);
  assertEquals(context.body.skinUndertone, "Cool");
  assert(!JSON.stringify(context).includes("references/1.jpg"));
});

Deno.test("no user identifier appears anywhere in the packet", () => {
  const context = buildStyleDnaContext(
    { user_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", primary_identity: "executive" },
    { user_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" },
    { user_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" },
  );
  assert(!JSON.stringify(context).includes("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"));
});

Deno.test("raw measurements are not in the packet, only whether any exist", () => {
  // Spec §11 forbids implying exact fit. The derived frame axes are what
  // advice actually uses, and keeping the centimetres out of the prompt means
  // no future prompt log or vendor retention window holds them.
  const context = buildStyleDnaContext(null, { chest_cm: "104.00", waist_cm: "88.00" }, null);
  const serialized = JSON.stringify(context);
  assert(!serialized.includes("104"));
  assert(!serialized.includes("88"));
});

Deno.test("confidence weight rises with the band and is zero for insufficient", () => {
  assertEquals(confidenceWeight("insufficient"), 0);
  assert(confidenceWeight("low") > 0);
  assert(confidenceWeight("moderate") > confidenceWeight("low"));
  assert(confidenceWeight("high") > confidenceWeight("moderate"));
  // An unrecognised band contributes nothing rather than defaulting to a
  // weight it has not earned.
  assertEquals(confidenceWeight("very sure indeed"), 0);
});

Deno.test("only moderate and high may be stated back to the user", () => {
  const reading = (confidence: string, score: number | null) => ({
    score,
    confidence,
    observations: 2,
    agreement: 1,
  });
  assertEquals(isStatable(reading("high", 0.5)), true);
  assertEquals(isStatable(reading("moderate", 0.5)), true);
  assertEquals(isStatable(reading("low", 0.5)), false);
  assertEquals(isStatable(reading("insufficient", null)), false);
  assertEquals(isStatable(undefined), false);
  // A band high enough to state, with no score to state, is still not
  // statable — the two conditions are independent.
  assertEquals(isStatable(reading("high", null)), false);
});
