import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { composeStyleDna, DeterministicStylistProvider } from "./deterministicStylist.ts";
import {
  evaluateStyleDnaGoldenOutput,
  runStyleDnaGoldenEvaluation,
  STYLE_DNA_GOLDEN_CASES,
} from "./goldenEvaluation.ts";

Deno.test("Style DNA golden profiles preserve sparse uncertainty and identity evidence", async () => {
  const results = await runStyleDnaGoldenEvaluation(new DeterministicStylistProvider());
  assertEquals(results.length, 3);
  for (const result of results) {
    assert(result.passed, `${result.id}: ${result.failures.join(", ")}`);
    assert(result.modelIdentifier.startsWith("astra-deterministic-stylist/"));
  }

  const identityOnly = results.find((result) => result.id === "identity-only-quiet-luxury")!;
  const noIdentity = results.find((result) => result.id === "sparse-no-identity")!;
  const measured = results.find((result) => result.id === "measured-streetwear")!;
  assertEquals(identityOnly.document!.primary_identity, "quiet_luxury");
  assertEquals(identityOnly.document!.open_questions.length > 0, true);
  assertEquals(noIdentity.document!.primary_identity, null);
  assertEquals(noIdentity.document!.open_questions.length > 0, true);
  assertEquals(measured.document!.primary_identity, "luxury_streetwear");
  assertNotEquals(
    identityOnly.document!.signature_opportunities.map((item) => item.title).join("|"),
    measured.document!.signature_opportunities.map((item) => item.title).join("|"),
  );
});

Deno.test("live golden evaluator reports schema failures without exposing model output", () => {
  const result = evaluateStyleDnaGoldenOutput(
    STYLE_DNA_GOLDEN_CASES[0]!,
    "not-json",
    "configured-model/2026-10",
  );
  assertEquals(result.passed, false);
  assertEquals(result.document, null);
  assertEquals(result.failures, ["provider response failed the Style DNA schema validator"]);
});

Deno.test("identity-only acceptance allows honest empty recommendations and unknown silhouette", () => {
  const testCase = STYLE_DNA_GOLDEN_CASES[0]!;
  const document = composeStyleDna(testCase.context);
  document.palette.preferred_colors = [];
  document.palette.avoided_colors = [];
  document.palette.rationale = "No color choices are recorded yet.";
  document.silhouette.headline = "Direction still open.";
  document.silhouette.detail = "No cut preference is recorded yet.";
  document.signature_opportunities = [];
  document.wardrobe_priorities = [];

  const result = evaluateStyleDnaGoldenOutput(
    testCase,
    JSON.stringify(document),
    "configured-model/2026-10",
  );
  assert(result.passed, result.failures.join(", "));
});
