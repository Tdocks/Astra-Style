import { assertEquals } from "@std/assert";
import {
  handleRetention,
  type RetentionDeps,
  type RetentionJob,
  validResultPath,
} from "./handler.ts";

const SECRET = "a".repeat(64);
const job: RetentionJob = {
  id: "job",
  user_id: "owner",
  generation_id: "generation",
  generation_key: "generation",
  result_image_path: "users/owner/studio/generation/result.png",
};
function fixture(jobs: RetentionJob[] = [job]) {
  const calls: string[] = [];
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
    },
  };
  return { deps, calls };
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
  assertEquals(await res.json(), { prepared: 1, completed: 1, retrying: 0 });
  assertEquals(calls.slice(-2), ["remove:" + job.result_image_path, "finish:job:claim:true"]);
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
    assertEquals(calls.at(-1), "finish:job:claim:false");
  }
});
Deno.test("failed Storage removal leaves a retry and no successful completion", async () => {
  const { deps, calls } = fixture();
  deps.removeImage = () => Promise.reject(new Error("private upstream detail"));
  const res = await handleRetention(request(SECRET), deps);
  assertEquals(await res.json(), { prepared: 1, completed: 0, retrying: 1 });
  assertEquals(calls.at(-1), "finish:job:claim:false");
});
Deno.test("failed estimates without an output can finalize without Storage", async () => {
  const { deps, calls } = fixture([{ ...job, result_image_path: null }]);
  assertEquals((await handleRetention(request(SECRET), deps)).status, 200);
  assertEquals(calls.some((value) => value.startsWith("remove:")), false);
  assertEquals(calls.at(-1), "finish:job:claim:true");
});

Deno.test("an independently deleted generation still has an owned cleanup snapshot", async () => {
  const { deps, calls } = fixture([{ ...job, generation_id: null }]);
  assertEquals((await handleRetention(request(SECRET), deps)).status, 200);
  assertEquals(calls.at(-2), "remove:" + job.result_image_path);
  assertEquals(calls.at(-1), "finish:job:claim:true");
});
