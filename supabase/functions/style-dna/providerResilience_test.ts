import { assertEquals, assertRejects } from "@std/assert";
import type {
  StylistCompletionRequest,
  StylistCompletionResult,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import { ResilientStylistProvider } from "./providerResilience.ts";

const request = {} as StylistCompletionRequest;
const context = { requestId: "req", userId: "user", timeoutMs: 10 };
const success: StylistCompletionResult = {
  message: "{}",
  toolCalls: [],
  finishReason: "stop",
  usage: { inputTokens: 1, outputTokens: 1 },
  modelIdentifier: "fixture/1",
};

function fakeProvider(complete: () => Promise<StylistCompletionResult>): StylistReasoningProvider {
  return {
    complete,
    // deno-lint-ignore require-yield
    async *completeStream() {
      throw new Error("unused");
    },
  };
}

Deno.test("retries one transient provider failure and returns only the successful live result", async () => {
  let calls = 0;
  const waits: number[] = [];
  const provider = new ResilientStylistProvider(
    fakeProvider(async () => {
      await Promise.resolve();
      calls++;
      if (calls === 1) throw new ProviderError("RATE_LIMITED", true, "rate limited");
      return success;
    }),
    {
      random: () => 0.5,
      sleep: (ms) => Promise.resolve().then(() => waits.push(ms)).then(() => undefined),
    },
  );

  assertEquals(await provider.complete(request, context), success);
  assertEquals(calls, 2);
  assertEquals(waits, [125]);
});

Deno.test("does not retry non-retryable provider errors", async () => {
  let calls = 0;
  const provider = new ResilientStylistProvider(
    fakeProvider(async () => {
      await Promise.resolve();
      calls++;
      throw new ProviderError("AUTH_FAILED", false, "auth failed");
    }),
    { sleep: () => Promise.resolve() },
  );

  await assertRejects(() => provider.complete(request, context), ProviderError);
  assertEquals(calls, 1);
});

Deno.test("opens after five provider failures and admits one half-open probe after thirty seconds", async () => {
  let now = 1_000;
  let calls = 0;
  const provider = new ResilientStylistProvider(
    fakeProvider(async () => {
      await Promise.resolve();
      calls++;
      throw new ProviderError("PROVIDER_UNAVAILABLE", false, "down");
    }),
    { now: () => now, sleep: () => Promise.resolve() },
  );

  for (let index = 0; index < 5; index++) {
    await assertRejects(() => provider.complete(request, context), ProviderError);
  }
  const circuitError = await assertRejects(
    () => provider.complete(request, context),
    ProviderError,
  );
  assertEquals(circuitError.message, "Stylist provider circuit is open.");
  assertEquals(calls, 5);

  now += 30_000;
  await assertRejects(() => provider.complete(request, context), ProviderError);
  assertEquals(calls, 6); // probe; this failure is explicitly non-retryable
});

Deno.test("a successful call clears the rolling failure streak", async () => {
  let now = 10_000;
  let calls = 0;
  const provider = new ResilientStylistProvider(
    fakeProvider(async () => {
      await Promise.resolve();
      calls++;
      if (calls <= 4) throw new ProviderError("PROVIDER_UNAVAILABLE", false, "down");
      return success;
    }),
    { now: () => now, sleep: () => Promise.resolve() },
  );

  for (let index = 0; index < 4; index++) {
    await assertRejects(() => provider.complete(request, context), ProviderError);
    now += 1;
  }
  assertEquals(await provider.complete(request, context), success);
  assertEquals(await provider.complete(request, context), success);
  assertEquals(calls, 6);
});
