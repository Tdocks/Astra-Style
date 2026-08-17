import { assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import { assertSafeExternalUrl } from "./urlValidation.ts";

Deno.test("urlValidation: accepts an ordinary https retailer URL", () => {
  assertSafeExternalUrl("https://www.example-retailer.com/products/navy-blazer");
});

Deno.test("urlValidation: rejects a non-http(s) scheme", () => {
  assertThrows(() => assertSafeExternalUrl("ftp://example.com/file"), AppError);
  assertThrows(() => assertSafeExternalUrl("file:///etc/passwd"), AppError);
  assertThrows(() => assertSafeExternalUrl("javascript:alert(1)"), AppError);
});

Deno.test("urlValidation: rejects localhost and .local hostnames", () => {
  assertThrows(() => assertSafeExternalUrl("http://localhost:8080/admin"), AppError);
  assertThrows(() => assertSafeExternalUrl("http://printer.local/"), AppError);
});

Deno.test("urlValidation: rejects loopback and private IPv4 literals", () => {
  assertThrows(() => assertSafeExternalUrl("http://127.0.0.1/"), AppError);
  assertThrows(() => assertSafeExternalUrl("http://10.0.0.5/"), AppError);
  assertThrows(() => assertSafeExternalUrl("http://192.168.1.1/"), AppError);
  assertThrows(() => assertSafeExternalUrl("http://172.16.0.1/"), AppError);
});

Deno.test("urlValidation: rejects the cloud metadata address", () => {
  assertThrows(() => assertSafeExternalUrl("http://169.254.169.254/latest/meta-data/"), AppError);
});

Deno.test("urlValidation: rejects IPv6 loopback and link-local", () => {
  assertThrows(() => assertSafeExternalUrl("http://[::1]/"), AppError);
  assertThrows(() => assertSafeExternalUrl("http://[fe80::1]/"), AppError);
});

Deno.test("urlValidation: rejects embedded credentials", () => {
  assertThrows(() => assertSafeExternalUrl("https://user:pass@example.com/"), AppError);
});

Deno.test("urlValidation: rejects an empty or malformed url", () => {
  assertThrows(() => assertSafeExternalUrl(""), AppError);
  assertThrows(() => assertSafeExternalUrl("not a url"), AppError);
});

Deno.test("urlValidation: rejects an overlong url", () => {
  const longUrl = "https://example.com/" + "a".repeat(2048);
  assertThrows(() => assertSafeExternalUrl(longUrl), AppError);
});

Deno.test("urlValidation: accepts a public IPv4 literal (not blocked, just unusual)", () => {
  assertSafeExternalUrl("http://93.184.216.34/product");
});
