import { assertEquals } from "@std/assert";
import { handleReferenceDelete } from "./referenceDeletion.ts";
import type { StudioDeletionDeps } from "../studio/deletion.ts";
import { AppError } from "../_shared/errors.ts";

function fixture() {
  const user = crypto.randomUUID(), key = crypto.randomUUID(), id = crypto.randomUUID();
  const path = `users/${user}/references/${key}.jpg`;
  const calls: string[] = [];
  const job = {
    id,
    user_id: user,
    generation_id: null,
    generation_key: key,
    kind: "reference" as const,
    result_image_path: path,
    status: "pending" as const,
  };
  const deps: StudioDeletionDeps = {
    authClient: {
      auth: { getUser: () => Promise.resolve({ data: { user: { id: user } }, error: null }) },
    },
    prepare: (owner, source) => {
      assertEquals([owner, source], [user, path]);
      calls.push("prepare");
      return Promise.resolve(job);
    },
    claim: () => {
      calls.push("claim");
      return Promise.resolve({ ...job, status: "processing" });
    },
    finish: (_id, _token, succeeded) => {
      calls.push(`finish:${succeeded}`);
      return Promise.resolve(true);
    },
    removeImage: (source) => {
      assertEquals(source, path);
      calls.push("remove");
      return Promise.resolve();
    },
    token: () => crypto.randomUUID(),
  };
  const req = (
    body: unknown = { path },
    authorization: string | null = "Bearer a.b.c",
    method = "DELETE",
  ) =>
    new Request("https://example.test/profile/reference-photos", {
      method,
      headers: authorization ? { authorization } : {},
      ...(method === "DELETE"
        ? { body: typeof body === "string" ? body : JSON.stringify(body) }
        : {}),
    });
  return { user, key, id, path, job, deps, calls, req };
}

Deno.test("reference erasure authenticates before parsing or invoking privileged work", async () => {
  const f = fixture();
  assertEquals((await handleReferenceDelete(f.req({ path: f.path }, null), f.deps)).status, 401);
  assertEquals(f.calls, []);
});
Deno.test("reference erasure accepts only an owned reference JPEG and bounded JSON", async () => {
  for (
    const invalid of [null, [], {}, "{broken", { path: "../photo.jpg" }, {
      path: `users/${crypto.randomUUID()}/references/${crypto.randomUUID()}.jpg`,
    }, { path: "x".repeat(3000) }]
  ) {
    const f = fixture();
    assertEquals((await handleReferenceDelete(f.req(invalid), f.deps)).status, 400);
    assertEquals(f.calls, []);
  }
});
Deno.test("accepted reference removal uses Storage API before fenced finish and reveals only safe status", async () => {
  const f = fixture();
  const response = await handleReferenceDelete(f.req(), f.deps);
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data, { id: f.id, status: "complete" });
  assertEquals(body.error, null);
  assertEquals(f.calls, ["prepare", "claim", "remove", "finish:true"]);
});
Deno.test("reference Storage failure is accepted as durable pending removal", async () => {
  const f = fixture();
  f.deps.removeImage = () => Promise.reject(new Error("private upstream detail"));
  const response = await handleReferenceDelete(f.req(), f.deps);
  assertEquals(response.status, 202);
  assertEquals((await response.json()).data, { id: f.id, status: "pending" });
  assertEquals(f.calls, ["prepare", "claim", "finish:false"]);
});
Deno.test("active descendant refusal preserves a visible retryable 409", async () => {
  const f = fixture();
  f.deps.prepare = () =>
    Promise.reject(new AppError("validation", 409, "A preview is in progress."));
  assertEquals((await handleReferenceDelete(f.req(), f.deps)).status, 409);
  assertEquals(f.calls, []);
});
Deno.test("reference claims cannot delete a peer path", async () => {
  const f = fixture();
  f.deps.claim = () =>
    Promise.resolve({ ...f.job, status: "processing", user_id: crypto.randomUUID() });
  assertEquals((await handleReferenceDelete(f.req(), f.deps)).status, 202);
  assertEquals(f.calls, ["prepare", "finish:false"]);
});
Deno.test("completed duplicate reference request performs no additional Storage deletion", async () => {
  const f = fixture();
  f.deps.prepare = () => Promise.resolve({ ...f.job, status: "complete", result_image_path: null });
  const response = await handleReferenceDelete(f.req(), f.deps);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).data, { id: f.id, status: "complete" });
  assertEquals(f.calls, []);
});
Deno.test("reference preflight and wrong method cannot initiate erasure", async () => {
  const f = fixture();
  assertEquals(
    (await handleReferenceDelete(f.req(undefined, null, "OPTIONS"), f.deps)).status,
    204,
  );
  assertEquals((await handleReferenceDelete(f.req(undefined, null, "POST"), f.deps)).status, 405);
  assertEquals(f.calls, []);
});

Deno.test("reference deletion limit returns exact Retry-After on the first rejected request", async () => {
  const f = fixture();
  let response: Response | null = null;
  for (let request = 0; request < 31; request++) {
    response = await handleReferenceDelete(f.req(), f.deps);
  }
  assertEquals(response?.status, 429);
  assertEquals(response?.headers.get("Retry-After"), "60");
});
