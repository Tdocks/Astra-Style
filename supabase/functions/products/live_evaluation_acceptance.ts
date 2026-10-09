import { assert, assertEquals } from "@std/assert";

/**
 * Opt-in hosted acceptance for P6-TEST-02. It creates an anonymous synthetic
 * owner, seeds a small caller-owned closet, evaluates an existing catalog
 * candidate, checks the duplicate verdict, then requests normal account
 * deletion. It never calls product extraction or an image/provider API.
 *
 * Run explicitly with RUN_PRODUCTS_LIVE_ACCEPTANCE=1 plus SUPABASE_URL,
 * SUPABASE_ANON_KEY, and PRODUCT_DUPLICATE_CANDIDATE_ID. The selected
 * candidate must describe a brown shearling/leather jacket like the fixture.
 */
async function runHostedAcceptance(): Promise<void> {
  assertEquals(Deno.env.get("RUN_PRODUCTS_LIVE_ACCEPTANCE"), "1", "set the explicit opt-in flag");
  const baseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const candidateID = Deno.env.get("PRODUCT_DUPLICATE_CANDIDATE_ID");
  assert(baseURL, "SUPABASE_URL is required");
  assert(anonKey, "SUPABASE_ANON_KEY is required");
  assert(candidateID, "PRODUCT_DUPLICATE_CANDIDATE_ID is required");

  const headers = (token?: string) => ({
    apikey: anonKey,
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    "Content-Type": "application/json",
  });
  const signup = await fetch(`${baseURL}/auth/v1/signup`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({}),
  });
  assertEquals(signup.status, 200, "synthetic anonymous signup should succeed");
  const auth = await signup.json() as { user?: { id?: string }; access_token?: string };
  assert(auth.user?.id, "signup response must include the synthetic user ID");
  assert(auth.access_token, "signup response must include the caller token");
  const userID = auth.user.id;
  const token = auth.access_token;

  let verdict: string | undefined;
  let redundancyScore: number | undefined;
  try {
    const closet = [
      {
        user_id: userID,
        name: "P6 synthetic duplicate jacket",
        category: "outerwear",
        primary_color: "brown",
        secondary_colors: [],
        pattern: "solid",
        material: [
          { fiber: "shearling", percentage: 50 },
          { fiber: "leather", percentage: 50 },
        ],
        fit: "regular",
        seasonality: ["fall", "winter"],
        formality_score: 55,
      },
      {
        user_id: userID,
        name: "P6 synthetic olive chinos",
        category: "bottom",
        primary_color: "olive",
        secondary_colors: [],
        pattern: "solid",
        material: [{ fiber: "cotton", percentage: 100 }],
        fit: "regular",
        seasonality: ["fall", "winter"],
        formality_score: 45,
      },
      {
        user_id: userID,
        name: "P6 synthetic brown boots",
        category: "shoes",
        primary_color: "brown",
        secondary_colors: [],
        pattern: "solid",
        material: [{ fiber: "leather", percentage: 100 }],
        fit: "regular",
        seasonality: ["fall", "winter"],
        formality_score: 50,
      },
    ];
    const seed = await fetch(`${baseURL}/rest/v1/closet_items`, {
      method: "POST",
      headers: { ...headers(token), Prefer: "return=minimal" },
      body: JSON.stringify(closet),
    });
    assertEquals(seed.status, 201, "caller should be able to seed its synthetic closet");

    const evaluate = await fetch(`${baseURL}/functions/v1/products/evaluate`, {
      method: "POST",
      headers: headers(token),
      body: JSON.stringify({
        request_id: crypto.randomUUID(),
        client_version: "p6-test-02-hosted-acceptance",
        body: { product_candidate_id: candidateID },
      }),
    });
    assertEquals(evaluate.status, 200, "evaluation endpoint should return a verdict");
    const envelope = await evaluate.json() as {
      data?: {
        compatibility_score?: number;
        redundancy_score?: number;
        verdict?: string;
        reasoning?: string;
        product_candidate_id?: string;
      };
    };
    const result = envelope.data;
    assert(result, "evaluation response must include data");
    assertEquals(result.product_candidate_id, candidateID);
    assertEquals(typeof result.compatibility_score, "number");
    assert(result.compatibility_score! >= 0 && result.compatibility_score! <= 100);
    assertEquals(typeof result.redundancy_score, "number");
    assert(result.redundancy_score! >= 85, "duplicate redundancy must be high");
    assert(result.verdict !== "buy", "a near-duplicate must not receive a buy verdict");
    assert(result.reasoning?.toLowerCase().includes("close"));
    verdict = result.verdict;
    redundancyScore = result.redundancy_score;
  } finally {
    const deletion = await fetch(`${baseURL}/functions/v1/account`, {
      method: "DELETE",
      headers: headers(token),
    });
    assertEquals(deletion.status, 202, "synthetic account should use normal deletion flow");
    const deletionEnvelope = await deletion.json() as {
      data?: { deletion_id?: string; status?: string };
    };
    assert(deletionEnvelope.data?.deletion_id, "deletion response must include an ID");
    console.log(JSON.stringify({
      owner_id: userID,
      product_candidate_id: candidateID,
      verdict,
      redundancy_score: redundancyScore,
      deletion_id: deletionEnvelope.data.deletion_id,
      deletion_status: deletionEnvelope.data.status,
    }));
  }
}

await runHostedAcceptance();
