import { assertEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { handleSignPublicLookImages, type SignPublicLookImagesDependencies } from "./handler.ts";

const OUTFIT = "11111111-1111-4111-8111-111111111111";
const PRIVATE_OUTFIT = "22222222-2222-4222-8222-222222222222";
const ITEM = "33333333-3333-4333-8333-333333333333";
const IMAGE = "44444444-4444-4444-8444-444444444444";
const PRIVATE_IMAGE = "55555555-5555-4555-8555-555555555555";

function dependencies(overrides: Partial<SignPublicLookImagesDependencies> = {}) {
  const calls = { paths: [] as string[], lifetime: 0, fetchedImageIDs: [] as string[] };
  const authClient: AuthClient = {
    auth: {
      getUser: () => Promise.resolve({ data: { user: { id: "user-a" } }, error: null }),
    },
  };
  const rateLimiter: RateLimiter = {
    check: () => ({ allowed: true, remaining: 59, retryAfterSeconds: 0 }),
  };
  const deps: SignPublicLookImagesDependencies = {
    authClient,
    rateLimiter,
    now: () => 1_000,
    fetchPublicGarments(_authorizationHeader, outfitIDs) {
      assertEquals(outfitIDs, [OUTFIT, PRIVATE_OUTFIT]);
      return Promise.resolve([{
        outfit_id: OUTFIT,
        closet_item_id: ITEM,
        display_image_id: IMAGE,
      }]);
    },
    fetchImages(imageIDs) {
      calls.fetchedImageIDs = imageIDs;
      return Promise.resolve([{
        id: IMAGE,
        storage_path: "users/user-b/closet/item/original.jpg",
        background_removed_path: "users/user-b/closet/item/cutout.png",
      }]);
    },
    signStoragePaths(paths, expiresInSeconds) {
      calls.paths = paths;
      calls.lifetime = expiresInSeconds;
      return Promise.resolve(paths.map((path) => ({
        path,
        signed_url: `https://storage.example/${path}?token=short`,
      })));
    },
    ...overrides,
  };
  return { deps, calls };
}

function request(images: unknown, authorization = "Bearer header.payload.signature") {
  return new Request("https://example.test/functions/v1/lookbook/sign-images", {
    method: "POST",
    headers: { authorization, "content-type": "application/json" },
    body: JSON.stringify({ request_id: "test-request", body: { images } }),
  });
}

Deno.test("signs only a selected image id returned by the caller-scoped public-look RPC", async () => {
  const { deps, calls } = dependencies();
  const response = await handleSignPublicLookImages(
    request([
      { outfit_id: OUTFIT, closet_item_id: ITEM, image_id: IMAGE },
      { outfit_id: PRIVATE_OUTFIT, closet_item_id: ITEM, image_id: PRIVATE_IMAGE },
    ]),
    deps,
  );

  assertEquals(response.status, 200);
  assertEquals(calls.fetchedImageIDs, [IMAGE]);
  assertEquals(calls.paths, ["users/user-b/closet/item/cutout.png"]);
  assertEquals(calls.lifetime, 600);
  assertEquals(await response.json(), {
    data: {
      images: [{
        image_id: IMAGE,
        signed_url: "https://storage.example/users/user-b/closet/item/cutout.png?token=short",
      }],
    },
    error: null,
    request_id: "test-request",
  });
});

Deno.test("public look image signing returns the exact Retry-After reset", async () => {
  const { deps } = dependencies({
    rateLimiter: { check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }) },
  });
  const response = await handleSignPublicLookImages(request([]), deps);
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
});

Deno.test("returns no URLs when no requested image belongs to a public worn look", async () => {
  const { deps, calls } = dependencies({
    fetchPublicGarments: () => Promise.resolve([]),
  });
  const response = await handleSignPublicLookImages(
    request([
      { outfit_id: PRIVATE_OUTFIT, closet_item_id: ITEM, image_id: PRIVATE_IMAGE },
    ]),
    deps,
  );

  assertEquals(response.status, 200);
  assertEquals(calls.fetchedImageIDs, []);
  assertEquals(calls.paths, []);
  assertEquals((await response.json()).data.images, []);
});

Deno.test("requires a verified session before querying public garments or Storage", async () => {
  const { deps, calls } = dependencies({
    authClient: {
      auth: {
        getUser: () => Promise.resolve({ data: { user: null }, error: { message: "bad token" } }),
      },
    },
  });
  const response = await handleSignPublicLookImages(
    request([
      { outfit_id: OUTFIT, closet_item_id: ITEM, image_id: IMAGE },
    ]),
    deps,
  );

  assertEquals(response.status, 401);
  assertEquals(calls.fetchedImageIDs, []);
  assertEquals(calls.paths, []);
});
