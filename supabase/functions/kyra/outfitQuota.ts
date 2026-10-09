import type { NewOutfitRecord } from "./tools/createOutfit.ts";

export interface OutfitGenerationQuotaRow {
  readonly allowed: boolean;
  readonly remaining: number;
  readonly resetsAt: string;
  readonly limitCount: number;
  readonly reservation_id: string | null;
  readonly replay_payload: unknown;
  readonly in_flight: boolean;
}

export interface OutfitGenerationQuotaOperations {
  isPremium(userID: string, now: Date): Promise<boolean>;
  reserve(
    userID: string,
    requestID: string,
    fingerprint: string,
    now: Date,
  ): Promise<OutfitGenerationQuotaRow>;
  finish(
    userID: string,
    reservationID: string,
    succeeded: boolean,
    result: unknown,
    now: Date,
  ): Promise<void>;
}

export interface OutfitQuotaIdentity {
  readonly requestID: string;
  readonly fingerprint: string;
}

export interface ReservedBuilderOutfitQuota extends OutfitQuotaIdentity {
  readonly userID: string;
  readonly premium: boolean;
  readonly reservationID: string | null;
  readonly replayResult: Record<string, unknown> | null;
  used: boolean;
  settled: boolean;
}

export interface AtomicOutfitCommit {
  readonly userID: string;
  readonly requestID: string;
  readonly fingerprint: string;
  readonly reservationID: string | null;
  readonly record: NewOutfitRecord;
  readonly result: Record<string, unknown>;
  readonly lockedItemIDs: readonly string[];
  readonly allowProductCandidates: boolean;
  readonly now: Date;
}

export function canonicalJson(value: unknown): string {
  if (value === undefined) return "null";
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
      a.localeCompare(b)
    );
    return `{${
      entries.map(([key, entry]) => `${JSON.stringify(key)}:${canonicalJson(entry)}`).join(",")
    }}`;
  }
  return JSON.stringify(value) ?? "null";
}

export async function createOutfitQuotaIdentity(
  outerRequestID: string,
  operation: unknown,
  toolCallID = "builder",
): Promise<OutfitQuotaIdentity> {
  const serialized = canonicalJson(operation);
  const bytes = new TextEncoder().encode(serialized);
  const fingerprintBytes = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const fingerprint = [...fingerprintBytes].map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const operationBytes = new TextEncoder().encode(
    `${outerRequestID}\0${toolCallID}\0${fingerprint}`,
  );
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", operationBytes)).slice(0, 16);
  digest[6] = (digest[6]! & 0x0f) | 0x50;
  digest[8] = (digest[8]! & 0x3f) | 0x80;
  const hex = [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const requestID = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
  return { requestID, fingerprint };
}

export function replayResultFromQuota(value: unknown): Record<string, unknown> | null {
  if (!Array.isArray(value) || value.length !== 1) return null;
  const result = value[0];
  if (result === null || typeof result !== "object" || Array.isArray(result)) return null;
  const record = result as Record<string, unknown>;
  return typeof record["outfit_id"] === "string" ? record : null;
}
