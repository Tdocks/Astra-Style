import { assert, assertEquals } from "@std/assert";
import { executeGetWeather } from "./getWeather.ts";

const NOW = () => new Date("2026-08-16T09:00:00Z");

Deno.test("no client snapshot -> available:false with an explicit do-not-guess reason", () => {
  const result = executeGetWeather({}, { weatherSnapshot: null, now: NOW });
  assertEquals(result["available"], false);
  assertEquals(result["reason"], "NO_CLIENT_SNAPSHOT");
  // The refusal must instruct against guessing, not merely report absence.
  assert(String(result["detail"]).includes("Do not guess"));
  // And it must contain no fabricated reading.
  assertEquals(result["high_c"], undefined);
  assertEquals(result["condition"], undefined);
});

Deno.test("client snapshot is returned verbatim, scoped to today only", () => {
  const result = executeGetWeather({ date_range_days: 7 }, {
    weatherSnapshot: { temperatureHigh: 23, temperatureLow: 14, condition: "rain" },
    now: NOW,
  });
  assertEquals(result["available"], true);
  assertEquals(result["high_c"], 23);
  assertEquals(result["low_c"], 14);
  assertEquals(result["condition"], "rain");
  const forecast = result["forecast"] as Array<Record<string, unknown>>;
  // Even asked for 7 days, only the one measured day exists — no padding.
  assertEquals(forecast.length, 1);
  assertEquals(forecast[0]!["date"], "2026-08-16");
  assert(String(result["detail"]).includes("do not extrapolate"));
});
