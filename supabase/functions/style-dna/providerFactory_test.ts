import { assert, assertEquals, assertRejects } from "@std/assert";
import { ProviderError } from "../_shared/providers/types.ts";
import { DeterministicStylistProvider } from "./deterministicStylist.ts";
import { buildStyleDnaContext } from "./context.ts";
import { buildStyleDnaProvider } from "./providerFactory.ts";
import { ResilientStylistProvider } from "./providerResilience.ts";

Deno.test("configured shared OpenAI credentials select the live Terra adapter", () => {
  const provider = buildStyleDnaProvider({
    imageProvider: "openai",
    imageApiKey: "existing-server-key",
    modelTerra: "configured-terra-model",
  });
  assert(provider instanceof ResilientStylistProvider);
});

Deno.test("dedicated stylist credential takes precedence over image credential", () => {
  const provider = buildStyleDnaProvider({
    stylistApiKey: "dedicated-server-key",
    imageProvider: "other",
    imageApiKey: "unused-image-key",
  });
  assert(provider instanceof ResilientStylistProvider);
});

Deno.test("missing live credentials do not silently select deterministic output", async () => {
  const provider = buildStyleDnaProvider({ imageProvider: "openai" });
  assert(!(provider instanceof DeterministicStylistProvider));
  const error = await assertRejects(
    () => provider.complete({} as never, { requestId: "r", userId: "u", timeoutMs: 1 }),
    ProviderError,
  );
  assertEquals(error.isConfigurationIssue, true);
  assertEquals(error.retryable, false);
});

Deno.test("deterministic content requires an explicit preview mode and reports its identity", async () => {
  const provider = buildStyleDnaProvider({ mode: "deterministic" });
  assert(provider instanceof DeterministicStylistProvider);
  const result = await provider.complete({
    systemPrompt: "",
    contextPacket: buildStyleDnaContext(
      {
        primary_identity: "quiet_luxury",
        secondary_identities: [],
        style_goals: [],
        preference_vector: {},
      },
      null,
      null,
    ) as unknown as Record<string, unknown>,
    messages: [],
    tools: [],
    responseSchema: {},
    maxOutputTokens: 1,
    temperature: 0,
    stream: false,
    tier: "terra",
  }, { requestId: "r", userId: "u", timeoutMs: 1 });
  assert(result.modelIdentifier.startsWith("astra-deterministic-stylist/"));
});
