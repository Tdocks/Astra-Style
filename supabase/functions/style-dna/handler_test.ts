// ============================================================================
// style-dna/handler_test.ts
// ============================================================================
// The whole request path — auth, rate limit, retrieval, provider call,
// response validation, persistence — with every dependency mocked at its
// interface. No Supabase project, no provider key, no network.
//
// The test that matters most for P2-CORE-02's second acceptance criterion
// ("Switching the live adapter to a different provider requires no
// client-side change") is `a different provider changes the output and
// nothing else`: it runs the same request through two unrelated
// `StylistReasoningProvider` implementations and asserts the response shape,
// the persisted columns and the status code are identical. That is the
// provider-neutrality claim, checked rather than asserted in prose.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { serverError } from "../_shared/errors.ts";
import type {
  StylistCompletionRequest,
  StylistCompletionResult,
  StylistReasoningProvider,
} from "../_shared/providers/stylistReasoning.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import { DeterministicStylistProvider } from "./deterministicStylist.ts";
import {
  type GeneratedSummary,
  handleGenerateStyleDna,
  type HandlerDeps,
  type ProfileRows,
  STYLE_DNA_SYSTEM_PROMPT,
  type StyleProfileRepository,
} from "./handler.ts";

const JWT_A = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const JWT_B = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWIifQ.YW5vdGhlcl9mYWtlX3NpZ25hdHVyZQ";
const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const USER_B_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function authClient(): AuthClient {
  return {
    auth: {
      getUser(jwt?: string) {
        if (jwt === JWT_A) {
          return Promise.resolve({ data: { user: { id: USER_A_ID } }, error: null });
        }
        if (jwt === JWT_B) {
          return Promise.resolve({ data: { user: { id: USER_B_ID } }, error: null });
        }
        return Promise.resolve({ data: { user: null }, error: { message: "invalid token" } });
      },
    },
  };
}

const USER_A_ROWS: ProfileRows = {
  style: {
    user_id: USER_A_ID,
    primary_identity: "modern_heritage",
    secondary_identities: ["rugged_utility"],
    style_goals: ["build_complete_wardrobe"],
    preferred_fit: "tailored",
    preference_vector: {
      comparisons_answered: 3,
      comparisons_offered: 3,
      dimensions: {
        formality: { score: 0.7, confidence: "moderate", observations: 2, agreement: 1 },
      },
    },
  },
  body: { user_id: USER_A_ID, chest_cm: "104.00" },
  lifestyle: {
    user_id: USER_A_ID,
    dress_code: "business_casual",
    typical_week: "Mostly in an office",
  },
  wardrobeGraph: "menswear_3_role",
};

const USER_B_ROWS: ProfileRows = {
  style: { user_id: USER_B_ID, primary_identity: "luxury_streetwear" },
  body: null,
  lifestyle: null,
  wardrobeGraph: "menswear_3_role",
};

function recordingRepository(
  rowsByUser: Record<string, ProfileRows> = { [USER_A_ID]: USER_A_ROWS, [USER_B_ID]: USER_B_ROWS },
): StyleProfileRepository & {
  loads: string[];
  saves: Array<{ userId: string; summary: GeneratedSummary }>;
} {
  const loads: string[] = [];
  const saves: Array<{ userId: string; summary: GeneratedSummary }> = [];
  return {
    loads,
    saves,
    load(userId: string) {
      loads.push(userId);
      return Promise.resolve(
        rowsByUser[userId] ?? {
          style: null,
          body: null,
          lifestyle: null,
          wardrobeGraph: "menswear_3_role",
        },
      );
    },
    saveGeneratedSummary(userId: string, summary: GeneratedSummary) {
      saves.push({ userId, summary });
      return Promise.resolve("2026-07-30T12:00:00.123456+00:00");
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: authClient(),
    profileRepository: recordingRepository(),
    provider: new DeterministicStylistProvider(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-07-30T12:00:05Z"),
    ...overrides,
  };
}

function requestFor(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://example.com/style-dna/generate", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const ENVELOPE = { request_id: "test-request-id", client_version: "ios/1.0.0", body: {} };

// ---------------------------------------------------------------------------
// Auth, rate limiting, method
// ---------------------------------------------------------------------------

Deno.test("rejects a request with no Authorization header", async () => {
  const response = await handleGenerateStyleDna(requestFor(ENVELOPE), buildDeps());
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error.category, "auth");
});

Deno.test("rejects a malformed JWT", async () => {
  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: "Bearer nope" }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("an unauthenticated request never reads a profile", async () => {
  const repository = recordingRepository();
  await handleGenerateStyleDna(requestFor(ENVELOPE), buildDeps({ profileRepository: repository }));
  assertEquals(repository.loads.length, 0);
});

Deno.test("exceeding the rate limit is a 429 with Retry-After", async () => {
  const deps = buildDeps({ rateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }) });
  assertEquals(
    (await handleGenerateStyleDna(requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }), deps))
      .status,
    200,
  );
  const second = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    deps,
  );
  assertEquals(second.status, 429);
  assertNotEquals(second.headers.get("Retry-After"), null);
});

