import { assertEquals } from "@std/assert";
import {
  handleRetention,
  type OrphanResultCleanupJob,
  type RetentionDeps,
  type RetentionJob,
  validOrphanResultCleanupPath,
  validResultPath,
} from "./handler.ts";

const SECRET = "a".repeat(64);

Deno.test("reference cleanup only accepts its immutable owner/key JPEG path", () => {
  const user = crypto.randomUUID(), key = crypto.randomUUID();
  const reference: RetentionJob = {
    id: crypto.randomUUID(),
    user_id: user,
    generation_id: null,
    generation_key: key,
    kind: "reference",
    result_image_path: `users/${user}/references/${key}.jpg`,
  };
  assertEquals(validResultPath(reference), true);
  for (
    const invalid of [
      { ...reference, generation_id: key },
      { ...reference, result_image_path: `users/${crypto.randomUUID()}/references/${key}.jpg` },
      { ...reference, result_image_path: `users/${user}/references/${crypto.randomUUID()}.jpg` },
      { ...reference, result_image_path: `users/${user}/references/${key}.png` },
      { ...reference, result_image_path: `users/${user}/closet/${key}.jpg` },
      { ...reference, kind: "studio" as const },
    ]
  ) assertEquals(validResultPath(invalid), false);
});
const job: RetentionJob = {
  id: "job",
  user_id: "owner",
  generation_id: "generation",
  generation_key: "generation",
  result_image_path: "users/owner/studio/generation/result.png",
};
function fixture(jobs: RetentionJob[] = [job]) {
  const calls: string[] = [];
  const ownerID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const generationID = "12121212-1212-4121-8121-121212121212";
  const orphanJob: OrphanResultCleanupJob = {
    id: "orphan-job",
    owner_user_id: ownerID,
    generation_id: generationID,
    storage_path: `users/${ownerID}/studio/${generationID}/result.png`,
  };
  const deps: RetentionDeps = {
    token: () => "claim",
    removeImage(path) {
      calls.push("remove:" + path);
      return Promise.resolve();
    },
    repository: {
      authorize(secret) {
        calls.push("auth");
        return Promise.resolve(secret === SECRET);
      },
      prepare() {
        calls.push("prepare");
        return Promise.resolve(jobs.length);
      },
      claim(token) {
        calls.push("claim:" + token);
        return Promise.resolve(jobs);
      },
      finish(id, token, success) {
        calls.push(`finish:${id}:${token}:${success}`);
        return Promise.resolve(true);
      },
      claimOrphanResults(token) {
        calls.push(`claim-orphans:${token}`);
        return Promise.resolve([]);
      },
      orphanResultDisposition(userID, generationID) {
        calls.push(`orphan-disposition:${userID}:${generationID}`);
        return Promise.resolve("remove");
      },
      finishOrphanResult(id, token, success) {
        calls.push(`finish-orphan:${id}:${token}:${success}`);
        return Promise.resolve(true);
      },
    },
  };
  return { deps, calls, orphanJob };
}
function request(secret?: string, method = "POST") {
  return new Request("https://example.test/studio-retention", {
    method,
    headers: secret ? { "x-astra-retention-secret": secret } : {},
  });
}

Deno.test("scheduler rejects missing, malformed and incorrect secrets before job work", async () => {
  for (const secret of [undefined, "bad", "b".repeat(64)]) {
    const { deps, calls } = fixture();
    assertEquals((await handleRetention(request(secret), deps)).status, 401);
    assertEquals(calls.includes("prepare"), false);
  }
});
Deno.test("GET cannot initiate deletion", async () => {
  const { deps, calls } = fixture();
  assertEquals((await handleRetention(request(SECRET, "GET"), deps)).status, 405);
  assertEquals(calls.length, 0);
});
Deno.test("Storage API removal precedes fenced row finalization", async () => {
  const { deps, calls } = fixture();
  const res = await handleRetention(request(SECRET), deps);
  assertEquals(await res.json(), {
    prepared: 1,
    completed: 1,
    retrying: 0,
    orphanCompleted: 0,
    orphanRetrying: 0,
  });
  const removeIndex = calls.indexOf("remove:" + job.result_image_path);
  const finishIndex = calls.indexOf("finish:job:claim:true");
  assertEquals(removeIndex >= 0 && finishIndex > removeIndex, true);
});

