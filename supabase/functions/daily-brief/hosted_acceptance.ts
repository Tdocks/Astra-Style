/**
 * Bounded hosted acceptance for P4-TEST-03.
 *
 * This contacts only a project explicitly enabled for disposable acceptance.
 * It creates two anonymous accounts, inserts temporary garment metadata (no
 * photos), calls the deployed daily-brief/generate function as the owner,
 * verifies owned outfit-item joins plus weather/calendar DTOs and same-day
 * idempotency, then requests normal account deletion for both accounts.
 *
 * Daily Brief uses the production deterministic compatibility scorer; there
 * is no StylistReasoningProvider or server-side weather provider on this path.
 * Weather is the request's synthetic device snapshot, not a paid/live lookup.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const RUN_GATE = "ASTRA_ALLOW_DISPOSABLE_DAILY_BRIEF_ACCEPTANCE";
const RUN_GATE_VALUE = "YES";
const CLIENT_VERSION = "P4-TEST-03-hosted-acceptance";

interface DailyBriefDTO {
  readonly id: string;
  readonly user_id: string;
  readonly brief_date: string;
  readonly primary_outfit_id: string | null;
  readonly alternative_outfit_ids: readonly string[];
  readonly weather_snapshot: Record<string, unknown> | null;
  readonly schedule_snapshot: Record<string, unknown> | null;
}

interface Envelope<T> {
  readonly data?: T | null;
  readonly error?: { readonly category?: string } | null;
}

interface DeletionReceipt {
  readonly deletion_id: string;
  readonly status: "pending" | "processing";
}

interface SyntheticAccount {
  readonly client: SupabaseClient;
  readonly userId: string;
  readonly accessToken: string;
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error("Required acceptance environment value is missing: " + name);
  return value;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function createSyntheticAccount(baseURL: string, anonKey: string): Promise<SyntheticAccount> {
  const client = createClient(baseURL, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await client.auth.signInAnonymously();
  if (error || !data.user || !data.session) {
    throw new Error("Could not create a temporary anonymous test account.");
  }
  return { client, userId: data.user.id, accessToken: data.session.access_token };
}

async function seedCloset(account: SyntheticAccount, prefix: string): Promise<Set<string>> {
  const garments = [
    { category: "top", primary_color: "navy", formality_score: 60 },
    { category: "top", primary_color: "white", formality_score: 40 },
    { category: "bottom", primary_color: "charcoal", formality_score: 60 },
    { category: "bottom", primary_color: "khaki", formality_score: 40 },
    { category: "shoes", primary_color: "black", formality_score: 60 },
    { category: "shoes", primary_color: "brown", formality_score: 40 },
  ].map((garment, index) => ({
    user_id: account.userId,
    name: prefix + " fixture " + (index + 1),
    category: garment.category,
    primary_color: garment.primary_color,
    secondary_colors: [],
    pattern: "solid",
    material: [{ fiber: "cotton", percentage: 100 }],
    fit: "regular",
    seasonality: ["fall", "winter"],
    formality_score: garment.formality_score,
    warmth_score: 75,
    water_resistance_score: 60,
    laundry_state: "clean",
    availability_state: "available",
  }));

  const { data, error } = await account.client
    .from("closet_items")
    .insert(garments)
    .select("id");
  if (error || !data || data.length !== garments.length) {
    throw new Error("Could not seed the complete temporary wardrobe.");
  }
  return new Set((data as { id: string }[]).map((row) => row.id));
}

async function seedClosetImageMetadata(
  account: SyntheticAccount,
  closetItemIDs: ReadonlySet<string>,
): Promise<readonly string[]> {
  const closetItemID = closetItemIDs.values().next().value;
  assert(closetItemID, "The synthetic wardrobe did not return an owned closet item.");
  const sourceID = crypto.randomUUID();
  const cutoutID = crypto.randomUUID();
  const sourcePath = `users/${account.userId}/closet/${sourceID}.jpg`;
  const cutoutPath = `users/${account.userId}/closet/${cutoutID}-cutout.png`;
  const sourceThumbnailPath = sourcePath.replace(".jpg", ".thumb.jpg");
  const cutoutThumbnailPath = cutoutPath.replace(".png", ".thumb.png");
  const { error } = await account.client.from("closet_item_images").insert({
    closet_item_id: closetItemID,
    image_type: "front",
    storage_path: sourcePath,
    background_removed_path: cutoutPath,
    thumbnail_storage_path: sourceThumbnailPath,
    background_removed_thumbnail_path: cutoutThumbnailPath,
    is_primary: true,
  });
  if (error) throw new Error("Could not seed owner-scoped closet image metadata.");
  return [sourcePath, cutoutPath, sourceThumbnailPath, cutoutThumbnailPath];
}

async function generate(
  account: SyntheticAccount,
  briefDate: string,
  regenerate: boolean,
): Promise<DailyBriefDTO> {
  const { data, error } = await account.client.functions.invoke("daily-brief/generate", {
    body: {
      request_id: crypto.randomUUID(),
      client_version: CLIENT_VERSION,
      body: {
        date: briefDate,
        regenerate,
        weather_snapshot: {
          temperature_high: 40,
          temperature_low: 35,
          apparent_temperature: 32,
          condition: "rain",
          precipitation_chance: 0.8,
          season: "winter",
        },
        schedule_snapshot: { event_count: 1, earliest_formality_level: "formal" },
      },
    },
  });
  if (error) throw new Error("The deployed Daily Brief request failed.");
  const envelope = data as Envelope<DailyBriefDTO> | null;
  if (!envelope?.data || envelope.error) {
    throw new Error("The deployed Daily Brief returned an unsuccessful response envelope.");
  }
  return envelope.data;
}

async function countOwnedOutfits(account: SyntheticAccount): Promise<number> {
  const { count, error } = await account.client
    .from("outfits")
    .select("id", { count: "exact", head: true });
  if (error || count === null) throw new Error("Could not verify the temporary outfit count.");
  return count;
}

async function verifyOwnedReferences(
  account: SyntheticAccount,
  brief: DailyBriefDTO,
  closetIDs: ReadonlySet<string>,
): Promise<void> {
  assert(brief.user_id === account.userId, "Brief owner did not match the authenticated account.");
  assert(brief.primary_outfit_id, "A six-item test wardrobe did not produce a primary outfit.");
  assert(
    brief.alternative_outfit_ids.length >= 1,
    "A six-item test wardrobe did not produce at least one alternative.",
  );

  const outfitIDs = [brief.primary_outfit_id, ...brief.alternative_outfit_ids];
  const { data, error } = await account.client
    .from("outfit_items")
    .select("outfit_id,closet_item_id,user_id")
    .in("outfit_id", outfitIDs);
  if (error || !data || data.length < 6) {
    throw new Error("Could not read the persisted outfit-item rows for the brief.");
  }
  const seenOutfits = new Set((data as { outfit_id: string }[]).map((row) => row.outfit_id));
  for (const outfitID of outfitIDs) {
    assert(seenOutfits.has(outfitID), "A returned outfit ID has no persisted outfit-item rows.");
  }
  for (
    const row of data as { outfit_id: string; closet_item_id: string | null; user_id: string }[]
  ) {
    assert(row.user_id === account.userId, "An outfit-item row was not owned by the caller.");
    assert(
      row.closet_item_id !== null && closetIDs.has(row.closet_item_id),
      "The generated outfit referenced a garment outside the seeded caller-owned closet.",
    );
  }
}

async function verifyProfileExportManifest(
  baseURL: string,
  anonKey: string,
  owner: SyntheticAccount,
  peer: SyntheticAccount,
  expectedPaths: readonly string[],
): Promise<void> {
  const response = await fetch(baseURL + "/functions/v1/profile/export-data", {
    method: "GET",
    headers: {
      apikey: anonKey,
      authorization: "Bearer " + owner.accessToken,
      "x-request-id": crypto.randomUUID(),
    },
    signal: AbortSignal.timeout(30_000),
  });
  assert(response.status === 200, "Owner profile export did not return HTTP 200.");
  assert(
    response.headers.get("cache-control")?.includes("no-store"),
    "Owner profile export did not include Cache-Control: no-store.",
  );
  const exportEnvelope = await response.json() as Envelope<{
    readonly owner_user_id?: string;
    readonly referenced_storage_objects?: readonly {
      readonly bucket: string;
      readonly path: string;
    }[];
    readonly storage_manifest_scope?: string;
  }>;
  const exportDTO = exportEnvelope.data;
  assert(exportDTO, "Owner profile export returned an empty response envelope.");
  assert(exportDTO.owner_user_id === owner.userId, "Export owner did not match the caller.");
  const manifest = exportDTO.referenced_storage_objects ?? [];
  for (const path of expectedPaths) {
    assert(
      manifest.some((reference) => reference.bucket === "user-content" && reference.path === path),
      "Export manifest omitted an owned source, cutout, or thumbnail path.",
    );
  }
  assert(
    exportDTO.storage_manifest_scope?.includes(
      "does not verify whether referenced objects exist",
    ) &&
      exportDTO.storage_manifest_scope.includes("does not enumerate all Storage objects"),
    "Export manifest overstated what its referenced path list proves.",
  );

  const { data: peerRows, error: peerError } = await peer.client
    .from("closet_item_images")
    .select("id")
    .eq("user_id", owner.userId);
  if (peerError || !peerRows || peerRows.length !== 0) {
    throw new Error("Peer session could read owner closet-image metadata.");
  }
}

async function requestAccountDeletion(
  baseURL: string,
  anonKey: string,
  serviceClient: SupabaseClient,
  account: SyntheticAccount,
): Promise<void> {
  const response = await fetch(baseURL + "/functions/v1/account", {
    method: "DELETE",
    headers: {
      apikey: anonKey,
      authorization: "Bearer " + account.accessToken,
      "x-request-id": crypto.randomUUID(),
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (response.status !== 202) {
    await response.body?.cancel();
    throw new Error("Temporary account deletion was not accepted (HTTP " + response.status + ").");
  }
  const receiptEnvelope = await response.json() as Envelope<DeletionReceipt>;
  const deletionID = receiptEnvelope.data?.deletion_id;
  if (!deletionID || receiptEnvelope.error) {
    throw new Error("Temporary account deletion did not return its deletion receipt.");
  }

  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline) {
    const { data: deletion, error: deletionError } = await serviceClient
      .from("account_deletions")
      .select("status")
      .eq("id", deletionID)
      .maybeSingle();
    if (deletionError) throw new Error("Could not verify temporary account deletion status.");
    if (deletion?.status === "completed") {
      const tables = [
        "closet_items",
        "closet_item_images",
        "outfits",
        "outfit_items",
        "daily_briefs",
      ];
      for (const table of tables) {
        const { count, error } = await serviceClient
          .from(table)
          .select("id", { count: "exact", head: true })
          .eq("user_id", account.userId);
        if (error || count === null || count !== 0) {
          throw new Error("Account deletion completed but owned fixture rows remain.");
        }
      }
      const { data: authResult, error: authError } = await serviceClient.auth.admin
        .getUserById(account.userId);
      if (!authError && authResult.user) {
        throw new Error("Account deletion completed but Auth still recognizes the account.");
      }
      if (authError && (authError as { status?: number }).status !== 404) {
        throw new Error("Could not verify the temporary Auth identity was deleted.");
      }
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error("The temporary account deletion did not reach completed status before timeout.");
}

export async function runHostedDailyBriefAcceptance(): Promise<void> {
  if (Deno.env.get(RUN_GATE) !== RUN_GATE_VALUE) {
    throw new Error("Set " + RUN_GATE + "=YES only for a disposable test project.");
  }
  const baseURL = requiredEnvironment("SUPABASE_URL").replace(/\/$/, "");
  const keysFile = requiredEnvironment("SUPABASE_KEYS_FILE");
  const keyRecords = JSON.parse(await Deno.readTextFile(keysFile)) as Array<{
    readonly name?: string;
    readonly api_key?: string;
  }>;
  const anonKey = keyRecords.find((record) => record.name === "anon")?.api_key;
  const serviceRoleKey = keyRecords.find((record) => record.name === "service_role")?.api_key;
  if (!anonKey || !serviceRoleKey) {
    throw new Error("Protected Supabase key file lacks the required project keys.");
  }
  const serviceClient = createClient(baseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const host = new URL(baseURL).hostname;
  assert(
    host.endsWith(".supabase.co") || host === "127.0.0.1" || host === "localhost",
    "Unexpected Supabase URL host.",
  );

  let owner: SyntheticAccount | undefined;
  let peer: SyntheticAccount | undefined;
  let primaryFailure: unknown;
  const cleanupFailures: string[] = [];
  try {
    owner = await createSyntheticAccount(baseURL, anonKey);
    peer = await createSyntheticAccount(baseURL, anonKey);
    const ownerCloset = await seedCloset(owner, "owner");
    const imagePaths = await seedClosetImageMetadata(owner, ownerCloset);
    await seedCloset(peer, "peer");

    const briefDate = new Date().toISOString().slice(0, 10);
    const first = await generate(owner, briefDate, false);
    assert(first.brief_date === briefDate, "The endpoint returned an unexpected brief date.");
    assert(
      first.weather_snapshot?.["apparent_temperature"] === 32,
      "Weather snapshot did not round-trip.",
    );
    assert(first.weather_snapshot?.["season"] === "winter", "Season did not round-trip.");
    assert(
      first.schedule_snapshot?.["event_count"] === 1,
      "Calendar event count did not round-trip.",
    );
    await verifyOwnedReferences(owner, first, ownerCloset);
    await verifyProfileExportManifest(baseURL, anonKey, owner, peer, imagePaths);

    const outfitCountAfterFirst = await countOwnedOutfits(owner);
    const replay = await generate(owner, briefDate, false);
    assert(replay.id === first.id, "Same-day replay returned another brief row.");
    assert(
      replay.primary_outfit_id === first.primary_outfit_id,
      "Same-day replay changed the primary outfit.",
    );
    assert(
      await countOwnedOutfits(owner) === outfitCountAfterFirst,
      "Same-day idempotent replay unexpectedly persisted more outfits.",
    );

    const regenerated = await generate(owner, briefDate, true);
    assert(
      regenerated.id === first.id,
      "Explicit regeneration did not update the same day's brief.",
    );
    assert(
      regenerated.primary_outfit_id !== first.primary_outfit_id,
      "Explicit regeneration did not persist a fresh outfit row.",
    );
    await verifyOwnedReferences(owner, regenerated, ownerCloset);

    // The peer's high-formality fixture rows must never appear in the owner's
    // persisted joins; verifyOwnedReferences enforces exact owner closet IDs.
    console.log(
      "P4-TEST-03 hosted Daily Brief acceptance passed; synthetic account cleanup is being verified.",
    );
  } catch (error) {
    primaryFailure = error;
  } finally {
    if (peer) {
      try {
        await requestAccountDeletion(baseURL, anonKey, serviceClient, peer);
      } catch {
        cleanupFailures.push("peer");
      }
    }
    if (owner) {
      try {
        await requestAccountDeletion(baseURL, anonKey, serviceClient, owner);
      } catch {
        cleanupFailures.push("owner");
      }
    }
  }

  if (primaryFailure) {
    const detail = primaryFailure instanceof Error
      ? primaryFailure.message
      : "unknown acceptance failure";
    if (owner && peer) {
      console.log(
        `Disposable owner/peer IDs for cleanup verification: ${owner.userId}, ${peer.userId}; ` +
          `unverified cleanup accounts: ${cleanupFailures.join(",") || "none"}`,
      );
    }
    throw new Error(
      detail +
        (cleanupFailures.length
          ? "; account cleanup not accepted for: " + cleanupFailures.join(", ")
          : ""),
    );
  }
  if (cleanupFailures.length) {
    throw new Error("Account cleanup was not verified for: " + cleanupFailures.join(", "));
  }
  console.log(
    "Both synthetic accounts reached completed deletion; all owned fixture row counts were zero.",
  );
  if (owner && peer) {
    console.log(`Cleanup-verified disposable owner/peer IDs: ${owner.userId}, ${peer.userId}`);
  }
}

if (import.meta.main) {
  await runHostedDailyBriefAcceptance();
}
