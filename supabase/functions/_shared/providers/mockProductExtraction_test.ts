import { assertEquals, assertNotEquals } from "@std/assert";
import { MockProductExtractionProvider } from "./mockProductExtraction.ts";

const CTX = { requestId: "req-1", userId: "user-1", timeoutMs: 5000 };

Deno.test("mockProductExtraction: known retailer resolves brand/retailer/category with high confidence", async () => {
  const provider = new MockProductExtractionProvider();
  const result = await provider.extractProduct(
    { url: "https://www.uniqlo.com/us/en/products/oxford-cloth-button-down-shirt" },
    CTX,
  );
  assertEquals(result.retailer?.value, "Uniqlo");
  assertEquals(result.brand?.value, "Uniqlo");
  assertEquals(result.category?.value, "top");
  assertEquals(result.price, null);
  assertEquals(result.unreadFields.includes("price"), true);
});

Deno.test("mockProductExtraction: unknown retailer still derives a plausible, lower-confidence result", async () => {
  const provider = new MockProductExtractionProvider();
  const result = await provider.extractProduct(
    { url: "https://www.some-boutique.example/shop/navy-wool-trouser" },
    CTX,
  );
  assertEquals(result.name !== null, true);
  assertEquals(result.category?.value, "bottom");
  assertEquals(result.brand, null);
  assertEquals(result.unreadFields.includes("brand"), true);
  // Retailer IS flagged unread, and the original expectation here (that it
  // must not be) conflated two different things. `unreadFields` records what
  // the PROVIDER could not read off the page; a hostname is not a retailer
  // name. `candidateMapper.ts` separately derives a display fallback from the
  // domain, which is why the row still ends up with a retailer — but claiming
  // the provider read one would make `unreadFields` unreliable everywhere
  // else, and it is the one signal the decision page has for "we are guessing
  // at this".
  assertEquals(result.unreadFields.includes("retailer"), true);
});

Deno.test("mockProductExtraction: two different URLs extract to two different names (not one canned fixture)", async () => {
  const provider = new MockProductExtractionProvider();
  const a = await provider.extractProduct({ url: "https://example.com/products/navy-blazer" }, CTX);
  const b = await provider.extractProduct({ url: "https://example.com/products/khaki-chino" }, CTX);
  assertNotEquals(a.name?.value, b.name?.value);
});

Deno.test("mockProductExtraction: /unextractable path yields a null name (extraction-failure fixture)", async () => {
  const provider = new MockProductExtractionProvider();
  const result = await provider.extractProduct(
    { url: "https://example.com/unextractable/page" },
    CTX,
  );
  assertEquals(result.name, null);
});

Deno.test("mockProductExtraction: a bare hostname with no path has no name to derive", async () => {
  const provider = new MockProductExtractionProvider();
  const result = await provider.extractProduct({ url: "https://example.com/" }, CTX);
  assertEquals(result.name, null);
});

Deno.test("mockProductExtraction: is deterministic across repeated calls", async () => {
  const provider = new MockProductExtractionProvider();
  const url = "https://www.jcrew.com/p/mens/categories/clothing/jeans/slim/broken-in-jean";
  const first = await provider.extractProduct({ url }, CTX);
  const second = await provider.extractProduct({ url }, CTX);
  assertEquals(first, second);
});

Deno.test("mockProductExtraction: canonicalUrl strips tracking parameters", async () => {
  const provider = new MockProductExtractionProvider();
  const result = await provider.extractProduct(
    { url: "https://example.com/products/navy-blazer?utm_source=newsletter&color=navy" },
    CTX,
  );
  assertEquals(result.canonicalUrl, "https://example.com/products/navy-blazer?color=navy");
});
