import { assert, assertEquals } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import type { AuthClient, AuthUser } from "../_shared/jwt.ts";
import {
  type CompatibilityWeightsConfig,
  loadCompatibilityWeightsConfig,
} from "../_shared/scoring/compatibilityWeights.ts";
import type { ComponentWeights } from "../_shared/scoring/compatibility.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { scoreOutfit } from "../_shared/scoring/compatibility.ts";
import { classifyNeutral, rgbToLCh } from "../_shared/scoring/colorSpace.ts";
import type { ScorableItem } from "../_shared/scoring/types.ts";
import {
  handleUpdateCompatibilityWeights,
  parseCompatibilityWeightUpdate,
} from "./compatibilityWeightsAdmin.ts";

const ADMIN_TOKEN = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiJ9.c2lnbmF0dXJl";
const USER_TOKEN = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.c2lnbmF0dXJl";
const DEFAULT_WEIGHTS: ComponentWeights = {
  color: 0.25,
  formality: 0.2,
  silhouette: 0.15,
  seasonWeather: 0.1,
  userPreference: 0.1,
  coWear: 0.1,
  occasion: 0.05,
  availability: 0.05,
};
const COLOR_HEAVY_WEIGHTS: ComponentWeights = {
  color: 0.6,
  formality: 0.1,
  silhouette: 0.1,
  seasonWeather: 0.05,
  userPreference: 0.05,
  coWear: 0.05,
  occasion: 0.025,
  availability: 0.025,
};

function garment(id: string, role: ScorableItem["role"], colorHex: string): ScorableItem {
  const value = Number.parseInt(colorHex, 16);
  const lch = rgbToLCh({ r: (value >> 16) & 255, g: (value >> 8) & 255, b: value & 255 });
  return {
    id,
    category: role,
    role,
    primaryColor: lch,
    isNeutral: classifyNeutral(lch).isNeutral,
    secondaryColors: [],
    pattern: "solid",
    patternScale: null,
    materials: [],
    formalityScore: 50,
    fit: "regular",
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
  };
}

function request(body: unknown, token = ADMIN_TOKEN): Request {
  return new Request("https://example.test/functions/v1/outfits/config/compatibility-weights", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify({ body }),
  });
}

function dependencies(options: {
  readonly user?: AuthUser | null;
  readonly storeUpdate?: (
    expectedVersion: number,
    weights: ComponentWeights,
  ) => Promise<CompatibilityWeightsConfig | null>;
  readonly now?: () => Date;
  readonly rateLimiter?: RateLimiter;
} = {}) {
  let authCalls = 0;
  let updateCalls = 0;
  let receivedVersion = 0;
  let receivedWeights: ComponentWeights | null = null;
  const authClient: AuthClient = {
    auth: {
      getUser(jwt) {
        authCalls++;
        const user = options.user === undefined
          ? jwt === ADMIN_TOKEN
            ? { id: "admin-user", app_metadata: { astra_admin: true } }
            : { id: "regular-user", app_metadata: {}, user_metadata: { astra_admin: true } }
          : options.user;
        return Promise.resolve({
          data: { user },
          error: user ? null : { message: "invalid token" },
        });
      },
    },
  };
  const deps = {
    authClient,
    rateLimiter: options.rateLimiter ?? {
      check: () => ({ allowed: true, remaining: 9, retryAfterSeconds: 0 }),
    },
    now: options.now ?? (() => new Date("2026-10-09T12:00:00Z")),
    store: {
      async updateIfVersion(version: number, weights: ComponentWeights) {
        updateCalls++;
        receivedVersion = version;
        receivedWeights = weights;
        return options.storeUpdate
          ? await options.storeUpdate(version, weights)
          : { version: version + 1, weights };
      },
    },
  };
  return {
    deps,
    get authCalls() {
      return authCalls;
    },
    get updateCalls() {
      return updateCalls;
    },
    get receivedVersion() {
      return receivedVersion;
    },
    get receivedWeights() {
      return receivedWeights;
    },
  };
}

async function errorBody(response: Response): Promise<{ error: { category: string } | null }> {
  return await response.json();
}

Deno.test("weight update requires Supabase-verified admin app_metadata before parsing or writing", async () => {
  const regular = dependencies();
  const denied = await handleUpdateCompatibilityWeights(
    request({ expected_version: 1, weights: DEFAULT_WEIGHTS }, USER_TOKEN),
    regular.deps,
  );
  assertEquals(denied.status, 403);
  assertEquals((await errorBody(denied)).error?.category, "auth");
  assertEquals(regular.authCalls, 1);
  assertEquals(regular.updateCalls, 0);

  const missing = dependencies();
  const unauthenticated = await handleUpdateCompatibilityWeights(
    new Request("https://example.test/functions/v1/outfits/config/compatibility-weights", {
      method: "POST",
      body: "{}",
    }),
    missing.deps,
  );
  assertEquals(unauthenticated.status, 401);
  assertEquals(missing.authCalls, 0);
  assertEquals(missing.updateCalls, 0);
});

