/**
 * Protected-credential helper for the bounded Studio orphan-result cleanup acceptance.
 *
 * Uses one disposable confirmed synthetic Auth account. The service role is
 * used only to create that test identity; uploads and account deletion use
 * the caller JWT. No provider calls are made.
 * Its state file contains synthetic credentials and short-lived tokens and
 * must be stored mode 0600.
 * Keys come from SUPABASE_KEYS_FILE (CLI JSON, mode 0600) or protected key
 * environment variables; this helper never prints them.
 *
 * Commands: prepare|upload|verify|verify-removed|delete <state-file>.
 * Deletion always uses the normal DELETE /account endpoint.
 */
interface State {
  ownerID: string;
  completeGenerationID: string;
  activeGenerationID: string;
  removedGenerationID: string;
  email: string;
  password: string;
  accessToken?: string;
}

async function protectedAPIKey(name: "anon" | "service_role"): Promise<string> {
  const direct = Deno.env.get(name === "anon" ? "SUPABASE_ANON_KEY" : "SUPABASE_SERVICE_ROLE_KEY")
    ?.trim();
  if (direct) return direct;
  const keysPath = Deno.env.get("SUPABASE_KEYS_FILE")?.trim();
  if (!keysPath) throw new Error(`Protected API key unavailable: ${name}.`);
  const keys = JSON.parse(await Deno.readTextFile(keysPath)) as Array<{
    name?: string;
    api_key?: string;
  }>;
  const key = keys.find((entry) => entry.name === name)?.api_key;
  if (!key) throw new Error(`Protected key file does not contain ${name}.`);
  return key;
}

const baseURL = (Deno.env.get("SUPABASE_URL")?.trim() ||
  "https://anutsdzbxycaavmmkewo.supabase.co").replace(/\/$/, "");
if (!baseURL.includes("anutsdzbxycaavmmkewo.supabase.co")) {
  throw new Error("This acceptance helper is restricted to the configured Astra project.");
}

async function readState(path: string): Promise<State> {
  return JSON.parse(await Deno.readTextFile(path)) as State;
}

