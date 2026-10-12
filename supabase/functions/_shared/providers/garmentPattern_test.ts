import { assertEquals } from "@std/assert";
import { OpenAIVisionAnalysisProvider } from "./openaiVisionAnalysis.ts";
import { resolveGarmentPattern } from "./garmentPattern.ts";

Deno.test("garment evidence corrects contradictory camouflage and plaid labels", () => {
  assertEquals(
    resolveGarmentPattern("check", "Irregular camouflage patches cover the shirt.", "top"),
    { value: "print", corrected: true },
  );
  assertEquals(
    resolveGarmentPattern("texture-only", "Red and black plaid checks cover the fabric.", "top"),
    { value: "check", corrected: true },
  );
});
Deno.test("background and negative cues cannot force a garment pattern", () => {
  assertEquals(resolveGarmentPattern("solid", "Plain shirt on a plaid rug background.", "top"), {
    value: "solid",
    corrected: false,
  });
  assertEquals(resolveGarmentPattern("solid", "There are no plaid checks on this shirt.", "top"), {
    value: "solid",
    corrected: false,
  });
});
Deno.test("ordinary leather creases are solid but decorative footwear remains textured", () => {
  assertEquals(
    resolveGarmentPattern("texture-only", "Black leather with wrinkles and creases.", "shoes"),
    { value: "solid", corrected: true },
  );
  assertEquals(
    resolveGarmentPattern("texture-only", "Embossed crocodile leather grain.", "shoes"),
    { value: "texture-only", corrected: false },
  );
  assertEquals(resolveGarmentPattern("texture-only", "Braided leather with grain.", "shoes"), {
    value: "texture-only",
    corrected: false,
  });
});
Deno.test("small isolated logo stays solid without suppressing camouflage", () => {
  assertEquals(
    resolveGarmentPattern("print", "Otherwise plain yellow body with a small chest logo.", "top"),
    { value: "solid", corrected: true },
  );
  assertEquals(
    resolveGarmentPattern("print", "Camouflage fabric with a small chest logo.", "top"),
    { value: "print", corrected: false },
  );
});
Deno.test("weave descriptions retain herringbone and competing cues stay unmodified", () => {
  assertEquals(
    resolveGarmentPattern("print", "Herringbone weave across the fabric.", "outerwear"),
    { value: "herringbone", corrected: true },
  );
  assertEquals(
    resolveGarmentPattern("print", "Floral motifs and plaid checks both appear.", "top"),
    { value: "print", corrected: false },
  );
});

Deno.test("provider propagates corrected pattern as a field requiring review", async () => {
  const provider = new OpenAIVisionAnalysisProvider({
    apiKey: "test-only",
    model: "test-only",
    loadImageBytes: () => Promise.resolve(new Uint8Array([0xff, 0xd8, 0xff])),
    fetchImpl: () =>
      Promise.resolve(Response.json({
        choices: [{
          message: {
            content: JSON.stringify({
              category: "shoes",
              subcategory: "ankle boot",
              confidence: 0.95,
              primary_color_name: "black",
              secondary_color_names: [],
              pattern: "texture-only",
              pattern_evidence: "Black leather with wrinkles and creases on the shaft.",
              fields_below_confidence_threshold: ["size"],
            }),
          },
        }],
      })),
  });
  const result = await provider.analyzeGarment({ imageStoragePath: "test.jpg" }, {
    requestId: "test-only",
    userId: "test-only",
    timeoutMs: 1000,
  });
  assertEquals(result.pattern, "solid");
  assertEquals(result.fieldsBelowConfidenceThreshold, ["size", "pattern"]);
  assertEquals("pattern_evidence" in result, false);
});

Deno.test("boot print contradiction is corrected without erasing real colored motifs", () => {
  assertEquals(
    resolveGarmentPattern("print", "Black leather with creases on the shaft.", "shoes"),
    { value: "solid", corrected: true },
  );
  assertEquals(resolveGarmentPattern("print", "Floral printed leather with creases.", "shoes"), {
    value: "print",
    corrected: false,
  });
});
Deno.test("provider reconciles coatigan slot while preserving warm ivory color", async () => {
  const provider = new OpenAIVisionAnalysisProvider({
    apiKey: "test",
    model: "test",
    loadImageBytes: () => Promise.resolve(new Uint8Array([1])),
    fetchImpl: () =>
      Promise.resolve(
        Response.json({
          choices: [{
            message: {
              content: JSON.stringify({
                category: "top",
                subcategory: "coatigan",
                primary_color_name: "ivory",
                pattern: "solid",
                pattern_evidence: "Plain fabric",
                fields_below_confidence_threshold: [],
              }),
            },
          }],
        }),
      ),
  });
  const result = await provider.analyzeGarment({ imageStoragePath: "test.jpg" }, {
    requestId: "test",
    userId: "test",
    timeoutMs: 1000,
  });
  assertEquals(result.category, "outerwear");
  assertEquals(result.primaryColorName?.value, "ivory");
  assertEquals(result.fieldsBelowConfidenceThreshold, ["category"]);
});
