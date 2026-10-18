import { AppStoreServerAPIClient, Environment } from "@apple/app-store-server-library";

const required = (name: string): string => {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Set ${name} before requesting Apple's test notification.`);
  return value;
};

const privateKeyPath = required("APP_STORE_SERVER_PRIVATE_KEY_PATH");
const privateKey = await Deno.readTextFile(privateKeyPath);
// TestFlight purchases use Sandbox. Production API access requires a released app.
const environmentName = Deno.env.get("APP_STORE_SERVER_ENVIRONMENT")?.trim().toLowerCase() ??
  "sandbox";
if (environmentName !== "sandbox" && environmentName !== "production") {
  throw new Error("APP_STORE_SERVER_ENVIRONMENT must be sandbox or production.");
}
const client = new AppStoreServerAPIClient(
  privateKey,
  required("APP_STORE_SERVER_KEY_ID"),
  required("APP_STORE_CONNECT_ISSUER_ID"),
  required("APP_STORE_BUNDLE_ID"),
  environmentName === "production" ? Environment.PRODUCTION : Environment.SANDBOX,
);

try {
  const { testNotificationToken } = await client.requestTestNotification();
  if (!testNotificationToken) {
    throw new Error("Apple accepted the request but returned no status token.");
  }

  console.log(`Apple accepted the ${environmentName} TEST notification request.`);
  for (let attempt = 0; attempt < 12; attempt += 1) {
    try {
      const status = await client.getTestNotificationStatus(testNotificationToken);
      const results = (status.sendAttempts ?? []).map((item) =>
        item.sendAttemptResult ?? "unknown"
      );
      if (results.length) console.log(`Webhook delivery result(s): ${results.join(", ")}`);
      if (results.includes("SUCCESS")) Deno.exit(0);
      if (results.some((result) => result !== "PENDING" && result !== "unknown")) Deno.exit(1);
    } catch (error) {
      if (attempt === 11) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, 5_000));
  }
  console.log(
    "Apple has not reported a final delivery result yet; check the notification status again.",
  );
  Deno.exit(2);
} catch (error) {
  const details = typeof error === "object" && error !== null && "httpStatusCode" in error
    ? `HTTP ${String((error as { httpStatusCode: unknown }).httpStatusCode)}`
    : error instanceof Error
    ? error.message
    : "unknown error";
  console.error(
    `App Store Server API test failed (${details}). No notification status was confirmed.`,
  );
  Deno.exit(1);
}
