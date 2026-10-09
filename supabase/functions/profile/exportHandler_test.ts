import { assertEquals, assertStringIncludes } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import {
  type ExportHandlerDeps,
  handlePersonalDataExport,
  type PersonalDataExportRepository,
} from "./exportHandler.ts";

const USER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const TOKEN = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.c2lnbmF0dXJl";

function authClient(): AuthClient {
  return {
    auth: {
      getUser(jwt?: string) {
        return Promise.resolve(
          jwt === TOKEN
            ? { data: { user: { id: USER_ID } }, error: null }
            : { data: { user: null }, error: { message: "invalid token" } },
        );
      },
    },
  };
}

function request(method = "GET", token?: string): Request {
  const headers = new Headers();
  if (token) headers.set("Authorization", "Bearer " + token);
  return new Request("https://example.com/profile/export-data", { method, headers });
}

function deps(repository: PersonalDataExportRepository, limit = 20): ExportHandlerDeps {
  return {
    authClient: authClient(),
    repository,
    rateLimiter: createRateLimiter({ limit, windowMs: 60_000 }),
    now: () => new Date("2026-09-29T14:00:00.000Z"),
  };
}

Deno.test("requires a verified caller before reading any data", async () => {
  let reads = 0;
  const repository: PersonalDataExportRepository = {
    fetchForUser() {
      reads += 1;
      return Promise.resolve({ profiles: [] });
    },
  };
  const response = await handlePersonalDataExport(request(), deps(repository));
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.status, 401);
  assertEquals(reads, 0);
});

Deno.test("exports only the identity verified from the bearer token", async () => {
  const received: string[] = [];
  const repository: PersonalDataExportRepository = {
    fetchForUser(userId) {
      received.push(userId);
      return Promise.resolve({ profiles: [{ id: userId }], closet_items: [] });
    },
  };
  const response = await handlePersonalDataExport(request("GET", TOKEN), deps(repository));
  const payload = await response.json();

  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.status, 200);
  assertEquals(received, [USER_ID]);
  assertEquals(payload.data.owner_user_id, USER_ID);
  assertEquals(payload.data.table_counts.profiles, 1);
  assertEquals(payload.data.tables.profiles[0].id, USER_ID);
});

Deno.test("emits only validated owner photo references with an honest scope", async () => {
  const ownCutout = `users/${USER_ID}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.png`;
  const ownSource = `users/${USER_ID}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`;
  const peerSource =
    `users/22222222-2222-4222-8222-222222222222/closet/cccccccc-cccc-4ccc-8ccc-cccccccccccc.jpg`;
  const repository: PersonalDataExportRepository = {
    fetchForUser(userId) {
      return Promise.resolve({
        closet_item_images: [
          { user_id: userId, storage_path: ownSource, background_removed_path: ownCutout },
          { user_id: "22222222-2222-4222-8222-222222222222", storage_path: peerSource },
        ],
      });
    },
  };

  const response = await handlePersonalDataExport(request("GET", TOKEN), deps(repository));
  const payload = await response.json();

  assertEquals(response.status, 200);
  assertEquals(payload.data.referenced_storage_objects, [
    { bucket: "user-content", path: ownCutout },
    { bucket: "user-content", path: ownSource },
  ]);
  assertEquals(
    payload.data.storage_manifest_scope.includes("does not enumerate all Storage objects"),
    true,
  );
  assertEquals(
    payload.data.storage_manifest_scope.includes(
      "does not verify whether referenced objects exist",
    ),
    true,
  );
  assertEquals(payload.data.storage_manifest_scope.includes("does not include image files"), true);
});

Deno.test("rejects non-GET calls", async () => {
  const response = await handlePersonalDataExport(
    request("POST", TOKEN),
    deps({ fetchForUser: () => Promise.resolve({}) }),
  );
  assertEquals(response.status, 405);
});

Deno.test("rate limits repeated exports for the same verified user", async () => {
  const repository = { fetchForUser: () => Promise.resolve({ profiles: [] }) };
  const limited = deps(repository, 1);
  const first = await handlePersonalDataExport(request("GET", TOKEN), limited);
  const second = await handlePersonalDataExport(request("GET", TOKEN), limited);

  assertEquals(first.status, 200);
  assertEquals(second.headers.get("Cache-Control"), "no-store");
  assertEquals(second.status, 429);
  assertStringIncludes(second.headers.get("Retry-After") ?? "", "60");
});

Deno.test("does not reveal database errors in the response", async () => {
  const repository = {
    fetchForUser: () => Promise.reject(new Error("secret_column and private row data")),
  };
  const response = await handlePersonalDataExport(request("GET", TOKEN), deps(repository));
  const body = await response.text();

  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(response.status, 500);
  assertStringIncludes(body, "Couldn't prepare your data export.");
  assertEquals(body.includes("secret_column"), false);
});
