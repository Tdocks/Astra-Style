import { assertEquals, assertThrows } from "@std/assert";
import { AppError } from "./errors.ts";
import {
  isRecord,
  isUUID,
  optionalIntInRange,
  optionalString,
  optionalUUID,
  optionalUUIDArray,
  requireRecord,
} from "./validation.ts";

const VALID_UUID = "550e8400-e29b-41d4-a716-446655440000";

Deno.test("isUUID accepts a well-formed v4-ish UUID", () => {
  assertEquals(isUUID(VALID_UUID), true);
});

Deno.test("isUUID rejects non-UUID strings", () => {
  assertEquals(isUUID("not-a-uuid"), false);
  assertEquals(isUUID(""), false);
  assertEquals(isUUID(123), false);
});

Deno.test("isRecord distinguishes plain objects from arrays/null/primitives", () => {
  assertEquals(isRecord({}), true);
  assertEquals(isRecord([]), false);
  assertEquals(isRecord(null), false);
  assertEquals(isRecord("x"), false);
});

Deno.test("requireRecord throws AppError for non-objects", () => {
  const err = assertThrows(() => requireRecord([], "body"), AppError);
  assertEquals(err.category, "validation");
});

Deno.test("optionalString allows undefined/null and rejects wrong type", () => {
  assertEquals(optionalString(undefined, "f"), undefined);
  assertEquals(optionalString(null, "f"), undefined);
  assertEquals(optionalString("hi", "f"), "hi");
  assertThrows(() => optionalString(5, "f"), AppError);
});

Deno.test("optionalString enforces a max length", () => {
  assertThrows(() => optionalString("x".repeat(10), "f", 5), AppError);
});

Deno.test("optionalUUID validates format when present", () => {
  assertEquals(optionalUUID(undefined, "f"), undefined);
  assertEquals(optionalUUID(VALID_UUID, "f"), VALID_UUID);
  assertThrows(() => optionalUUID("nope", "f"), AppError);
});

Deno.test("optionalUUIDArray defaults to empty and validates each element", () => {
  assertEquals(optionalUUIDArray(undefined, "f"), []);
  assertEquals(optionalUUIDArray([VALID_UUID], "f"), [VALID_UUID]);
  assertThrows(() => optionalUUIDArray(["nope"], "f"), AppError);
  assertThrows(() => optionalUUIDArray("not-an-array", "f"), AppError);
});

Deno.test("optionalUUIDArray enforces a max item count", () => {
  const tooMany = Array.from({ length: 5 }, () => VALID_UUID);
  assertThrows(() => optionalUUIDArray(tooMany, "f", 3), AppError);
});

Deno.test("optionalIntInRange applies the fallback and enforces bounds", () => {
  assertEquals(optionalIntInRange(undefined, "f", 1, 6, 3), 3);
  assertEquals(optionalIntInRange(4, "f", 1, 6, 3), 4);
  assertThrows(() => optionalIntInRange(7, "f", 1, 6, 3), AppError);
  assertThrows(() => optionalIntInRange(1.5, "f", 1, 6, 3), AppError);
  assertThrows(() => optionalIntInRange("3", "f", 1, 6, 3), AppError);
});
