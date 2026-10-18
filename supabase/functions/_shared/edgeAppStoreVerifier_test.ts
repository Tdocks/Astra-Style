import { Buffer } from "node:buffer";
import { assertEquals, assertRejects } from "@std/assert";
import { Environment, VerificationException } from "@apple/app-store-server-library";
import { EdgeAppStoreVerifier } from "./edgeAppStoreVerifier.ts";

const root = Buffer.from(
  await Deno.readFile(new URL("./fixtures/AppleRootCA-G3.cer", import.meta.url)),
);
// Genuine public Apple TEST event, with no transaction or customer data.
const { signedPayload } = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/apple-sandbox-test-notification.json", import.meta.url),
  ),
) as { signedPayload: string };
const verifier = (bundle = "com.astrastyle.app", roots = [root]) =>
  new EdgeAppStoreVerifier(roots, false, Environment.SANDBOX, bundle);

Deno.test("Edge verifier accepts Apple's genuine signed TEST on the hosted Deno runtime", async () => {
  const result = await verifier().verifyAndDecodeNotification(signedPayload);
  assertEquals(result.notificationType, "TEST");
  assertEquals(result.data?.environment, "Sandbox");
});

Deno.test("Edge verifier rejects a modified signature", async () => {
  const parts = signedPayload.split(".");
  const signature = Buffer.from(parts[2] ?? "", "base64url");
  signature[0] = (signature[0] ?? 0) ^ 1;
  parts[2] = signature.toString("base64url");
  await assertRejects(
    () => verifier().verifyAndDecodeNotification(parts.join(".")),
    VerificationException,
  );
});

Deno.test("Edge verifier rejects a modified signed environment", async () => {
  const parts = signedPayload.split(".");
  const payload = JSON.parse(Buffer.from(parts[1] ?? "", "base64url").toString());
  payload.data.environment = "Production";
  parts[1] = Buffer.from(JSON.stringify(payload)).toString("base64url");
  await assertRejects(
    () => verifier().verifyAndDecodeNotification(parts.join(".")),
    VerificationException,
  );
});

Deno.test("Edge verifier rejects a genuine event for a different app", async () => {
  await assertRejects(
    () => verifier("com.other.app").verifyAndDecodeNotification(signedPayload),
    VerificationException,
  );
});

Deno.test("Edge verifier rejects an untrusted certificate chain", async () => {
  const header = JSON.parse(Buffer.from(signedPayload.split(".")[0] ?? "", "base64url").toString());
  await assertRejects(
    () =>
      verifier("com.astrastyle.app", [Buffer.from(header.x5c[0], "base64")])
        .verifyAndDecodeNotification(signedPayload),
    VerificationException,
  );
});

for (
  const [name, token] of [
    ["empty token", ""],
    ["missing signature", signedPayload.split(".").slice(0, 2).join(".")],
    ["extra segment", `${signedPayload}.extra`],
  ] as const
) {
  Deno.test(`Edge verifier rejects ${name}`, async () => {
    await assertRejects(() => verifier().verifyAndDecodeNotification(token), VerificationException);
  });
}

for (
  const [name, update] of [
    ["unsigned algorithm", { alg: "none" }],
    ["missing certificate chain", { x5c: [] }],
    ["non-string certificate", { x5c: [null, null, null] }],
  ] as const
) {
  Deno.test(`Edge verifier rejects ${name}`, async () => {
    const parts = signedPayload.split(".");
    const header = JSON.parse(Buffer.from(parts[0] ?? "", "base64url").toString());
    parts[0] = Buffer.from(JSON.stringify({ ...header, ...update })).toString("base64url");
    await assertRejects(
      () => verifier().verifyAndDecodeNotification(parts.join(".")),
      VerificationException,
    );
  });
}

Deno.test("Edge verifier rejects a genuine Sandbox event in Production", async () => {
  const production = new EdgeAppStoreVerifier(
    [root],
    false,
    Environment.PRODUCTION,
    "com.astrastyle.app",
    6797115649,
  );
  await assertRejects(
    () => production.verifyAndDecodeNotification(signedPayload),
    VerificationException,
  );
});
