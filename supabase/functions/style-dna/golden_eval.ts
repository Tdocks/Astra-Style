import { buildStyleDnaProvider } from "./providerFactory.ts";
import { runStyleDnaGoldenEvaluation } from "./goldenEvaluation.ts";

if (import.meta.main) {
  const provider = buildStyleDnaProvider({
    mode: Deno.env.get("STYLE_DNA_PROVIDER") ?? "openai",
    stylistApiKey: Deno.env.get("STYLIST_PROVIDER_API_KEY"),
    imageProvider: Deno.env.get("IMAGE_GENERATION_PROVIDER"),
    imageApiKey: Deno.env.get("IMAGE_PROVIDER_API_KEY"),
    modelLuna: Deno.env.get("STYLIST_PROVIDER_MODEL_LUNA"),
    modelTerra: Deno.env.get("STYLIST_PROVIDER_MODEL_TERRA"),
  });

  try {
    const results = await runStyleDnaGoldenEvaluation(provider);
    const report = results.map(({ id, modelIdentifier, passed, failures }) => ({
      id,
      model_identifier: modelIdentifier,
      passed,
      failures,
    }));
    console.log(
      JSON.stringify({
        total: report.length,
        passed: report.filter((r) => r.passed).length,
        cases: report,
      }),
    );
    if (report.some((result) => !result.passed)) Deno.exit(1);
  } catch (error) {
    // Never print prompts, profile packets, provider response bodies, or credentials.
    console.error(JSON.stringify({
      event: "style_dna_golden_eval.failed",
      error_name: error instanceof Error ? error.name : "unknown",
    }));
    Deno.exit(1);
  }
}
