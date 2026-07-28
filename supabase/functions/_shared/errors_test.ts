import { assertEquals } from "@std/assert";
import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  rateLimited,
  unauthorized,
} from "./errors.ts";

Deno.test("badRequest produces a validation category with status 400", () => {
  const err = badRequest("bad field");
  assertEquals(err.category, "validation");
  assertEquals(err.status, 400);
  assertEquals(err.message, "bad field");
});

Deno.test("unauthorized produces an auth category with status 401", () => {
  const err = unauthorized();
  assertEquals(err.category, "auth");
  assertEquals(err.status, 401);
});

Deno.test("rateLimited produces a rate_limited category with status 429", () => {
  const err = rateLimited();
  assertEquals(err.category, "rate_limited");
  assertEquals(err.status, 429);
});

Deno.test("jsonResponse wraps data in the shared envelope shape", async () => {
  const response = jsonResponse({ hello: "world" }, { requestId: "req-1" });
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body, { data: { hello: "world" }, error: null, request_id: "req-1" });
});

Deno.test("errorResponse wraps an AppError in the shared envelope shape", async () => {
  const err = new AppError("validation", 422, "nope");
  const response = errorResponse(err, "req-2");
  assertEquals(response.status, 422);
  const body = await response.json();
  assertEquals(body, {
    data: null,
    error: { category: "validation", message: "nope" },
    request_id: "req-2",
  });
});