Deno.test("user_metadata cannot grant admin access", async () => {
  const fixture = dependencies({
    user: { id: "regular-user", user_metadata: { astra_admin: true } },
  });
  const response = await handleUpdateCompatibilityWeights(
    request({ expected_version: 1, weights: DEFAULT_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(response.status, 403);
  assertEquals(fixture.updateCalls, 0);
});

Deno.test("anonymous users cannot update config even if app_metadata contains the admin flag", async () => {
  const fixture = dependencies({
    user: { id: "anonymous-user", is_anonymous: true, app_metadata: { astra_admin: true } },
  });
  const response = await handleUpdateCompatibilityWeights(
    request({ expected_version: 1, weights: DEFAULT_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(response.status, 403);
  assertEquals(fixture.updateCalls, 0);
});

Deno.test("admin update validates exact finite weights and sum before service-store write", async () => {
  const invalid = [
    { expected_version: 1, weights: { ...DEFAULT_WEIGHTS, extra: 0 } },
    { expected_version: 1, weights: { ...DEFAULT_WEIGHTS, color: Number.NaN } },
    { expected_version: 1, weights: { ...DEFAULT_WEIGHTS, color: -0.01 } },
    { expected_version: 1, weights: { ...DEFAULT_WEIGHTS, color: 1.01 } },
    { expected_version: 1, weights: { ...DEFAULT_WEIGHTS, color: 0.3 } },
    { expected_version: 0, weights: DEFAULT_WEIGHTS },
  ];
  for (const body of invalid) {
    let threw = false;
    try {
      parseCompatibilityWeightUpdate(body);
    } catch (error) {
      threw = error instanceof AppError && error.status === 400;
    }
    assert(threw, "invalid config should be rejected with a validation error");
  }

  const fixture = dependencies();
  const response = await handleUpdateCompatibilityWeights(
    request({ expected_version: 7, weights: DEFAULT_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(response.status, 200);
  assertEquals(fixture.updateCalls, 1);
  assertEquals(fixture.receivedVersion, 7);
  assertEquals(fixture.receivedWeights, DEFAULT_WEIGHTS);
  const payload = await response.json();
  assertEquals(payload.data.version, 8);
  assertEquals(payload.data.weights, DEFAULT_WEIGHTS);
});

Deno.test("optimistic version conflict returns 409 and no success payload", async () => {
  const fixture = dependencies({ storeUpdate: () => Promise.resolve(null) });
  const response = await handleUpdateCompatibilityWeights(
    request({ expected_version: 2, weights: DEFAULT_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(response.status, 409);
  assertEquals((await errorBody(response)).error?.category, "validation");
  assertEquals(fixture.updateCalls, 1);
});

Deno.test("an unchanged weight update keeps the database-trigger version unchanged", async () => {
  const fixture = dependencies({
    storeUpdate: (_version, weights) => Promise.resolve({ version: 4, weights }),
  });
  const response = await handleUpdateCompatibilityWeights(
    request({ expected_version: 4, weights: DEFAULT_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).data.version, 4);
});

Deno.test("an updated config re-fetch changes the compatibility score", async () => {
  let stored: CompatibilityWeightsConfig = { version: 1, weights: DEFAULT_WEIGHTS };
  const fixture = dependencies({
    storeUpdate: (_version, weights) => {
      stored = { version: 2, weights };
      return Promise.resolve(stored);
    },
  });
  const updateResponse = await handleUpdateCompatibilityWeights(
    request({ expected_version: 1, weights: COLOR_HEAVY_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(updateResponse.status, 200);

  const refetched = await loadCompatibilityWeightsConfig({
    from(table: string) {
      assertEquals(table, "compatibility_weights_config");
      return {
        select(columns: string) {
          assertEquals(columns, "weights, version");
          return {
            eq(column: string, value: boolean) {
              assertEquals(column, "singleton");
              assertEquals(value, true);
              return { maybeSingle: () => Promise.resolve({ data: stored, error: null }) };
            },
          };
        },
      };
    },
  });
  const clashing = [garment("top", "top", "B03030"), garment("bottom", "bottom", "7A9A2E")];
  const before = scoreOutfit(clashing, {}, { weights: DEFAULT_WEIGHTS }).score;
  const after = scoreOutfit(clashing, {}, { weights: refetched.weights }).score;
  assertEquals(refetched.version, 2);
  assert(
    after < before,
    `a higher color weight should lower the clash score: ${after} vs ${before}`,
  );
});

Deno.test("compatibility weights admin limit returns the exact Retry-After reset", async () => {
  const fixture = dependencies({
    rateLimiter: { check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }) },
  });
  const response = await handleUpdateCompatibilityWeights(
    request({ expected_version: 1, weights: DEFAULT_WEIGHTS }),
    fixture.deps,
  );
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
  assertEquals(fixture.updateCalls, 0);
});
