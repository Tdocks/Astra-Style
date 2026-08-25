// ============================================================================
// kyra/tools/getWeather.ts
// ============================================================================
// The `get_weather` tool (P5-KYRA-07, docs/06 §3.6) — and the sharpest test
// of this codebase's honesty rule. There is NO server-side weather provider,
// by design: `daily-brief/README.md` records the decision that the client's
// own WeatherKit reading travels up in the request body, and the server
// never looks a forecast up itself. This tool therefore reads exactly one
// thing — the `weather_snapshot` the client sent with THIS request — and
// when none was sent it says so: `{available: false}` with a reason the
// model can relay ("I don't have your weather today"). A tool that invented
// a plausible forecast here is precisely the confounded reading docs/06 §6's
// weather-unavailable row forbids.
//
// `date_range_days` is accepted per the §3.6 schema, but the snapshot the
// client sends is a single same-day reading (high/low/condition), in the
// iOS WeatherSnapshot wire convention of Fahrenheit. Tool output is `_c`,
// so conversion happens here before the model sees it. The forecast array
// carries at most that one day and names its own limitation rather than
// padding days that were never measured.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import type { WeatherSnapshot } from "../schema.ts";

export interface GetWeatherDeps {
  /** The snapshot from THIS request's body, or null if the client sent none. */
  readonly weatherSnapshot: WeatherSnapshot | null;
  /** Injected clock so the forecast entry's date is testable. */
  readonly now: () => Date;
}

export const getWeatherDefinition: StylistToolDefinition = {
  name: "get_weather",
  description: "Read the weather snapshot the user's device sent with this request. Read-only. " +
    "If the device sent none, reports unavailable — never estimates.",
  parametersSchema: {
    type: "object",
    properties: {
      date_range_days: { type: "integer", default: 3, maximum: 10 },
    },
  },
};

export function executeGetWeather(
  _args: Record<string, unknown>,
  deps: GetWeatherDeps,
): Record<string, unknown> {
  const snapshot = deps.weatherSnapshot;
  if (snapshot === null) {
    return {
      available: false,
      reason: "NO_CLIENT_SNAPSHOT",
      detail: "The device did not send a weather reading with this request. Do not guess the " +
        "weather; reason without it, and say so if it materially affects the answer.",
    };
  }
  const today = deps.now().toISOString().slice(0, 10);
  const highC = fahrenheitToCelsius(snapshot.temperatureHigh);
  const lowC = fahrenheitToCelsius(snapshot.temperatureLow);
  return {
    available: true,
    current_temp_c: null,
    high_c: highC,
    low_c: lowC,
    condition: snapshot.condition,
    forecast: [
      {
        date: today,
        high_c: highC,
        low_c: lowC,
        condition: snapshot.condition,
      },
    ],
    detail: "Single same-day reading from the user's device. No multi-day forecast exists " +
      "server-side; do not extrapolate beyond today.",
  };
}

function fahrenheitToCelsius(value: number): number {
  return Math.round(((value - 32) * 5 / 9) * 10) / 10;
}
