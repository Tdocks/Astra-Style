import { assertEquals } from "@std/assert";
import type { OccasionSourceRow } from "../contextPacket.ts";
import { executeGetSchedule } from "./getSchedule.ts";

const NOW = () => new Date("2026-08-16T09:00:00Z");

const FRIDAY_DINNER: OccasionSourceRow = {
  id: "00000000-0000-4000-8000-000000000001",
  title: "Dinner with Sam",
  starts_at: "2026-08-21T18:30:00Z",
  dress_code: "smart_casual",
  location: "Osteria",
};

Deno.test("returns occasions within the requested window", async () => {
  const ranges: Array<[string, string]> = [];
  const result = await executeGetSchedule({ date_range_days: 7 }, {
    listOccasions: (fromIso, toIso) => {
      ranges.push([fromIso, toIso]);
      return Promise.resolve([FRIDAY_DINNER]);
    },
    now: NOW,
  });
  assertEquals(result["available"], true);
  const occasions = result["occasions"] as Array<Record<string, unknown>>;
  assertEquals(occasions.length, 1);
  assertEquals(occasions[0]!["title"], "Dinner with Sam");
  assertEquals(occasions[0]!["dress_code"], "smart_casual");
  // Window: now .. now + 7 days.
  assertEquals(ranges[0]![0], "2026-08-16T09:00:00.000Z");
  assertEquals(ranges[0]![1], "2026-08-23T09:00:00.000Z");
});

Deno.test("no occasions is a graceful empty result, not an error", async () => {
  const result = await executeGetSchedule({}, {
    listOccasions: () => Promise.resolve([]),
    now: NOW,
  });
  assertEquals(result["available"], true);
  assertEquals(result["occasions"], []);
  assertEquals(result["error"], undefined);
});

Deno.test("date_range_days is clamped to the documented maximum", async () => {
  const ranges: Array<[string, string]> = [];
  await executeGetSchedule({ date_range_days: 400 }, {
    listOccasions: (fromIso, toIso) => {
      ranges.push([fromIso, toIso]);
      return Promise.resolve([]);
    },
    now: NOW,
  });
  assertEquals(ranges[0]![1], "2026-09-15T09:00:00.000Z"); // 30 days, not 400
});
