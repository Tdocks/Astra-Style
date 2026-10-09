import { type ComponentWeights, DEFAULT_WEIGHTS } from "./compatibility.ts";

export interface CompatibilityWeightsConfig {
  readonly weights: ComponentWeights;
  readonly version: number;
}

const WEIGHT_NAMES = Object.keys(DEFAULT_WEIGHTS) as (keyof ComponentWeights)[];
const defaults = (version = 1): CompatibilityWeightsConfig => ({
  weights: DEFAULT_WEIGHTS,
  version,
});

/** Strictly parse the service-only configuration row; invalid rows use shipped defaults. */
export function parseCompatibilityWeightsConfig(raw: unknown): CompatibilityWeightsConfig {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return defaults();
  }
  const row = raw as Record<string, unknown>;
  const version = row["version"];
  const rawWeights = row["weights"];
  const safeVersion = Number.isSafeInteger(version) && (version as number) >= 1
    ? version as number
    : 1;
  if (rawWeights === null || typeof rawWeights !== "object" || Array.isArray(rawWeights)) {
    return defaults(safeVersion);
  }

  const input = rawWeights as Record<string, unknown>;
  if (
    Object.keys(input).length !== WEIGHT_NAMES.length ||
    WEIGHT_NAMES.some((name) => !Object.hasOwn(input, name))
  ) {
    return defaults(safeVersion);
  }
  const weights = {} as Record<keyof ComponentWeights, number>;
  let total = 0;
  for (const name of WEIGHT_NAMES) {
    const value = input[name];
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
      return defaults(safeVersion);
    }
    weights[name] = value;
    total += value;
  }
  if (!Number.isFinite(total) || total <= 0) return defaults(safeVersion);
  return { weights, version: safeVersion };
}

/** Read current server-owned weights using a service-role client. */
export async function loadCompatibilityWeightsConfig(serviceClient: {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: boolean): {
        maybeSingle(): PromiseLike<{ data: unknown; error: unknown }>;
      };
    };
  };
}): Promise<CompatibilityWeightsConfig> {
  try {
    const { data, error } = await serviceClient.from("compatibility_weights_config")
      .select("weights, version").eq("singleton", true).maybeSingle();
    if (error || !data) return defaults();
    return parseCompatibilityWeightsConfig(data);
  } catch {
    return defaults();
  }
}
