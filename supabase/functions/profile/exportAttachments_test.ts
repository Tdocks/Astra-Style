import { assertEquals } from "@std/assert";
import { extractExportedStorageReferences } from "./exportAttachments.ts";

const OWNER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";

Deno.test("extracts deterministic unique owner paths for supported photo rows", () => {
  const tables = {
    profiles: [{
      id: OWNER,
      avatar_storage_path: `users/${OWNER}/avatars/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
    }],
    closet_item_images: [{
      user_id: OWNER,
      storage_path: `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`,
      background_removed_path:
        `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb-cutout.png`,
      thumbnail_storage_path:
        `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.thumb.jpg`,
      background_removed_thumbnail_path:
        `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb-cutout.thumb.png`,
    }],
    studio_generations: [{
      user_id: OWNER,
      reference_image_path: `users/${OWNER}/references/cccccccc-cccc-4ccc-8ccc-cccccccccccc.jpg`,
      result_image_path: `users/${OWNER}/studio/dddddddd-dddd-4ddd-8ddd-dddddddddddd/result.png`,
    }],
  };

  const result = extractExportedStorageReferences(tables, OWNER);
  assertEquals(
    result,
    [...result].sort((a, b) => a.path.localeCompare(b.path)),
  );
  assertEquals(result.length, 7);
  assertEquals(new Set(result.map((item) => item.path)).size, 7);
  assertEquals(result.every((item) => item.bucket === "user-content"), true);
});

Deno.test("includes legacy nested closet paths and deduplicates references", () => {
  const path =
    `users/${OWNER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`;
  const result = extractExportedStorageReferences({
    closet_item_images: [
      { user_id: OWNER, storage_path: path },
      { user_id: OWNER, storage_path: path },
    ],
  }, OWNER);

  assertEquals(result, [{ bucket: "user-content", path }]);
});

Deno.test("exports only canonical owner-scoped thumbnail sibling paths", () => {
  const source = `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`;
  const thumb = `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.thumb.jpg`;
  const result = extractExportedStorageReferences({
    closet_item_images: [{
      user_id: OWNER,
      storage_path: source,
      thumbnail_storage_path: thumb,
      background_removed_thumbnail_path:
        `users/${OTHER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb-cutout.thumb.png`,
    }],
  }, OWNER);

  assertEquals(result.map((item) => item.path), [source, thumb]);
});

Deno.test("includes on-device cutouts stored under their own UUID PNG path", () => {
  const path = `users/${OWNER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.png`;
  const result = extractExportedStorageReferences({
    closet_item_images: [{
      user_id: OWNER,
      storage_path: `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`,
      background_removed_path: path,
    }],
  }, OWNER);

  assertEquals(result.map((item) => item.path), [
    `users/${OWNER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.png`,
    `users/${OWNER}/closet/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg`,
  ]);
});

Deno.test("rejects foreign rows, malformed paths, URLs, traversal, and another profile", () => {
  const result = extractExportedStorageReferences({
    profiles: [
      {
        id: OTHER,
        avatar_storage_path: `users/${OWNER}/avatars/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
      },
    ],
    closet_item_images: [
      {
        user_id: OTHER,
        storage_path: `users/${OWNER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
      },
      {
        user_id: OWNER,
        storage_path:
          `https://example.test/users/${OWNER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
      },
      { user_id: OWNER, storage_path: `users/${OWNER}/closet/../secret.jpg` },
      {
        user_id: OWNER,
        storage_path: `users/${OTHER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
      },
    ],
    studio_generations: [
      {
        user_id: OWNER,
        reference_image_path: `users/${OWNER}/references/foreign.png`,
        result_image_path: null,
      },
      {
        user_id: OTHER,
        reference_image_path: `users/${OWNER}/references/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
        result_image_path: null,
      },
    ],
  }, OWNER);

  assertEquals(result, []);
});

Deno.test("does not infer references from rows without verified ownership columns", () => {
  const result = extractExportedStorageReferences({
    profiles: [{
      avatar_storage_path: `users/${OWNER}/avatars/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
    }],
    closet_item_images: [{
      storage_path: `users/${OWNER}/closet/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
    }],
    studio_generations: [{
      reference_image_path: `users/${OWNER}/references/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg`,
    }],
  }, OWNER);

  assertEquals(result, []);
});