async function prepare(path: string): Promise<void> {
  const anonKey = await protectedAPIKey("anon");
  const serviceRoleKey = await protectedAPIKey("service_role");
  const email = `orphan-cleanup-${crypto.randomUUID()}@example.invalid`;
  const password = `T-${crypto.randomUUID()}-z9!`;
  const created = await fetch(`${baseURL}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  if (created.status !== 200) {
    await created.body?.cancel();
    throw new Error(`Could not create confirmed synthetic owner (HTTP ${created.status}).`);
  }
  const user = await created.json() as { id?: string };
  if (!user.id) throw new Error("Auth Admin API did not return a synthetic owner ID.");
  const signedIn = await fetch(`${baseURL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!signedIn.ok) {
    await signedIn.body?.cancel();
    await fetch(`${baseURL}/auth/v1/admin/users/${user.id}`, {
      method: "DELETE",
      headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
    }).then((cleanup) => cleanup.body?.cancel());
    throw new Error(`Synthetic owner sign-in failed (HTTP ${signedIn.status}).`);
  }
  const session = await signedIn.json() as { access_token?: string };
  if (!session.access_token) throw new Error("Synthetic owner sign-in returned no caller token.");
  const state: State = {
    ownerID: user.id,
    completeGenerationID: crypto.randomUUID(),
    activeGenerationID: crypto.randomUUID(),
    removedGenerationID: crypto.randomUUID(),
    email,
    password,
    accessToken: session.access_token,
  };
  await Deno.writeTextFile(path, JSON.stringify(state), { createNew: true, mode: 0o600 });
  await Deno.chmod(path, 0o600);
  console.log(JSON.stringify({
    ownerID: state.ownerID,
    completeGenerationID: state.completeGenerationID,
    activeGenerationID: state.activeGenerationID,
    removedGenerationID: state.removedGenerationID,
    confirmedEmailOwner: true,
  }));
}

async function upload(path: string): Promise<void> {
  const state = await readState(path);
  const anonKey = await protectedAPIKey("anon");
  const token = state.accessToken ?? await signIn(baseURL, anonKey, state);
  const paths = [
    state.completeGenerationID,
    state.activeGenerationID,
    state.removedGenerationID,
  ].map((id) => `users/${state.ownerID}/studio/${id}/result.png`);
  const pngBytes = await Deno.readFile(
    new URL(
      "../../../ios/AstraStyle/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
      import.meta.url,
    ),
  );
  for (const storagePath of paths) {
    const uploadResponse = await fetch(
      `${baseURL}/storage/v1/object/user-content/${
        storagePath.split("/").map(encodeURIComponent).join("/")
      }`,
      {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${token}`,
          "Content-Type": "image/png",
          "x-upsert": "false",
        },
        body: pngBytes,
      },
    );
    if (uploadResponse.status !== 200) {
      await uploadResponse.body?.cancel();
      throw new Error(`Synthetic fixture PNG upload failed (HTTP ${uploadResponse.status}).`);
    }
    await uploadResponse.body?.cancel();
  }
  state.accessToken = token;
  await Deno.writeTextFile(path, JSON.stringify(state), { create: true, mode: 0o600 });
  await Deno.chmod(path, 0o600);
  console.log(JSON.stringify({ uploadedPNGCount: paths.length, confirmedEmailOwner: true }));
}

async function removeNormally(path: string): Promise<void> {
  const state = await readState(path);
  const anonKey = await protectedAPIKey("anon");
  if (!state.accessToken) {
    state.accessToken = await signIn(baseURL, anonKey, state);
  }
  const response = await fetch(`${baseURL}/functions/v1/account`, {
    method: "DELETE",
    headers: { apikey: anonKey, authorization: `Bearer ${state.accessToken}` },
    signal: AbortSignal.timeout(30_000),
  });
  const body = await response.json().catch(() => null) as
    | { data?: { deletion_id?: string } }
    | null;
  if ((response.status !== 200 && response.status !== 202) || !body?.data?.deletion_id) {
    throw new Error(`Normal account deletion was not accepted (HTTP ${response.status}).`);
  }
  const deadline = Date.now() + 45_000;
  let deleted = false;
  while (Date.now() < deadline) {
    const response = await fetch(`${baseURL}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: `Bearer ${state.accessToken}` },
      signal: AbortSignal.timeout(10_000),
    });
    // Supabase Auth can report a deleted identity as 401, 403, or 404 depending
    // on the gateway version. This check runs only after DELETE /account was
    // accepted; any of those responses means the caller identity is gone.
    if (response.status === 401 || response.status === 403 || response.status === 404) {
      deleted = true;
      break;
    }
    await response.body?.cancel();
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  if (!deleted) throw new Error("Synthetic Auth identity remains after account deletion.");
  await Deno.remove(path);
  console.log(
    JSON.stringify({
      ownerID: state.ownerID,
      deletionID: body.data.deletion_id,
      authDeleted: true,
    }),
  );
}

async function verifyPNGObjects(path: string): Promise<void> {
  const state = await readState(path);
  const token = state.accessToken;
  if (!token) throw new Error("Synthetic owner state has no caller token.");
  const pngBytes = await Deno.readFile(
    new URL(
      "../../../ios/AstraStyle/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
      import.meta.url,
    ),
  );
  const paths = [
    state.completeGenerationID,
    state.activeGenerationID,
    state.removedGenerationID,
  ].map((id) => `users/${state.ownerID}/studio/${id}/result.png`);
  const anonKey = await protectedAPIKey("anon");
  for (const storagePath of paths) {
    const response = await fetch(
      `${baseURL}/storage/v1/object/authenticated/user-content/${
        storagePath.split("/").map(encodeURIComponent).join("/")
      }`,
      {
        headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
      },
    );
    if (response.status !== 200) {
      await response.body?.cancel();
      throw new Error(`Synthetic fixture image could not be read (HTTP ${response.status}).`);
    }
    const downloaded = new Uint8Array(await response.arrayBuffer());
    if (
      downloaded.length !== pngBytes.length || downloaded.some((byte, i) => byte !== pngBytes[i])
    ) {
      throw new Error("Synthetic fixture image bytes changed during retention processing.");
    }
  }
  console.log(JSON.stringify({ verifiedUnchangedPNGCount: paths.length }));
}

async function verifyRemovedPNG(path: string): Promise<void> {
  const state = await readState(path);
  const token = state.accessToken;
  if (!token) throw new Error("Synthetic owner state has no caller token.");
  const anonKey = await protectedAPIKey("anon");
  const storagePath = `users/${state.ownerID}/studio/${state.removedGenerationID}/result.png`;
  const response = await fetch(
    `${baseURL}/storage/v1/object/authenticated/user-content/${
      storagePath.split("/").map(encodeURIComponent).join("/")
    }`,
    { headers: { apikey: anonKey, Authorization: `Bearer ${token}` } },
  );
  const body = await response.json().catch(() => ({})) as {
    statusCode?: number | string;
    error?: string;
  };
  if (response.ok || String(body.statusCode) !== "404" || body.error !== "not_found") {
    throw new Error("Removed fixture image did not return the Storage not-found response.");
  }
  console.log(JSON.stringify({
    removedPNGHttpStatus: response.status,
    removedPNGStorageStatusCode: String(body.statusCode),
    removedPNGStorageError: body.error,
  }));
}

async function signIn(baseURL: string, anonKey: string, state: State): Promise<string> {
  const response = await fetch(`${baseURL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: state.email, password: state.password }),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error("Could not restore the synthetic owner session.");
  }
  const session = await response.json() as { access_token?: string };
  if (!session.access_token) throw new Error("Synthetic owner session had no access token.");
  return session.access_token;
}

const [command, statePath] = Deno.args;
if (!command || !statePath) throw new Error("Usage: prepare|upload|delete <state-file>");
if (command === "prepare") await prepare(statePath);
else if (command === "upload") await upload(statePath);
else if (command === "verify") await verifyPNGObjects(statePath);
else if (command === "verify-removed") await verifyRemovedPNG(statePath);
else if (command === "delete") await removeNormally(statePath);
else throw new Error("Unknown acceptance command.");
