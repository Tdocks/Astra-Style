// ============================================================================
// packing/schema.ts
// ============================================================================
// Request parsing and the wire DTO for `POST /packing/generate`
// (spec §14, §6.24). Same envelope as daily-brief. Identity is JWT-only.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MAX_DAYS = 14;
const LUGGAGE = new Set([
  "personal_item_only",
  "carry_on_only",
  "checked_bag",
  "no_constraint",
]);
const DRESS_CODES = new Set([
  "ultra_casual",
  "casual",
  "smart_casual",
  "business_casual",
  "business_formal",
  "black_tie",
  "formal",
  "athletic",
]);

export interface GeneratePackingBody {
  readonly destination: string;
  readonly startDate: string;
  readonly endDate: string;
  readonly activities: readonly string[];
  readonly dressCodes: readonly string[];
  readonly luggageConstraint: string;
  readonly hasLaundryAccess: boolean;
  readonly regenerate: boolean;
}

export interface PackingDayWire {
  readonly date: string;
  readonly outfit_id: string;
  readonly is_rewear: boolean;
}

export interface PackingPlanWire {
  readonly packing_list_item_ids: readonly string[];
  readonly daily_outfit_plan: readonly PackingDayWire[];
  readonly missing_essentials: readonly string[];
  readonly weather_contingency_note: string | null;
}

function asRecord(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw badRequest(`${what} must be a JSON object.`);
  }
  return value as Record<string, unknown>;
}

export function parseEnvelope(raw: unknown): { requestId?: string; body: unknown } {
  const record = asRecord(raw, "Request");
  if (!("body" in record)) {
    throw badRequest("Request envelope must carry a `body` field.");
  }
  const requestId = record["request_id"];
  if (requestId !== undefined && typeof requestId !== "string") {
    throw badRequest("`request_id` must be a string when present.");
  }
  return { requestId: requestId as string | undefined, body: record["body"] };
}

function requireDate(value: unknown, field: string): string {
  if (typeof value !== "string" || !DATE_PATTERN.test(value)) {
    throw badRequest(`${field} must be YYYY-MM-DD.`);
  }
  return value;
}

function daysInclusive(start: string, end: string): string[] {
  if (end < start) {
    throw badRequest("end_date must be on or after start_date.");
  }
  const dates: string[] = [];
  let cursor = start;
  while (cursor <= end) {
    dates.push(cursor);
    const next = new Date(`${cursor}T00:00:00Z`);
    next.setUTCDate(next.getUTCDate() + 1);
    cursor = next.toISOString().slice(0, 10);
    if (dates.length > MAX_DAYS) {
      throw badRequest(`A packing plan can cover at most ${MAX_DAYS} days.`);
    }
  }
  return dates;
}

export function parseGeneratePackingBody(raw: unknown): GeneratePackingBody {
  const record = asRecord(raw, "Body");
  const destination = typeof record["destination"] === "string" ? record["destination"].trim() : "";
  const startDate = requireDate(record["start_date"], "start_date");
  const endDate = requireDate(record["end_date"], "end_date");
  daysInclusive(startDate, endDate);

  const activities = Array.isArray(record["activities"])
    ? record["activities"].filter((item): item is string => typeof item === "string")
    : [];
  const dressCodes = Array.isArray(record["dress_codes"])
    ? record["dress_codes"].filter((item): item is string =>
      typeof item === "string" && DRESS_CODES.has(item)
    )
    : [];
  const luggage = typeof record["luggage_constraint"] === "string" &&
      LUGGAGE.has(record["luggage_constraint"])
    ? record["luggage_constraint"]
    : "no_constraint";
  const hasLaundryAccess = record["has_laundry_access"] === true;
  const regenerate = record["regenerate"] === true;

  return {
    destination,
    startDate,
    endDate,
    activities,
    dressCodes,
    luggageConstraint: luggage,
    hasLaundryAccess,
    regenerate,
  };
}

export function planDates(startDate: string, endDate: string): string[] {
  return daysInclusive(startDate, endDate);
}

export function nextDay(date: string): string {
  const next = new Date(`${date}T00:00:00Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString().slice(0, 10);
}
