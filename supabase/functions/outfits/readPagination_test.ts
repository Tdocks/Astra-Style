import { assertEquals } from "@std/assert";
import { readAllUserIdBatches, readAllUserPages } from "./readPagination.ts";

Deno.test("readAllUserPages retrieves beyond the PostgREST 1000-row default in stable offsets", async () => {
  const source = Array.from({ length: 2_105 }, (_, index) => index);
  const calls: { userId: string; offset: number; limit: number }[] = [];
  const result = await readAllUserPages("owner-a", (userId, offset, limit) => {
    calls.push({ userId, offset, limit });
    return Promise.resolve({ data: source.slice(offset, offset + limit), error: null });
  });
  assertEquals(result, source);
  assertEquals(calls, [
    { userId: "owner-a", offset: 0, limit: 1000 },
    { userId: "owner-a", offset: 1000, limit: 1000 },
    { userId: "owner-a", offset: 2000, limit: 1000 },
  ]);
});

Deno.test("readAllUserIdBatches bounds URL IDs, paginates each batch, and forwards caller scope", async () => {
  const ids = Array.from({ length: 237 }, (_, index) => `outfit-${index}`);
  const calls: { userId: string; ids: readonly string[]; offset: number; limit: number }[] = [];
  const result = await readAllUserIdBatches(
    "owner-a",
    [...ids, ids[0]!],
    (userId, batch, offset, limit) => {
      calls.push({ userId, ids: batch, offset, limit });
      // This mock models the repository's `.eq(user_id, ownerId)` boundary:
      // rows belonging to another caller are never returned.
      const matching = userId === "owner-a" ? batch.map((id) => ({ ownerId: userId, id })) : [];
      return Promise.resolve({ data: matching.slice(offset, offset + limit), error: null });
    },
    75,
    20,
  );
  assertEquals(result?.length, ids.length);
  assertEquals(result?.every((row) => row.ownerId === "owner-a"), true);
  assertEquals(Math.max(...calls.map((call) => call.ids.length)), 75);
  assertEquals(calls.every((call) => call.userId === "owner-a"), true);
  assertEquals(calls.filter((call) => call.offset === 0).length, 4);
  assertEquals(calls.filter((call) => call.offset > 0).length, 9);
});

Deno.test("paged optional context fails closed instead of using partial history", async () => {
  const result = await readAllUserPages(
    "owner-a",
    (_userId, offset, limit) =>
      Promise.resolve(
        offset === 0
          ? { data: Array.from({ length: limit }, (_, index) => index), error: null }
          : { data: null, error: new Error("page unavailable") },
      ),
  );
  assertEquals(result, null);
});
