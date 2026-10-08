import { assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { AppError } from "../_shared/errors.ts";
import { buildProductServices } from "./productServices.ts";

const env = { supabaseUrl: "https://project.example.com", supabaseAnonKey: "fixture-anon" };
const client = () =>
  createClient(env.supabaseUrl, env.supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

Deno.test("product calls use fixed deployment routes and the caller's authorization", async () => {
  const services = buildProductServices(env, "Bearer fixture-caller", client(), (input, init) => {
    assertEquals(String(input), "https://project.example.com/functions/v1/products/extract");
    const headers = new Headers(init?.headers);
    assertEquals(headers.get("Authorization"), "Bearer fixture-caller");
    assertEquals(headers.get("apikey"), "fixture-anon");
    const body = JSON.parse(String(init?.body));
    assertEquals(body.body, { url: "https://retailer.example.com/item" });
    assertEquals(typeof body.request_id, "string");
    return Promise.resolve(Response.json({ data: { id: "fixture" }, error: null }));
  });
  assertEquals((await services.extract("https://retailer.example.com/item")).id, "fixture");
});

Deno.test("allowance and authentication failures are typed without leaking upstream bodies", async () => {
  for (const status of [400, 401, 403, 404, 429]) {
    const services = buildProductServices(
      env,
      "Bearer fixture-caller",
      client(),
      () =>
        Promise.resolve(
          Response.json({ data: null, error: { message: "private diagnostic" } }, { status }),
        ),
    );
    const error = await assertRejects(() => services.evaluate("fixture"), AppError);
    assertEquals(error.status, status);
    assertEquals(error.message.includes("private diagnostic"), false);
  }
});

Deno.test("server failures remain retryable infrastructure failures", async () => {
  const services = buildProductServices(
    env,
    "Bearer fixture-caller",
    client(),
    () => Promise.resolve(Response.json({ data: null }, { status: 503 })),
  );
  const error = await assertRejects(() => services.evaluate("fixture"), AppError);
  assertEquals(error.status, 500);
});