Deno.test("short-window abandoned reference uses the same Storage-before-finalization fence", async () => {
  const ownerID = crypto.randomUUID();
  const key = crypto.randomUUID();
  const path = `users/${ownerID}/references/${key}.jpg`;
  const reference: RetentionJob = {
    id: crypto.randomUUID(),
    user_id: ownerID,
    generation_id: null,
    generation_key: key,
    result_image_path: path,
    kind: "reference",
  };
  const { deps, calls } = fixture([reference]);
  const response = await handleRetention(request(SECRET), deps);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    prepared: 1,
    completed: 1,
    retrying: 0,
    orphanCompleted: 0,
    orphanRetrying: 0,
  });
  const removal = calls.indexOf(`remove:${path}`);
  const finish = calls.indexOf(`finish:${reference.id}:claim:true`);
  assertEquals(removal >= 0 && finish > removal, true);
});
Deno.test("cross-owner and malformed paths never reach Storage", async () => {
  for (
    const path of [
      "users/peer/studio/generation/result.png",
      "users/owner/studio/other/result.png",
      "../result.png",
      "users/owner/studio/generation/source.png",
    ]
  ) {
    const { deps, calls } = fixture([{ ...job, result_image_path: path }]);
    assertEquals(validResultPath({ ...job, result_image_path: path }), false);
    assertEquals((await handleRetention(request(SECRET), deps)).status, 200);
    assertEquals(calls.some((value) => value.startsWith("remove:")), false);
    assertEquals(calls.includes("finish:job:claim:false"), true);
  }
});
Deno.test("failed Storage removal leaves a retry and no successful completion", async () => {
  const { deps, calls } = fixture();
  deps.removeImage = () => Promise.reject(new Error("private upstream detail"));
  const res = await handleRetention(request(SECRET), deps);
  assertEquals(await res.json(), {
    prepared: 1,
    completed: 0,
    retrying: 1,
    orphanCompleted: 0,
    orphanRetrying: 0,
  });
  assertEquals(calls.includes("finish:job:claim:false"), true);
});
Deno.test("failed estimates without an output can finalize without Storage", async () => {
  const { deps, calls } = fixture([{ ...job, result_image_path: null }]);
  assertEquals((await handleRetention(request(SECRET), deps)).status, 200);
  assertEquals(calls.some((value) => value.startsWith("remove:")), false);
  assertEquals(calls.includes("finish:job:claim:true"), true);
});

Deno.test("an independently deleted generation still has an owned cleanup snapshot", async () => {
  const { deps, calls } = fixture([{ ...job, generation_id: null }]);
  assertEquals((await handleRetention(request(SECRET), deps)).status, 200);
  const removeIndex = calls.indexOf("remove:" + job.result_image_path);
  const finishIndex = calls.indexOf("finish:job:claim:true");
  assertEquals(removeIndex >= 0 && finishIndex > removeIndex, true);
});

Deno.test("orphan result cleanup retries until Auth deletion or job loss makes removal safe", async () => {
  const { deps, calls, orphanJob } = fixture([]);
  assertEquals(validOrphanResultCleanupPath(orphanJob), true);
  deps.repository.claimOrphanResults = (token) => {
    calls.push(`claim-orphans:${token}`);
    return Promise.resolve([orphanJob]);
  };
  deps.repository.orphanResultDisposition = () => Promise.resolve("defer");
  const response = await handleRetention(request(SECRET), deps);
  assertEquals(await response.json(), {
    prepared: 0,
    completed: 0,
    retrying: 0,
    orphanCompleted: 0,
    orphanRetrying: 1,
  });
  assertEquals(calls.includes(`remove:${orphanJob.storage_path}`), false);
  assertEquals(calls.at(-1), `finish-orphan:${orphanJob.id}:claim:false`);
});

Deno.test("orphan cleanup validates owner path and removes only with service-verified proof", async () => {
  const { deps, calls, orphanJob } = fixture([]);
  const malformed = { ...orphanJob, storage_path: `users/${crypto.randomUUID()}/result.png` };
  assertEquals(validOrphanResultCleanupPath(malformed), false);
  deps.repository.claimOrphanResults = () => Promise.resolve([orphanJob]);
  const response = await handleRetention(request(SECRET), deps);
  assertEquals(await response.json(), {
    prepared: 0,
    completed: 0,
    retrying: 0,
    orphanCompleted: 1,
    orphanRetrying: 0,
  });
  assertEquals(
    calls.includes(`orphan-disposition:${orphanJob.owner_user_id}:${orphanJob.generation_id}`),
    true,
  );
  assertEquals(calls.includes(`remove:${orphanJob.storage_path}`), true);
  assertEquals(calls.at(-1), `finish-orphan:${orphanJob.id}:claim:true`);
});

Deno.test("stale cleanup intent preserves the image of a live completed generation", async () => {
  const { deps, calls, orphanJob } = fixture([]);
  deps.repository.claimOrphanResults = () => Promise.resolve([orphanJob]);
  deps.repository.orphanResultDisposition = () => Promise.resolve("preserve");

  const response = await handleRetention(request(SECRET), deps);
  assertEquals(await response.json(), {
    prepared: 0,
    completed: 0,
    retrying: 0,
    orphanCompleted: 1,
    orphanRetrying: 0,
  });
  assertEquals(calls.includes(`remove:${orphanJob.storage_path}`), false);
  assertEquals(calls.at(-1), `finish-orphan:${orphanJob.id}:claim:true`);
});
