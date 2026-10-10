import { assertEquals, assertThrows } from "@std/assert";
import { resolveLocalStylistProviderEndpoint } from "./localProviderEndpoint.ts";

Deno.test("local provider endpoint is absent by default", () => {
  assertEquals(
    resolveLocalStylistProviderEndpoint("https://example.supabase.co", undefined),
    undefined,
  );
});

Deno.test("local provider endpoint accepts only local Supabase and Responses URLs", () => {
  assertEquals(
    resolveLocalStylistProviderEndpoint(
      "http://kong:8000",
      "http://host.docker.internal:18765/v1/responses",
    ),
    "http://host.docker.internal:18765/v1/responses",
  );
  assertThrows(
    () =>
      resolveLocalStylistProviderEndpoint(
        "https://example.supabase.co",
        "http://host.docker.internal:18765/v1/responses",
      ),
    Error,
    "hosted Supabase",
  );
  assertThrows(
    () =>
      resolveLocalStylistProviderEndpoint(
        "http://kong:8000",
        "https://api.openai.com/v1/responses",
      ),
    Error,
    "local Responses endpoint",
  );
  assertThrows(
    () =>
      resolveLocalStylistProviderEndpoint(
        "http://kong:8000",
        "http://example.com/v1/responses",
      ),
    Error,
    "local Responses endpoint",
  );
});
