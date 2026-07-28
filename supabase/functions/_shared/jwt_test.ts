import { assertEquals, assertRejects } from "@std/assert";
import { AppError } from "./errors.ts";
import { type AuthClient, authenticateRequest } from "./jwt.ts";

const VALID_LOOKING_JWT =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";

function mockAuthClient(
  behavior: (
    jwt: string | undefined,
  ) => Promise<{ data: { user: { id: string } | null }; error: { message: string } | null }>,
): AuthClient {
  return { auth: { getUser: behavior } };
}

Deno.test("authenticateRequest rejects a request with no Authorization header", async () => {
  const req = new Request("https://example.com/outfits/generate", { method: "POST" });
  const authClient = mockAuthClient(() => {
    throw new Error("must not be called for a missing header");
  });
  const err = await assertRejects(() => authenticateRequest(req, authClient), AppError);
  assertEquals(err.category, "auth");
  assertEquals(err.status, 401);
});

Deno.test("authenticateRequest rejects a header that isn't 'Bearer <token>'", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "POST",
    headers: { Authorization: "Basic dXNlcjpwYXNz" },
  });
  const authClient = mockAuthClient(() => {
    throw new Error("must not be called for a non-Bearer header");
  });
  const err = await assertRejects(() => authenticateRequest(req, authClient), AppError);
  assertEquals(err.category, "auth");
});

Deno.test("authenticateRequest rejects a malformed (non-JWT-shaped) token without calling Supabase Auth", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "POST",
    headers: { Authorization: "Bearer not-a-real-jwt" },
  });
  let called = false;
  const authClient = mockAuthClient(() => {
    called = true;
    return Promise.resolve({ data: { user: null }, error: { message: "should not reach here" } });
  });
  const err = await assertRejects(() => authenticateRequest(req, authClient), AppError);
  assertEquals(err.category, "auth");
  assertEquals(
    called,
    false,
    "a structurally malformed token should be rejected before any network call",
  );
});

Deno.test("authenticateRequest rejects a well-formed-looking token Supabase Auth reports invalid", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "POST",
    headers: { Authorization: `Bearer ${VALID_LOOKING_JWT}` },
  });
  const authClient = mockAuthClient(() =>
    Promise.resolve({ data: { user: null }, error: { message: "invalid JWT" } })
  );
  const err = await assertRejects(() => authenticateRequest(req, authClient), AppError);
  assertEquals(err.category, "auth");
});

Deno.test("authenticateRequest returns the user id Supabase Auth resolves the token to", async () => {
  const req = new Request("https://example.com/outfits/generate", {
    method: "POST",
    headers: { Authorization: `Bearer ${VALID_LOOKING_JWT}` },
  });
  let receivedToken: string | undefined;
  const authClient = mockAuthClient((jwt) => {
    receivedToken = jwt;
    return Promise.resolve({ data: { user: { id: "user-abc-123" } }, error: null });
  });
  const userId = await authenticateRequest(req, authClient);
  assertEquals(userId, "user-abc-123");
  assertEquals(receivedToken, VALID_LOOKING_JWT);
});
