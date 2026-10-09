import { assertStringIncludes } from "@std/assert";

interface BudgetExpectation {
  readonly tableRoute: string;
  readonly budget: string;
  readonly configFile: string;
  readonly routeFile?: string;
  readonly limit: number;
  readonly windowMs: string;
  readonly routes: readonly string[];
  readonly additionalLimiters?: readonly { limit: number; windowMs: string }[];
}

const EXPECTATIONS: readonly BudgetExpectation[] = [
  {
    tableRoute: "POST /profile/complete-onboarding",
    budget: "6/user/minute",
    configFile: "profile/index.ts",
    limit: 6,
    windowMs: "60_000",
    routes: ["/complete-onboarding"],
  },
  {
    tableRoute: "GET /profile/export-data",
    budget: "2/user/hour",
    configFile: "profile/index.ts",
    limit: 2,
    windowMs: "60 * 60_000",
    routes: ["/export-data"],
  },
  {
    tableRoute: "DELETE /profile/reference-photos",
    budget: "30/user/minute",
    configFile: "profile/referenceDeletion.ts",
    routeFile: "profile/index.ts",
    limit: 30,
    windowMs: "60_000",
    routes: ["/reference-photos"],
  },
  {
    tableRoute: "POST /style-dna/generate",
    budget: "5/user/minute",
    configFile: "style-dna/index.ts",
    limit: 5,
    windowMs: "60_000",
    routes: ["/generate"],
  },
  {
    tableRoute:
      "POST /closet/remove-background, /closet/analyze-item, /closet/batch-analyze, GET /closet/batch-status/:id",
    budget: "30/user/minute, shared",
    configFile: "closet/index.ts",
    limit: 30,
    windowMs: "60_000",
    routes: ["/remove-background", "/analyze-item", "/batch-analyze", "/batch-status/:id"],
  },
  {
    tableRoute: "GET /closet/wardrobe-score, GET /closet/items/:id/insights",
    budget: "5/user/minute, shared",
    configFile: "closet/index.ts",
    limit: 5,
    windowMs: "60_000",
    routes: ["/wardrobe-score", "/items/:id/insights"],
  },
  {
    tableRoute: "GET /closet/items/:id/unlock-count",
    budget: "15/user/minute",
    configFile: "closet/index.ts",
    limit: 15,
    windowMs: "60_000",
    routes: ["/items/:id/unlock-count"],
  },
  {
    tableRoute:
      "POST /outfits/generate, /outfits/rank, /outfits/record-wear, /outfits/config/compatibility-weights",
    budget: "20/user/minute, shared",
    configFile: "outfits/index.ts",
    limit: 20,
    windowMs: "60_000",
    routes: ["/generate", "/rank", "/record-wear", "/config/compatibility-weights"],
  },
  {
    tableRoute: "POST /daily-brief/generate",
    budget: "10/user/minute",
    configFile: "daily-brief/index.ts",
    limit: 10,
    windowMs: "60_000",
    routes: ["/generate"],
  },
  {
    tableRoute: "POST /kyra/respond",
    budget: "10/user/minute",
    configFile: "kyra/index.ts",
    limit: 10,
    windowMs: "60_000",
    routes: ["/respond"],
  },
  {
    tableRoute: "POST /products/extract, /products/evaluate, /products/unlocks",
    budget: "10/user/minute, shared",
    configFile: "products/index.ts",
    limit: 10,
    windowMs: "60_000",
    routes: ["/extract", "/evaluate", "/unlocks"],
  },
  {
    tableRoute: "POST /studio/generate, /studio/export-hi-res",
    budget: "6/user/minute, shared",
    configFile: "studio/index.ts",
    limit: 6,
    windowMs: "60_000",
    routes: ["/generate", "/export-hi-res"],
  },
  {
    tableRoute: "GET /studio/status/:id",
    budget: "120/user/minute",
    configFile: "studio/index.ts",
    limit: 120,
    windowMs: "60_000",
    routes: ["/status/:id"],
  },
  {
    tableRoute: "DELETE /studio/generations/:id",
    budget: "30/user/minute",
    configFile: "studio/deletion.ts",
    routeFile: "studio/index.ts",
    limit: 30,
    windowMs: "60_000",
    routes: ["/generations/:id"],
  },
  {
    tableRoute: "POST /packing/generate",
    budget: "10/user/minute",
    configFile: "packing/index.ts",
    limit: 10,
    windowMs: "60_000",
    routes: ["/generate"],
  },
  {
    tableRoute: "POST /subscriptions/sync",
    budget: "20/user/minute",
    configFile: "subscriptions/index.ts",
    limit: 20,
    windowMs: "60_000",
    routes: ["/sync"],
  },
  {
    tableRoute: "POST /lookbook/sign-images",
    budget: "60/user/minute",
    configFile: "lookbook/index.ts",
    limit: 60,
    windowMs: "60_000",
    routes: ["/sign-images"],
  },
  {
    tableRoute: "DELETE /account",
    budget: "3/user/minute",
    configFile: "account/index.ts",
    limit: 3,
    windowMs: "60_000",
    routes: ["/"],
  },
  {
    tableRoute: "POST /app-store/webhook",
    budget: "1,200/inbound/minute, then 600/verified bundle/minute",
    configFile: "app-store/index.ts",
    limit: 1200,
    windowMs: "60_000",
    routes: ["/webhook"],
    additionalLimiters: [{ limit: 600, windowMs: "60_000" }],
  },
];

const functionsRoot = new URL("../", import.meta.url);

Deno.test("README endpoint budgets match configured limiters and registered routes", async () => {
  const read = (path: string) => Deno.readTextFile(new URL(path, functionsRoot));
  const readme = await read("README.md");
  const markdownTableText = readme.replaceAll("`", "");

  function assertLimiter(source: string, limit: number, windowMs: string, file: string) {
    const configPattern = new RegExp(
      `createRateLimiter\\(\\{\\s*limit:\\s*${limit},\\s*windowMs:\\s*${
        windowMs.replaceAll("*", "\\*")
      },?\\s*\\}\\)`,
    );
    if (!configPattern.test(source)) {
      throw new Error(`README budget does not match ${file}`);
    }
  }

  for (const expectation of EXPECTATIONS) {
    assertStringIncludes(
      markdownTableText,
      `| ${expectation.tableRoute} | ${expectation.budget} |`,
    );
    const source = await read(expectation.configFile);
    assertLimiter(source, expectation.limit, expectation.windowMs, expectation.configFile);
    for (const limiter of expectation.additionalLimiters ?? []) {
      assertLimiter(source, limiter.limit, limiter.windowMs, expectation.configFile);
    }
    const routeSource = expectation.routeFile ? await read(expectation.routeFile) : source;
    for (const route of expectation.routes) {
      assertStringIncludes(routeSource, `pattern: "${route}"`);
    }
  }

  for (const file of ["products/index.ts", "subscriptions/index.ts"]) {
    const source = await read(file);
    assertStringIncludes(source, "if (!limit.allowed)");
    assertStringIncludes(source, '"Retry-After": String(limit.retryAfterSeconds)');
  }
});
