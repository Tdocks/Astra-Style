import { createClient } from "@supabase/supabase-js";
import { handleRetention, type RetentionJob } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !key) throw new Error("Retention requires the injected Supabase server configuration.");
const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

// JWT verification is disabled only for this scheduler endpoint. It checks a
// dedicated random Vault secret via a service-only RPC before any job work.
Deno.serve((req) =>
  handleRetention(req, {
    token: () => crypto.randomUUID(),
    async removeImage(path) {
      const { error } = await client.storage.from("user-content").remove([path]);
      if (error) throw new Error("Storage removal failed");
    },
    repository: {
      async authorize(secret) {
        const { data, error } = await client.rpc("authorize_studio_retention", { p_token: secret });
        if (error) throw new Error("Scheduler authorization unavailable");
        return data === true;
      },
      async prepare() {
        const { data, error } = await client.rpc("prepare_studio_retention", { p_limit: 25 });
        if (error) throw new Error("Cleanup preparation failed");
        const references = await client.rpc("prepare_reference_retention", { p_limit: 25 });
        if (references.error) throw new Error("Reference cleanup preparation failed");
        return (data as number) + (references.data as number);
      },
      async claim(token) {
        const { data, error } = await client.rpc("claim_studio_retention", {
          p_token: token,
          p_limit: 25,
        });
        if (error) throw new Error("Cleanup claims unavailable");
        return data as RetentionJob[];
      },
      async finish(jobID, token, succeeded) {
        const { data, error } = await client.rpc("finish_studio_retention", {
          p_job_id: jobID,
          p_token: token,
          p_succeeded: succeeded,
        });
        if (error) throw new Error("Cleanup completion failed");
        return data === true;
      },
    },
  })
);
