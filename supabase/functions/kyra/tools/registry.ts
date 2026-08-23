// ============================================================================
// kyra/tools/registry.ts
// ============================================================================
// Assembles docs/06 §3's eleven-tool surface into one dispatch table the
// handler's orchestration loop consumes: the full definitions list (handed
// to the provider on every call) and a single `execute(name, args)` that
// routes to the right executor with its narrow deps.
//
// Every executor returns a JSON-serializable record and NEVER throws for a
// domain outcome (empty closet, unresolvable id, confirmation missing) —
// those come back as `{error: "..."}` results the model reads and relays in
// its own voice, per docs/06 §6's "a tool call fails" row. A THROWN error
// from an executor means infrastructure failed (database unreachable), and
// the loop in handler.ts owns the retry-once-then-degrade policy for that.
//
// An unknown tool name also returns a structured error rather than
// throwing: the model hallucinating a twelfth tool is a model defect the
// turn should survive, not a 500.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import {
  executeSearchCloset,
  parseSearchClosetArgs,
  searchClosetDefinition,
  type SearchClosetDeps,
} from "./searchCloset.ts";
import {
  executeRankOutfits,
  parseRankOutfitsArgs,
  rankOutfitsDefinition,
  type RankOutfitsDeps,
} from "./rankOutfits.ts";
import {
  createOutfitDefinition,
  type CreateOutfitDeps,
  executeCreateOutfit,
  parseCreateOutfitArgs,
} from "./createOutfit.ts";
import { executeGetWeather, getWeatherDefinition, type GetWeatherDeps } from "./getWeather.ts";
import { executeGetSchedule, getScheduleDefinition, type GetScheduleDeps } from "./getSchedule.ts";
import {
  executeSavePreference,
  savePreferenceDefinition,
  type SavePreferenceDeps,
} from "./savePreference.ts";
import {
  executeMarkItemWorn,
  markItemWornDefinition,
  type MarkItemWornDeps,
} from "./markItemWorn.ts";
import {
  createPackingListDefinition,
  type CreatePackingListDeps,
  executeCreatePackingList,
  parseCreatePackingListArgs,
} from "./createPackingList.ts";
import { executePhase6Stub, PHASE6_STUB_DEFINITIONS } from "./phase6Stubs.ts";

export interface ToolRegistryDeps {
  readonly searchCloset: SearchClosetDeps;
  readonly rankOutfits: RankOutfitsDeps;
  readonly createOutfit: CreateOutfitDeps;
  readonly getWeather: GetWeatherDeps;
  readonly getSchedule: GetScheduleDeps;
  readonly savePreference: SavePreferenceDeps;
  readonly markItemWorn: MarkItemWornDeps;
  readonly createPackingList: CreatePackingListDeps;
}

export interface ToolExecution {
  readonly name: string;
  readonly args: Record<string, unknown>;
  readonly result: Record<string, unknown>;
}

export interface ToolRegistry {
  readonly definitions: readonly StylistToolDefinition[];
  execute(name: string, args: Record<string, unknown>): Promise<Record<string, unknown>>;
}

export function buildToolRegistry(deps: ToolRegistryDeps): ToolRegistry {
  const definitions: StylistToolDefinition[] = [
    searchClosetDefinition,
    rankOutfitsDefinition,
    createOutfitDefinition,
    getWeatherDefinition,
    getScheduleDefinition,
    savePreferenceDefinition,
    markItemWornDefinition,
    createPackingListDefinition,
    ...PHASE6_STUB_DEFINITIONS,
  ];

  const stubNames = new Set(PHASE6_STUB_DEFINITIONS.map((definition) => definition.name));

  return {
    definitions,
    async execute(name, args) {
      switch (name) {
        case "search_closet":
          return await executeSearchCloset(parseSearchClosetArgs(args), deps.searchCloset);
        case "rank_outfits":
          return await executeRankOutfits(parseRankOutfitsArgs(args), deps.rankOutfits);
        case "create_outfit":
          return await executeCreateOutfit(parseCreateOutfitArgs(args), deps.createOutfit);
        case "get_weather":
          return executeGetWeather(args, deps.getWeather);
        case "get_schedule":
          return await executeGetSchedule(args, deps.getSchedule);
        case "save_preference":
          return await executeSavePreference(args, deps.savePreference);
        case "mark_item_worn":
          return await executeMarkItemWorn(args, deps.markItemWorn);
        case "create_packing_list":
          return await executeCreatePackingList(
            parseCreatePackingListArgs(args),
            deps.createPackingList,
          );
        default:
          if (stubNames.has(name)) {
            return executePhase6Stub(name);
          }
          return {
            error: "UNKNOWN_TOOL",
            detail: `No tool named "${name}" exists. Use only the declared tools.`,
          };
      }
    },
  };
}
