import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { type AuthClient, authenticateUser } from "../_shared/jwt.ts";
import type { CompatibilityWeightsConfig } from "../_shared/scoring/compatibilityWeights.ts";
import { createLogger } from "../_shared/logger.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { isRecord } from "../_shared/validation.ts";
import type { ComponentWeights } from "../_shared/scoring/compatibility.ts";

const WEIGHT_KEYS: readonly (keyof ComponentWeights)[] = [
  "color",
  "formality",
  "silhouette",
  "seasonWeather",
  "userPreference",
  "coWear",
  "occasion",
  "availability",
];
const WEIGHT_SUM_EPSILON = 0.000001;

export interface CompatibilityWeightUpdate {
  readonly expectedVersion: number;
  readonly weights: ComponentWeights;
}

export interface CompatibilityWeightsAdminDependencies {
  readonly authClient: AuthClient;
  readonly rateLimiter: RateLimiter;
  readonly store: {
    /** Atomically updates only if the singleton is still at expectedVersion. */
    updateIfVersion(
      expectedVersion: number,
      weights: ComponentWeights,
    ): Promise<CompatibilityWeightsConfig | null>;
  };
  readonly now: () => Date;
}

export function parseCompatibilityWeightUpdate(raw: unknown): CompatibilityWeightUpdate {
  if (!isRecord(raw)) throw badRequest('Request envelope must contain a JSON object at "body".');
  const expectedVersion = raw["expected_version"];
  if (!Number.isSafeInteger(expectedVersion) || (expectedVersion as number) < 1) {
    throw badRequest("body.expected_version must be a positive integer.");
  }
  const rawWeights = raw["weights"];
  if (!isRecord(rawWeights)) throw badRequest("body.weights must be an object.");
  if (
    Object.keys(rawWeights).length !== WEIGHT_KEYS.length ||
    WEIGHT_KEYS.some((key) => !Object.hasOwn(rawWeights, key))
  ) {
    throw badRequest("body.weights must contain exactly the eight compatibility weights.");
  }

  const weights = {} as Record<keyof ComponentWeights, number>;
  let total = 0;
  for (const key of WEIGHT_KEYS) {
    const value = rawWeights[key];
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
      throw badRequest(`body.weights.${key} must be a finite number from 0 to 1.`);
    }
    weights[key] = value;
    total += value;
  }
  if (Math.abs(total - 1) > WEIGHT_SUM_EPSILON) {
    throw badRequest("Compatibility weights must sum to 1.0.");
  }
  return { expectedVersion: expectedVersion as number, weights };
}

/** Admin-only update. The admin claim is fetched from Supabase Auth on every request. */
export async function handleUpdateCompatibilityWeights(
  req: Request,
  deps: CompatibilityWeightsAdminDependencies,
): Promise<Response> {
  const startedAt = deps.now().getTime();
  const requestId = resolveRequestId(req);
  const logger = createLogger(requestId);
  try {
    if (req.method !== "POST") {
      throw new AppError("validation", 405, "POST is required for this endpoint.");
    }

    const user = await authenticateUser(req, deps.authClient);
    if (user.is_anonymous === true || user.app_metadata?.["astra_admin"] !== true) {
      throw new AppError("auth", 403, "Administrator access is required.");
    }
    const limit = deps.rateLimiter.check(user.id, deps.now().getTime());
    if (!limit.allowed) {
      return errorResponse(rateLimited(), requestId, {
        "Retry-After": String(limit.retryAfterSeconds),
      });
    }

    const raw = await req.json().catch(() => {
      throw badRequest("Request body must be valid JSON.");
    });
    if (!isRecord(raw) || !Object.hasOwn(raw, "body")) {
      throw badRequest('Request envelope is missing the required "body" field.');
    }
    const update = parseCompatibilityWeightUpdate(raw["body"]);
    const config = await deps.store.updateIfVersion(update.expectedVersion, update.weights);
    if (config === null) {
      throw new AppError(
        "validation",
        409,
        "Compatibility weights changed; reload before retrying.",
      );
    }
    logger.info("compatibility_weights.updated", {
      user_id: user.id,
      version: config.version,
      latency_ms: deps.now().getTime() - startedAt,
    });
    return jsonResponse(config, { requestId });
  } catch (err) {
    const appError = err instanceof AppError
      ? err
      : serverError("Couldn't update compatibility weights.");
    logger.warn("compatibility_weights.update_failed", {
      category: appError.category,
      status: appError.status,
      latency_ms: deps.now().getTime() - startedAt,
      error_name: err instanceof Error ? err.name : "unknown",
    });
    return errorResponse(appError, requestId);
  }
}
