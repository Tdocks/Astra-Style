import { assert, assertEquals } from "@std/assert";

/**
 * Opt-in hosted P6-CORE-01 peer-look acceptance. Uses two disposable confirmed
 * accounts and the repository's non-person AppIcon PNG. No provider calls,
 * real-user writes, public notifications, or product-catalog changes occur.
 * The confirmed synthetic accounts are created through the Auth Admin API
 * (anonymous accounts cannot upload to user-content) and are always sent
 * through normal DELETE /account cleanup.
 *
 * Run with RUN_LOOKBOOK_PUBLIC_ACCEPTANCE=1 and SUPABASE_URL,
 * SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY supplied by a protected
 * environment. The service key is used only to create test identities; all
 * feature writes use the resulting caller JWT, and cleanup uses DELETE /account.
 */
interface AuthState {
  readonly id: string;
  readonly token: string;
  deletionID?: string;
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const baseURL = requiredEnvironment("SUPABASE_URL").replace(/\/$/, "");
const anonKey = requiredEnvironment("SUPABASE_ANON_KEY");
assertEquals(Deno.env.get("RUN_LOOKBOOK_PUBLIC_ACCEPTANCE"), "1");

function headers(token?: string): HeadersInit {
  return {
    apikey: anonKey,
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    "Content-Type": "application/json",
  };
}

async function createAccount(): Promise<AuthState> {
  const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  const email = `p6-core01-${crypto.randomUUID()}@example.invalid`;
  const password = `${crypto.randomUUID()}-Aa9!`;
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
    const error = await created.json().catch(() => ({})) as {
      error?: string;
      message?: string;
      msg?: string;
    };
    const safeDetail = (error.message ?? error.msg ?? error.error ?? "auth-rejected-create")
      .replaceAll(email, "[synthetic-email]")
      .replaceAll(password, "[synthetic-password]");
    throw new Error(
      `disposable confirmed synthetic account creation failed (HTTP ${created.status}, ${safeDetail})`,
    );
  }
  const user = await created.json() as { id?: string };
  const id = user.id;
  if (!id) throw new Error("Auth Admin API did not return the synthetic user ID");

  const response = await fetch(`${baseURL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) {
    await response.body?.cancel();
    await fetch(`${baseURL}/auth/v1/admin/users/${id}`, {
      method: "DELETE",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
      },
    }).then((cleanup) => cleanup.body?.cancel());
    throw new Error(`synthetic account password login failed (HTTP ${response.status})`);
  }
  const session = await response.json() as { access_token?: string };
  if (!session.access_token) throw new Error("Auth login did not return a caller session");
  return { id, token: session.access_token };
}

async function jsonRequest<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${baseURL}${path}`, {
    ...init,
    headers: { ...headers(token) as Record<string, string>, ...init.headers },
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`Acceptance request failed at ${path} (HTTP ${response.status}).`);
  }
  return await response.json() as T;
}

async function insertOne<T>(table: string, token: string, row: unknown): Promise<T> {
  const result = await jsonRequest<T[]>(
    `/rest/v1/${table}?select=id`,
    token,
    {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify(row),
    },
  );
  assertEquals(result.length, 1, `${table} fixture should be created`);
  return result[0]!;
}

async function deleteAccount(account: AuthState): Promise<void> {
  const response = await fetch(`${baseURL}/functions/v1/account`, {
    method: "DELETE",
    headers: headers(account.token),
  });
  if (response.status !== 202 && response.status !== 200) {
    await response.body?.cancel();
    throw new Error(`Normal synthetic-account cleanup failed (HTTP ${response.status}).`);
  }
  const envelope = await response.json() as { data?: { deletion_id?: string; status?: string } };
  const deletionID = envelope.data?.deletion_id;
  if (!deletionID) throw new Error("deletion must return its receipt ID");
  account.deletionID = deletionID;
}

function assertKeys(value: Record<string, unknown>, expected: string[]): void {
  assertEquals(Object.keys(value).sort(), [...expected].sort());
}

async function rpc<T>(token: string, name: string, outfitID: string): Promise<T[]> {
  return await jsonRequest<T[]>(`/rest/v1/rpc/${name}`, token, {
    method: "POST",
    body: JSON.stringify({ p_outfit_ids: [outfitID] }),
  });
}

async function readRawRows(
  token: string,
  table: string,
  field: string,
  id: string,
): Promise<unknown[]> {
  const query = new URLSearchParams({ select: "*", [field]: `eq.${id}` });
  return await jsonRequest<unknown[]>(`/rest/v1/${table}?${query}`, token);
}

