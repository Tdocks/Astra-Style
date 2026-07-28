// ============================================================================
// _shared/validation.ts
// ============================================================================
// Small, dependency-free request-schema validation helpers, reused by every
// endpoint's own `schema.ts` (spec §14 "Validate request schema"). No
// external validation library — the request shapes in this project are
// small and flat enough that a hand-rolled validator is less code and less
// risk than adding a dependency, and it keeps every function's cold-start
// bundle small. Every helper either returns a well-typed value or throws an
// `AppError` (category "validation", HTTP 400) via `badRequest`.
// ============================================================================

import { badRequest } from "./errors.ts";

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isUUID(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

export function requireRecord(value: unknown, field: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw badRequest(`${field} must be a JSON object.`);
  }
  return value;
}

export function optionalString(
  value: unknown,
  field: string,
  maxLength = 2000,
): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw badRequest(`${field} must be a string.`);
  }
  if (value.length > maxLength) {
    throw badRequest(`${field} must be at most ${maxLength} characters.`);
  }
  return value;
}

export function optionalUUID(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (!isUUID(value)) {
    throw badRequest(`${field} must be a UUID string.`);
  }
  return value;
}

export function optionalUUIDArray(value: unknown, field: string, maxItems = 50): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw badRequest(`${field} must be an array of UUID strings.`);
  }
  if (value.length > maxItems) {
    throw badRequest(`${field} must contain at most ${maxItems} items.`);
  }
  return value.map((entry, index) => {
    if (!isUUID(entry)) {
      throw badRequest(`${field}[${index}] must be a UUID string.`);
    }
    return entry;
  });
}

export function optionalIntInRange(
  value: unknown,
  field: string,
  min: number,
  max: number,
  fallback: number,
): number {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw badRequest(`${field} must be an integer.`);
  }
  if (value < min || value > max) {
    throw badRequest(`${field} must be between ${min} and ${max}.`);
  }
  return value;
}
