import { assertEquals, assertRejects } from "@std/assert";
import { HtmlProductExtractionProvider } from "./htmlProductExtraction.ts";
import { ProviderError } from "./types.ts";

const CTX = { requestId: "req-1", userId: "user-1", timeoutMs: 5000 };

function htmlResponse(html: string, status = 200): Response {
  return new Response(html, { status, headers: { "Content-Type": "text/html" } });
}

const JSON_LD_FIXTURE = `
<!doctype html>
<html>
<head>
<title>Fallback Title — Example Store</title>
<meta property="og:title" content="OG Title Should Lose To JSON-LD">
<meta property="og:site_name" content="Example Store">
<meta property="og:image" content="https://cdn.example.com/og-image.jpg">
<script type="application/ld+json">
{
  "@context": "https://schema.org/",
  "@type": "Product",
  "name": "Oxford Cloth Button-Down Shirt",
  "brand": { "@type": "Brand", "name": "Example Brand" },
  "image": ["https://cdn.example.com/product-image.jpg"],
  "category": "Men's Shirts",
  "offers": {
    "@type": "Offer",
    "price": "89.50",
    "priceCurrency": "USD"
  }
}
</script>
</head>
<body></body>
</html>
`;

Deno.test("htmlProductExtraction: JSON-LD Product wins over OG tags when both are present", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse(JSON_LD_FIXTURE)),
  });
  const result = await provider.extractProduct({ url: "https://shop.example.com/p/123" }, CTX);
  assertEquals(result.name?.value, "Oxford Cloth Button-Down Shirt");
  assertEquals(result.brand?.value, "Example Brand");
  assertEquals(result.price?.value, 89.5);
  assertEquals(result.currency?.value, "USD");
  assertEquals(result.imageUrl?.value, "https://cdn.example.com/product-image.jpg");
  assertEquals(result.category?.value, "top");
  assertEquals(result.unreadFields, []);
});

const OG_ONLY_FIXTURE = `
<!doctype html>
<html><head>
<meta property="og:title" content="Slim Chino — Navy">
<meta property="og:site_name" content="Another Store">
<meta property="product:price:amount" content="64.00">
<meta property="product:price:currency" content="USD">
<meta property="og:image" content="https://cdn.example.com/chino.jpg">
</head><body></body></html>
`;

Deno.test("htmlProductExtraction: falls back to OG tags when no JSON-LD Product exists", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse(OG_ONLY_FIXTURE)),
  });
  const result = await provider.extractProduct({ url: "https://shop.example.com/p/456" }, CTX);
  assertEquals(result.name?.value, "Slim Chino — Navy");
  assertEquals(result.price?.value, 64.0);
  assertEquals(result.category?.value, "bottom");
  assertEquals(result.name && result.name.confidence < 0.85, true);
});

Deno.test("htmlProductExtraction: title tag is the last resort and stays low-confidence", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () =>
      Promise.resolve(htmlResponse("<html><head><title>Just A Title</title></head></html>")),
  });
  const result = await provider.extractProduct({ url: "https://shop.example.com/p/789" }, CTX);
  assertEquals(result.name?.value, "Just A Title");
  assertEquals(result.name!.confidence < 0.6, true);
  assertEquals(result.price, null);
  assertEquals(result.unreadFields.includes("price"), true);
});

Deno.test("htmlProductExtraction: a page with nothing at all yields name: null, never a fabricated title", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse("<html><body>Loading…</body></html>")),
  });
  const result = await provider.extractProduct({ url: "https://shop.example.com/p/loading" }, CTX);
  assertEquals(result.name, null);
  assertEquals(result.unreadFields.includes("name"), true);
});

Deno.test("htmlProductExtraction: malformed JSON-LD does not sink extraction of usable OG tags", async () => {
  const html = `<html><head>
    <script type="application/ld+json">{ not valid json </script>
    <meta property="og:title" content="Still Readable Title">
  </head></html>`;
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse(html)),
  });
  const result = await provider.extractProduct({ url: "https://shop.example.com/p/broken" }, CTX);
  assertEquals(result.name?.value, "Still Readable Title");
});

Deno.test("htmlProductExtraction: 404 maps to a non-retryable INVALID_INPUT error", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse("not found", 404)),
  });
  const err = await assertRejects(
    () => provider.extractProduct({ url: "https://shop.example.com/gone" }, CTX),
    ProviderError,
  );
  assertEquals((err as ProviderError).code, "INVALID_INPUT");
  assertEquals((err as ProviderError).retryable, false);
});

Deno.test("htmlProductExtraction: 429 maps to a retryable RATE_LIMITED error", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse("slow down", 429)),
  });
  const err = await assertRejects(
    () => provider.extractProduct({ url: "https://shop.example.com/busy" }, CTX),
    ProviderError,
  );
  assertEquals((err as ProviderError).code, "RATE_LIMITED");
  assertEquals((err as ProviderError).retryable, true);
});

Deno.test("htmlProductExtraction: 403 maps to a non-retryable PROVIDER_UNAVAILABLE error (anti-bot block)", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse("blocked", 403)),
  });
  const err = await assertRejects(
    () => provider.extractProduct({ url: "https://shop.example.com/blocked" }, CTX),
    ProviderError,
  );
  assertEquals((err as ProviderError).code, "PROVIDER_UNAVAILABLE");
  assertEquals((err as ProviderError).retryable, false);
});

Deno.test("htmlProductExtraction: 500 maps to a retryable PROVIDER_UNAVAILABLE error", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.resolve(htmlResponse("oops", 500)),
  });
  const err = await assertRejects(
    () => provider.extractProduct({ url: "https://shop.example.com/error" }, CTX),
    ProviderError,
  );
  assertEquals((err as ProviderError).code, "PROVIDER_UNAVAILABLE");
  assertEquals((err as ProviderError).retryable, true);
});

Deno.test("htmlProductExtraction: a network failure maps to a retryable PROVIDER_UNAVAILABLE error", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: () => Promise.reject(new TypeError("network down")),
  });
  const err = await assertRejects(
    () => provider.extractProduct({ url: "https://shop.example.com/down" }, CTX),
    ProviderError,
  );
  assertEquals((err as ProviderError).code, "PROVIDER_UNAVAILABLE");
  assertEquals((err as ProviderError).retryable, true);
});

Deno.test("htmlProductExtraction: an aborted fetch maps to a retryable TIMEOUT error", async () => {
  const provider = new HtmlProductExtractionProvider({
    fetchImpl: (_url, init) =>
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener("abort", () => {
          reject(new DOMException("The operation was aborted.", "AbortError"));
        });
      }),
  });
  const err = await assertRejects(
    () =>
      provider.extractProduct({ url: "https://shop.example.com/slow" }, { ...CTX, timeoutMs: 5 }),
    ProviderError,
  );
  assertEquals((err as ProviderError).code, "TIMEOUT");
  assertEquals((err as ProviderError).retryable, true);
});
