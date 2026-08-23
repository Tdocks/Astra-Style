// ============================================================================
// kyra/tools/createPackingList.ts
// ============================================================================
// Real `create_packing_list` (P7-HOME-04 / docs/06 §3.11). Pinned input
// schema from P5-KYRA-11: destination, start_date, end_date required;
// luggage enum `carry_on` / `checked` / `none`. Those values map onto
// packing's `carry_on_only` / `checked_bag` / `no_constraint` internally.
// The plan is `buildPlan` — same engine as POST /packing/generate.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import { AppError } from "../../_shared/errors.ts";
import { buildPlan, type BuildPlanDeps } from "../../packing/plan.ts";
import { parseGeneratePackingBody, planDates } from "../../packing/schema.ts";

export interface CreatePackingListArgs {
  readonly destination: string;
  readonly startDate: string;
  readonly endDate: string;
  readonly activities: readonly string[];
  readonly dressCodes: readonly string[];
  readonly laundryAccess: boolean;
  readonly luggageConstraint: "carry_on" | "checked" | "none";
}

export interface CreatePackingListDeps extends BuildPlanDeps {
  readonly userId: string;
}

export const createPackingListDefinition: StylistToolDefinition = {
  name: "create_packing_list",
  description:
    "Generate and persist a packing list, daily outfit plan, and rewear map for a trip, " +
    "from the user's closet. Returns the real plan (item ids, daily outfits, missing " +
    "essentials, weather note). Never invent a list if generation fails.",
  parametersSchema: {
    type: "object",
    properties: {
      destination: { type: "string" },
      start_date: { type: "string", format: "date" },
      end_date: { type: "string", format: "date" },
      activities: { type: "array", items: { type: "string" } },
      dress_codes: { type: "array", items: { type: "string" } },
      laundry_access: { type: "boolean", default: false },
      luggage_constraint: {
        type: "string",
        enum: ["carry_on", "checked", "none"],
        default: "none",
      },
    },
    required: ["destination", "start_date", "end_date"],
  },
};

const PINNED_LUGGAGE = new Set(["carry_on", "checked", "none"]);

export function mapKyraLuggage(
  value: unknown,
): "carry_on_only" | "checked_bag" | "no_constraint" {
  if (value === "carry_on") return "carry_on_only";
  if (value === "checked") return "checked_bag";
  return "no_constraint";
}

export function parseCreatePackingListArgs(raw: Record<string, unknown>): CreatePackingListArgs {
  const destination = typeof raw["destination"] === "string" ? raw["destination"].trim() : "";
  const startDate = typeof raw["start_date"] === "string" ? raw["start_date"] : "";
  const endDate = typeof raw["end_date"] === "string" ? raw["end_date"] : "";
  const activities = Array.isArray(raw["activities"])
    ? raw["activities"].filter((item): item is string => typeof item === "string")
    : [];
  const dressCodes = Array.isArray(raw["dress_codes"])
    ? raw["dress_codes"].filter((item): item is string => typeof item === "string")
    : [];
  const laundryAccess = raw["laundry_access"] === true;
  const luggageRaw = raw["luggage_constraint"];
  const luggageConstraint: CreatePackingListArgs["luggageConstraint"] =
    typeof luggageRaw === "string" && PINNED_LUGGAGE.has(luggageRaw)
      ? luggageRaw as CreatePackingListArgs["luggageConstraint"]
      : "none";
  return {
    destination,
    startDate,
    endDate,
    activities,
    dressCodes,
    laundryAccess,
    luggageConstraint,
  };
}

export async function executeCreatePackingList(
  args: CreatePackingListArgs,
  deps: CreatePackingListDeps,
): Promise<Record<string, unknown>> {
  if (args.destination.length === 0) {
    return { error: "VALIDATION", detail: "destination is required." };
  }

  try {
    const body = parseGeneratePackingBody({
      destination: args.destination,
      start_date: args.startDate,
      end_date: args.endDate,
      activities: args.activities,
      dress_codes: args.dressCodes,
      luggage_constraint: mapKyraLuggage(args.luggageConstraint),
      has_laundry_access: args.laundryAccess,
      regenerate: true,
    });
    const dates = planDates(body.startDate, body.endDate);
    const plan = await buildPlan(deps.userId, body, dates, deps);
    return {
      available: true,
      packing_list_item_ids: plan.packing_list_item_ids,
      daily_outfit_plan: plan.daily_outfit_plan,
      missing_essentials: plan.missing_essentials,
      weather_contingency_note: plan.weather_contingency_note,
    };
  } catch (err) {
    if (err instanceof AppError) {
      const error = err.category === "validation"
        ? "DATE_RANGE_INVALID"
        : err.category.toUpperCase();
      return { error, detail: err.message };
    }
    throw err;
  }
}