async function signImages(
  token: string,
  images: unknown[],
): Promise<Array<{ image_id: string; signed_url: string }>> {
  const response = await fetch(`${baseURL}/functions/v1/lookbook/sign-images`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify({ request_id: crypto.randomUUID(), body: { images } }),
  });
  assertEquals(response.status, 200, "authenticated signing call should succeed");
  const envelope = await response.json() as {
    data?: { images?: Array<{ image_id: string; signed_url: string }> };
  };
  return envelope.data?.images ?? [];
}

async function run(): Promise<void> {
  let owner: AuthState | undefined;
  let viewer: AuthState | undefined;
  let outcome: Record<string, unknown> = {};
  let failure: unknown;
  try {
    const ownerAccount = await createAccount();
    owner = ownerAccount;
    const viewerAccount = await createAccount();
    viewer = viewerAccount;

    const itemID = crypto.randomUUID();
    const imageID = crypto.randomUUID();
    const sourceOutfitID = crypto.randomUUID();
    const privateWornOutfitID = crypto.randomUUID();
    const unwornOutfitID = crypto.randomUUID();
    const item = await insertOne<{ id: string }>("closet_items", ownerAccount.token, {
      id: itemID,
      user_id: ownerAccount.id,
      name: "Synthetic acceptance jacket",
      category: "outerwear",
      primary_color: "charcoal",
      size: "synthetic-private-size-marker",
      purchase_date: "2026-01-01",
      price_paid: 1,
      formality_score: 50,
    });

    const png = await Deno.readFile(
      new URL(
        "../../../ios/AstraStyle/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        import.meta.url,
      ),
    );
    const objectPath = `users/${ownerAccount.id}/closet/${item.id}/${imageID}.png`;
    const upload = await fetch(
      `${baseURL}/storage/v1/object/user-content/${
        objectPath.split("/").map(encodeURIComponent).join("/")
      }`,
      {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${ownerAccount.token}`,
          "Content-Type": "image/png",
          "x-upsert": "false",
        },
        body: png,
      },
    );
    if (upload.status !== 200) {
      const error = await upload.json().catch(() => ({})) as {
        error?: string;
        message?: string;
        statusCode?: string;
      };
      const safeDetail = (error.message ?? error.error ?? "storage-rejected-upload")
        .replaceAll(objectPath, "[synthetic-path]")
        .replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/gi, "[synthetic-id]");
      throw new Error(`synthetic PNG upload rejected (HTTP ${upload.status}, ${safeDetail})`);
    }
    await upload.body?.cancel();

    const image = await insertOne<{ id: string }>("closet_item_images", ownerAccount.token, {
      id: imageID,
      closet_item_id: item.id,
      image_type: "front",
      storage_path: objectPath,
      is_primary: true,
      analysis_metadata: { private_marker: "must-not-cross-peer-boundary" },
    });

    for (
      const [id, name] of [
        [sourceOutfitID, "Synthetic public worn look"],
        [privateWornOutfitID, "Synthetic private worn look"],
        [unwornOutfitID, "Synthetic unworn look"],
      ]
    ) {
      const outfit = await jsonRequest<Array<{ id: string }>>(
        "/rest/v1/outfits?select=id",
        ownerAccount.token,
        {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({
            id,
            user_id: owner.id,
            name,
            visibility: "private",
            source: "user_created",
          }),
        },
      );
      assertEquals(outfit.length, 1);
      await insertOne("outfit_items", ownerAccount.token, {
        outfit_id: id,
        closet_item_id: item.id,
        role: "outerwear",
        sort_order: 0,
      });
    }

    for (const outfitID of [sourceOutfitID, privateWornOutfitID]) {
      await insertOne("outfit_wears", ownerAccount.token, {
        outfit_id: outfitID,
        user_id: ownerAccount.id,
        rating: 4,
        feedback: "synthetic-private-feedback-marker",
      });
    }
    const publish = await fetch(`${baseURL}/rest/v1/outfits?id=eq.${sourceOutfitID}`, {
      method: "PATCH",
      headers: {
        ...headers(ownerAccount.token) as Record<string, string>,
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ visibility: "public" }),
    });
    assertEquals(publish.status, 204, "a previously worn outfit can be explicitly made public");
    await publish.body?.cancel();

    const cannotPublishUnworn = await fetch(`${baseURL}/rest/v1/outfits?id=eq.${unwornOutfitID}`, {
      method: "PATCH",
      headers: {
        ...headers(ownerAccount.token) as Record<string, string>,
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ visibility: "public" }),
    });
    assert(!cannotPublishUnworn.ok, "an unworn outfit must not become public");
    await cannotPublishUnworn.body?.cancel();

    const summaries = await rpc<Record<string, unknown>>(
      viewerAccount.token,
      "fetch_public_worn_looks",
      sourceOutfitID,
    );
    assertEquals(summaries.length, 1);
    assertEquals(summaries[0]!.id, sourceOutfitID);
    assertKeys(summaries[0]!, [
      "id",
      "name",
      "description",
      "occasion_tags",
      "weather_min_celsius",
      "weather_max_celsius",
      "formality_score",
      "compatibility_score",
    ]);
    assert(!JSON.stringify(summaries).includes("private"));

    const garments = await rpc<Record<string, unknown>>(
      viewerAccount.token,
      "fetch_public_look_garments",
      sourceOutfitID,
    );
    assertEquals(garments.length, 1);
    assertEquals(garments[0]!.closet_item_id, item.id);
    assertEquals(garments[0]!.display_image_id, image.id);
    assertKeys(garments[0]!, [
      "outfit_id",
      "closet_item_id",
      "name",
      "brand",
      "category",
      "role",
      "formality_score",
      "sort_order",
      "display_image_id",
    ]);
    assert(!JSON.stringify(garments).includes("synthetic-private-size-marker"));
    assert(!JSON.stringify(garments).includes("must-not-cross-peer-boundary"));

    const rawTables = [
      ["outfits", "id", sourceOutfitID],
      ["outfit_items", "outfit_id", sourceOutfitID],
      ["outfit_wears", "outfit_id", sourceOutfitID],
      ["closet_items", "id", item.id],
      ["closet_item_images", "id", image.id],
    ] as const;
    for (const [table, field, id] of rawTables) {
      assertEquals(
        await readRawRows(viewerAccount.token, table, field, id),
        [],
        `peer raw ${table} rows stay closed`,
      );
    }

    const unauthorized = await fetch(`${baseURL}/functions/v1/lookbook/sign-images`, {
      method: "POST",
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        request_id: crypto.randomUUID(),
        body: {
          images: [{
            outfit_id: sourceOutfitID,
            closet_item_id: item.id,
            image_id: image.id,
          }],
        },
      }),
    });
    assertEquals(unauthorized.status, 401, "image signing must require an authenticated viewer");
    await unauthorized.body?.cancel();

    const valid = await signImages(viewerAccount.token, [{
      outfit_id: sourceOutfitID,
      closet_item_id: item.id,
      image_id: image.id,
    }]);
    assertEquals(valid.length, 1, "exact public worn tuple should receive an image capability");
    const signedURL = new URL(valid[0]!.signed_url);
    assertEquals(signedURL.hostname, new URL(baseURL).hostname);
    const imageResponse = await fetch(signedURL);
    assertEquals(imageResponse.status, 200, "signed private synthetic image should download");
    assertEquals(imageResponse.headers.get("content-type"), "image/png");
    const downloaded = new Uint8Array(await imageResponse.arrayBuffer());
    assertEquals([...downloaded.slice(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);

    const denied = await signImages(viewerAccount.token, [
      { outfit_id: privateWornOutfitID, closet_item_id: item.id, image_id: image.id },
      { outfit_id: unwornOutfitID, closet_item_id: item.id, image_id: image.id },
      { outfit_id: sourceOutfitID, closet_item_id: crypto.randomUUID(), image_id: image.id },
      { outfit_id: sourceOutfitID, closet_item_id: item.id, image_id: crypto.randomUUID() },
    ]);
    assertEquals(denied, [], "private, unworn, or forged tuples must not get signed URLs");

    outcome = {
      owner_id: ownerAccount.id,
      viewer_id: viewerAccount.id,
      public_outfit_id: sourceOutfitID,
      private_worn_outfit_id: privateWornOutfitID,
      unworn_outfit_id: unwornOutfitID,
      closet_item_id: item.id,
      image_id: image.id,
      summary_rpc_fields_exact: true,
      garment_rpc_fields_exact: true,
      peer_raw_tables_empty: rawTables.map(([table]) => table),
      unauthenticated_sign_images_401: true,
      valid_private_object_downloaded: downloaded.length,
      private_unworn_forged_tuples_denied: true,
    };
  } catch (error) {
    failure = error;
  } finally {
    for (const account of [viewer, owner]) {
      if (account && !account.deletionID) {
        try {
          await deleteAccount(account);
        } catch (error) {
          failure ??= error;
        }
      }
    }
    console.log(JSON.stringify({
      ...outcome,
      owner_id: owner?.id,
      viewer_id: viewer?.id,
      owner_deletion_id: owner?.deletionID,
      viewer_deletion_id: viewer?.deletionID,
    }));
  }
  if (failure) {
    throw new Error(
      `Hosted public-look acceptance failed: ${
        failure instanceof Error ? failure.message : "unknown failure"
      }`,
    );
  }
}

await run();