Deno.test("a CORS preflight is answered without authentication", async () => {
  const response = await handleGenerateStyleDna(
    new Request("https://example.com/style-dna/generate", { method: "OPTIONS" }),
    buildDeps(),
  );
  assertEquals(response.status, 204);
});

Deno.test("a non-POST verb is rejected", async () => {
  const response = await handleGenerateStyleDna(
    new Request("https://example.com/style-dna/generate", { method: "GET" }),
    buildDeps(),
  );
  assertEquals(response.status, 405);
});

Deno.test("a non-object body is a 400, not a silently-accepted request", async () => {
  const response = await handleGenerateStyleDna(
    requestFor({ request_id: "r", body: "regenerate" }, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps(),
  );
  assertEquals(response.status, 400);
});

// ---------------------------------------------------------------------------
// Ownership
// ---------------------------------------------------------------------------

Deno.test("the profile read is always for the JWT's user", async () => {
  const repository = recordingRepository();
  await handleGenerateStyleDna(
    // The body is empty by design, so there is nothing to substitute — but a
    // client could still send a user_id, and it must reach nothing.
    requestFor(
      { request_id: "r", body: { user_id: USER_B_ID } },
      { Authorization: `Bearer ${JWT_A}` },
    ),
    buildDeps({ profileRepository: repository }),
  );
  assertEquals(repository.loads, [USER_A_ID]);
  assertEquals(repository.saves[0]?.userId, USER_A_ID);
});

Deno.test("two users get two different results from the same request", async () => {
  const deps = buildDeps();
  const a = await (await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    deps,
  )).json();
  const b = await (await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_B}` }),
    deps,
  )).json();

  assertEquals(a.data.primary_identity, "modern_heritage");
  assertEquals(b.data.primary_identity, "luxury_streetwear");
});

// ---------------------------------------------------------------------------
// The happy path and what it persists
// ---------------------------------------------------------------------------

Deno.test("a valid request returns all six §6.10 sections", async () => {
  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps(),
  );
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertEquals(json.request_id, "test-request-id");

  const dna = json.data;
  assertEquals(dna.primary_identity, "modern_heritage"); // §6.10 primary identity
  assert(Array.isArray(dna.secondary_influences)); // §6.10 secondary influences
  assert(dna.palette.preferred_colors.length > 0); // §6.10 preferred palette
  assert(dna.silhouette.headline.length > 0); // §6.10 silhouette direction
  assert(dna.signature_opportunities.length > 0); // §6.10 signature items
  assert(dna.wardrobe_priorities.length > 0); // §6.10 wardrobe priorities
  assert(dna.summary.length > 0);
});

Deno.test("the generated_at timestamp is whole-second ISO-8601, which is all the client can decode", async () => {
  // The repository returns Postgres's microsecond precision
  // ("2026-07-30T12:00:00.123456+00:00"); passing that through would fail
  // `JSONDecoder.dateDecodingStrategy = .iso8601` on device. See
  // _shared/time.ts.
  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps(),
  );
  const json = await response.json();
  assertEquals(json.data.generated_at, "2026-07-30T12:00:00Z");
});

Deno.test("the four summary columns and the palette are persisted; the user's own answers are not", async () => {
  const repository = recordingRepository();
  await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ profileRepository: repository }),
  );

  const summary = repository.saves[0]?.summary;
  assert(summary !== undefined);
  assertEquals(Object.keys(summary).sort(), [
    "accessory_preference",
    "avoided_colors",
    "formality_preference",
    "logo_tolerance",
    "preferred_colors",
    "style_summary",
    "trend_tolerance",
  ]);
  // Not `preference_vector`, `primary_identity`, `secondary_identities`,
  // `style_goals` or `preferred_fit` — those are the user's answers and
  // POST /profile/complete-onboarding owns them. A generator writing back
  // over its own inputs makes regeneration non-idempotent.
});

Deno.test("regenerating twice produces the same result for an unchanged profile", async () => {
  const deps = buildDeps();
  const first = await (await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    deps,
  )).json();
  const second = await (await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    deps,
  )).json();
  assertEquals(JSON.stringify(first.data), JSON.stringify(second.data));
});

Deno.test("a profile with no rows at all still returns 200 with an honest, thin result", async () => {
  const empty = recordingRepository({});
  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ profileRepository: empty }),
  );
  assertEquals(response.status, 200);
  const dna = (await response.json()).data;
  assertEquals(dna.primary_identity, null);
  assert(dna.open_questions.length > 0);
  assert(dna.summary.length > 0);
});

// ---------------------------------------------------------------------------
// The provider seam
// ---------------------------------------------------------------------------

/** A second, unrelated provider — the stand-in for a live vendor adapter. */
class FixtureProvider implements StylistReasoningProvider {
  lastRequest: StylistCompletionRequest | null = null;

  complete(request: StylistCompletionRequest): Promise<StylistCompletionResult> {
    this.lastRequest = request;
    return Promise.resolve({
      message: JSON.stringify({
        primary_identity: "executive",
        identity_basis: "a different provider's reading",
        secondary_influences: ["minimalist"],
        palette: {
          preferred_colors: ["navy"],
          avoided_colors: ["neon brights"],
          rationale: "A suiting palette.",
        },
        silhouette: { headline: "Cut close.", detail: "Tailoring reads well when it fits." },
        signature_opportunities: [{ title: "A navy suit", reason: "It doubles as separates." }],
        wardrobe_priorities: [{
          rank: 1,
          title: "One suit that fits",
          reason: "Alteration is part of the price.",
        }],
        summary: "You are Executive.",
        formality_preference: "very_formal",
        logo_tolerance: 5,
        trend_tolerance: 20,
        accessory_preference: "minimal",
        known_inputs: ["your work dress code"],
        open_questions: [],
        measured_dimensions: [],
      }),
      toolCalls: [],
      finishReason: "stop",
      usage: { inputTokens: 1200, outputTokens: 400 },
      modelIdentifier: "some-vendor-model/2026-07",
    });
  }

  // deno-lint-ignore require-yield
  async *completeStream(): AsyncIterable<{ delta: string; toolCallDelta?: unknown }> {
    await Promise.resolve();
    throw new ProviderError("INVALID_INPUT", false, "not supported");
  }
}

Deno.test("a different provider changes the output and nothing else", async () => {
  const deterministicRepo = recordingRepository();
  const fixtureRepo = recordingRepository();

  const deterministic = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ profileRepository: deterministicRepo }),
  );
  const fixture = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ profileRepository: fixtureRepo, provider: new FixtureProvider() }),
  );

  // Same status, same envelope, same field set — a provider swap is invisible
  // to the client, which is ADR 0004's decision 4 and P2-CORE-02's second
  // acceptance criterion.
  assertEquals(deterministic.status, fixture.status);
  const a = (await deterministic.json()).data;
  const b = (await fixture.json()).data;
  assertEquals(Object.keys(a).sort(), Object.keys(b).sort());
  assertEquals(
    Object.keys(deterministicRepo.saves[0]?.summary ?? {}).sort(),
    Object.keys(fixtureRepo.saves[0]?.summary ?? {}).sort(),
  );

  // Only the content and the reported model differ.
  assertNotEquals(a.primary_identity, b.primary_identity);
  assertNotEquals(a.model_identifier, b.model_identifier);
  assertEquals(b.model_identifier, "some-vendor-model/2026-07");
});

Deno.test("the provider is handed a complete, real request — not an empty stub", async () => {
  const provider = new FixtureProvider();
  await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ provider }),
  );

  const request = provider.lastRequest;
  assert(request !== null);
  assertEquals(request.systemPrompt, STYLE_DNA_SYSTEM_PROMPT);
  // docs/09-model-routing.md §1 row 6: Style DNA generation defaults to Terra.
  assertEquals(request.tier, "terra");
  assertEquals(request.stream, false);
  assert(Object.keys(request.responseSchema).length > 0);
  // The packet actually carries the profile, so a live adapter has something
  // to serialize into a prompt.
  const packet = JSON.stringify(request.contextPacket);
  assert(packet.includes("modern_heritage"));
  assert(packet.includes("business_casual"));
  // ...and carries nothing identifying.
  assert(!packet.includes(USER_A_ID));
});

Deno.test("a provider that returns an invented identity is a retryable 502, not a 500 or a write", async () => {
  const repository = recordingRepository();

  class RogueProvider implements StylistReasoningProvider {
    complete(): Promise<StylistCompletionResult> {
      return Promise.resolve({
        message: JSON.stringify({ primary_identity: "dark_academia" }),
        toolCalls: [],
        finishReason: "stop",
        usage: { inputTokens: 0, outputTokens: 0 },
        modelIdentifier: "rogue/1",
      });
    }
    // deno-lint-ignore require-yield
    async *completeStream(): AsyncIterable<{ delta: string; toolCallDelta?: unknown }> {
      await Promise.resolve();
      throw new ProviderError("INVALID_INPUT", false, "not supported");
    }
  }

  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ provider: new RogueProvider(), profileRepository: repository }),
  );

  assertEquals(response.status, 502);
  const json = await response.json();
  // "provider", not "validation": nothing was wrong with the user's request,
  // and telling him otherwise would send him to change a correct answer.
  assertEquals(json.error.category, "provider");
  // Nothing was persisted from an output that failed validation.
  assertEquals(repository.saves.length, 0);
});

Deno.test("a retryable provider outage is a 502; a non-retryable one is a 500", async () => {
  const failing = (retryable: boolean): StylistReasoningProvider => ({
    complete(): Promise<StylistCompletionResult> {
      return Promise.reject(
        new ProviderError(retryable ? "TIMEOUT" : "AUTH_FAILED", retryable, "provider said no"),
      );
    },
    // deno-lint-ignore require-yield
    async *completeStream(): AsyncIterable<{ delta: string; toolCallDelta?: unknown }> {
      await Promise.resolve();
      throw new ProviderError("INVALID_INPUT", false, "not supported");
    },
  });

  const transient = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ provider: failing(true) }),
  );
  assertEquals(transient.status, 502);
  assertEquals((await transient.json()).error.category, "provider");

  const permanent = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ provider: failing(false) }),
  );
  // A misconfigured key is ours to fix, not something a client retry helps.
  assertEquals(permanent.status, 500);
});

Deno.test("a failed profile read never writes a thin result over a good one", async () => {
  const failing: StyleProfileRepository = {
    load() {
      return Promise.reject(serverError("Couldn't read your profile."));
    },
    saveGeneratedSummary() {
      throw new Error("must not be reached");
    },
  };
  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ profileRepository: failing }),
  );
  assertEquals(response.status, 500);
});

Deno.test("a failed persist is reported rather than returning an unsaved result", async () => {
  const failing: StyleProfileRepository = {
    load() {
      return Promise.resolve(USER_A_ROWS);
    },
    saveGeneratedSummary() {
      return Promise.reject(serverError("Couldn't save your Style DNA."));
    },
  };
  const response = await handleGenerateStyleDna(
    requestFor(ENVELOPE, { Authorization: `Bearer ${JWT_A}` }),
    buildDeps({ profileRepository: failing }),
  );
  // Returning the DNA anyway would show a result the next screen load
  // contradicts.
  assertEquals(response.status, 500);
});
