import { assert, assertEquals } from "@std/assert";
import { handleDelete, type StudioDeletionDeps } from "./deletion.ts";
import { AppError, notFound } from "../_shared/errors.ts";

function fixture() {
  const user = crypto.randomUUID(), generation = crypto.randomUUID(), jobID = crypto.randomUUID();
  const events: string[] = [];
  const job = {
    id: jobID,
    user_id: user,
    generation_id: generation,
    generation_key: generation,
    result_image_path: `users/${user}/studio/${generation}/result.png`,
    status: "pending" as const,
  };
  const deps: StudioDeletionDeps = {
    authClient: {
      auth: { getUser: () => Promise.resolve({ data: { user: { id: user } }, error: null }) },
    },
    prepare: (uid, id) => {
      assertEquals([uid, id], [user, generation]);
      events.push("prepare");
      return Promise.resolve(job);
    },
    claim: () => {
      events.push("claim");
      return Promise.resolve({ ...job, status: "processing" });
    },
    finish: (_id, _token, succeeded) => {
      events.push(`finish:${succeeded}`);
      return Promise.resolve(true);
    },
    removeImage: () => {
      events.push("remove");
      return Promise.resolve();
    },
    token: () => crypto.randomUUID(),
  };
  const req = (method = "DELETE", authorization: string | null = "Bearer a.b.c") =>
    new Request("https://example.com/studio/generations/" + generation, {
      method,
      headers: authorization ? { authorization } : {},
    });
  return { deps, events, req, generation, user, job };
}

Deno.test("Studio deletion authenticates before preparing and verifies method/id", async () => {
  const f = fixture();
  assertEquals((await handleDelete(f.req("GET"), f.deps, f.generation)).status, 405);
  assertEquals((await handleDelete(f.req(), f.deps, "bad")).status, 400);
  assertEquals((await handleDelete(f.req("DELETE", null), f.deps, f.generation)).status, 401);
  assertEquals(f.events, []);
});
Deno.test("Studio deletion removes Storage before fenced row completion and returns safe metadata", async () => {
  const f = fixture();
  const response = await handleDelete(f.req(), f.deps, f.generation);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).data, { id: f.job.id, status: "complete" });
  assertEquals(f.events, ["prepare", "claim", "remove", "finish:true"]);
});
Deno.test("Studio deletion retries Storage failures without leaking upstream details", async () => {
  const f = fixture();
  f.deps.removeImage = () => Promise.reject(new Error("private-provider-path-and-token"));
  const response = await handleDelete(f.req(), f.deps, f.generation);
  assertEquals(response.status, 202);
  assert(!JSON.stringify(await response.json()).includes("private-provider"));
  assertEquals(f.events, ["prepare", "claim", "finish:false"]);
});
Deno.test("Studio deletion rejects a malformed or cross-owner privileged path", async () => {
  const f = fixture();
  f.deps.claim = () =>
    Promise.resolve({
      ...f.job,
      status: "processing",
      result_image_path: `users/${crypto.randomUUID()}/studio/${f.generation}/result.png`,
    });
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 202);
  assertEquals(f.events, ["prepare", "finish:false"]);
});
Deno.test("Studio deletion remains idempotent after completion and honors an active lease", async () => {
  const f = fixture();
  f.deps.prepare = () => Promise.resolve({ ...f.job, status: "complete" });
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 200);
  assertEquals(f.events, []);
  f.deps.prepare = () => Promise.resolve(f.job);
  f.deps.claim = () => Promise.resolve(null);
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 202);
  assertEquals(f.events, []);
});
Deno.test("Studio deletion keeps an accepted request pending when claims or retry writes fail", async () => {
  const f = fixture();
  f.deps.claim = () => Promise.reject(new Error("db unavailable"));
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 202);
  f.deps.claim = () => Promise.resolve({ ...f.job, status: "processing" });
  f.deps.removeImage = () => Promise.reject(new Error("Storage unavailable"));
  f.deps.finish = () => Promise.reject(new Error("db unavailable"));
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 202);
});
Deno.test("Studio deletion preserves unavailable and dependency conflicts without a Storage call", async () => {
  const f = fixture();
  f.deps.prepare = () => Promise.reject(notFound());
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 404);
  f.deps.prepare = () =>
    Promise.reject(new AppError("validation", 409, "Remove variations first."));
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 409);
  assertEquals(f.events, []);
});
Deno.test("Studio deletion completes a failed job that never stored output", async () => {
  const f = fixture();
  f.deps.claim = () => Promise.resolve({ ...f.job, status: "processing", result_image_path: null });
  assertEquals((await handleDelete(f.req(), f.deps, f.generation)).status, 200);
  assertEquals(f.events, ["prepare", "finish:true"]);
});
