import { assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { AppError } from "../_shared/errors.ts";
import { buildStudioPreviewServices } from "./studioServices.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION } from "../studio/schema.ts";
import type { StudioPreviewSelection } from "./tools/generateStudioPreview.ts";
const userID = "11111111-1111-4111-8111-111111111111";
const messageID = "22222222-2222-4222-8222-222222222222";
const jobID = "33333333-3333-4333-8333-333333333333";
const env = { supabaseUrl: "https://project.example.com", supabaseAnonKey: "fixture-anon" };
const client = () =>
  createClient(env.supabaseUrl, env.supabaseAnonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
const turn = { userID, messageID, userText: "Generate a preview", pending: null };
const selection: StudioPreviewSelection = {
  outfitId: null,
  itemIds: [jobID],
  referenceImageId: jobID,
  pose: "standing",
  background: "studio-neutral",
  resolution: "draft",
};
const reference = {
  path: `users/${userID}/references/${jobID}.jpg`,
  termsVersion: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
};
Deno.test("preview service uses a persisted message key and caller credentials on each retry", async () => {
  let calls = 0;
  const services = buildStudioPreviewServices(
    env,
    "Bearer fixture-user",
    client(),
    turn,
    (input, init) => {
      calls++;
      assertEquals(String(input), env.supabaseUrl + "/functions/v1/studio/generate");
      const headers = new Headers(init?.headers);
      assertEquals(headers.get("Idempotency-Key"), messageID);
      assertEquals(headers.get("Authorization"), "Bearer fixture-user");
      assertEquals(JSON.parse(String(init?.body)).body.reference_image_path, reference.path);
      return Promise.resolve(
        Response.json({ data: { id: jobID, user_id: userID, status: "queued" } }),
      );
    },
  );
  assertEquals((await services.enqueue(selection, reference)).generationId, jobID);
  await services.enqueue(selection, reference);
  assertEquals(calls, 2);
});
Deno.test("preview service rejects another owner's response and preserves quota/conflict outcomes", async () => {
  const wrong = buildStudioPreviewServices(
    env,
    "Bearer fixture-user",
    client(),
    turn,
    () =>
      Promise.resolve(Response.json({ data: { id: jobID, user_id: messageID, status: "queued" } })),
  );
  await assertRejects(() => wrong.enqueue(selection, reference), AppError);
  for (const status of [409, 429]) {
    const services = buildStudioPreviewServices(
      env,
      "Bearer fixture-user",
      client(),
      turn,
      () => Promise.resolve(new Response(null, { status })),
    );
    const error = await assertRejects(() => services.enqueue(selection, reference), AppError);
    assertEquals(error.status, status);
  }
});
