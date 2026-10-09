import { assertEquals, assertNotEquals } from "@std/assert";
import { requestFingerprint } from "./requestFingerprint.ts";

Deno.test("request fingerprints ignore object key order but preserve values and array order", async () => {
  const left = await requestFingerprint({
    body: { a: 1, b: ["first", "second"] },
    id: "request",
  });
  const reordered = await requestFingerprint({
    id: "request",
    body: { b: ["first", "second"], a: 1 },
  });
  const changed = await requestFingerprint({
    id: "request",
    body: { b: ["second", "first"], a: 1 },
  });
  assertEquals(left, reordered);
  assertNotEquals(left, changed);
  assertEquals(left.length, 64);
});
