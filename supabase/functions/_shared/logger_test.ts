import { assertEquals } from "@std/assert";
import { createLogger } from "./logger.ts";

/** Captures every line written to console.log/console.error during `fn`. */
async function captureConsole(
  fn: () => void | Promise<void>,
): Promise<{ logLines: string[]; errorLines: string[] }> {
  const logLines: string[] = [];
  const errorLines: string[] = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (line: unknown) => {
    logLines.push(String(line));
  };
  console.error = (line: unknown) => {
    errorLines.push(String(line));
  };
  try {
    await fn();
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
  return { logLines, errorLines };
}

Deno.test("info() writes a single JSON line tagged with the request id", async () => {
  const { logLines } = await captureConsole(() => {
    createLogger("req-123").info("something_happened", { count: 3 });
  });
  assertEquals(logLines.length, 1);
  const parsed = JSON.parse(logLines[0]!);
  assertEquals(parsed.level, "info");
  assertEquals(parsed.event, "something_happened");
  assertEquals(parsed.request_id, "req-123");
  assertEquals(parsed.count, 3);
});

Deno.test("error() writes to console.error, not console.log", async () => {
  const { logLines, errorLines } = await captureConsole(() => {
    createLogger("req-456").error("it_broke", {});
  });
  assertEquals(logLines.length, 0);
  assertEquals(errorLines.length, 1);
});

Deno.test("redacts denylisted fields instead of logging their contents", async () => {
  const { logLines } = await captureConsole(() => {
    createLogger("req-789").info("outfits_generate.debug", {
      natural_language_request: "a private, specific request the user typed",
      image_url: "https://storage.example.com/users/123/closet/secret.jpg",
      desired_count: 3,
    });
  });
  const parsed = JSON.parse(logLines[0]!);
  assertEquals(parsed.natural_language_request, "[redacted]");
  assertEquals(parsed.image_url, "[redacted]");
  assertEquals(parsed.desired_count, 3);
});

Deno.test("does not leak an Authorization/JWT-shaped field if ever passed by mistake", async () => {
  const { logLines } = await captureConsole(() => {
    createLogger("req-000").warn("oops", {
      authorization: "Bearer some.jwt.value",
      jwt: "some.jwt.value",
    });
  });
  const parsed = JSON.parse(logLines[0]!);
  assertEquals(parsed.authorization, "[redacted]");
  assertEquals(parsed.jwt, "[redacted]");
});
