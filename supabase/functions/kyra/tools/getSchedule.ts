// ============================================================================
// kyra/tools/getSchedule.ts
// ============================================================================
// The `get_schedule` tool (P5-KYRA-08, docs/06 §3.7), backed by the
// `occasions` table — manually created occasions today, with EventKit-synced
// rows arriving through the same table when the client ships that path
// (`occasions.source = 'calendar_sync'`), so this tool needs no change for
// it. RLS scopes the query to the caller.
//
// An empty schedule is a normal result (`{available: true, occasions: []}`),
// not an error — P5-KYRA-08's acceptance criterion says so explicitly. The
// §3.7 CALENDAR_PERMISSION_NOT_GRANTED error belongs to the future
// EventKit-backed path; the server cannot see device permission state and
// does not pretend to.
// ============================================================================

import type { StylistToolDefinition } from "../../_shared/providers/stylistReasoning.ts";
import type { OccasionSourceRow } from "../contextPacket.ts";

export interface GetScheduleDeps {
  /** Occasions with `starts_at` in [fromIso, toIso], soonest first. */
  listOccasions(fromIso: string, toIso: string): Promise<OccasionSourceRow[]>;
  readonly now: () => Date;
}

const DEFAULT_RANGE_DAYS = 7;
const MAX_RANGE_DAYS = 30;

export const getScheduleDefinition: StylistToolDefinition = {
  name: "get_schedule",
  description:
    "Fetch the user's upcoming occasions (manually added or calendar-derived) within a date " +
    "range. Read-only.",
  parametersSchema: {
    type: "object",
    properties: {
      date_range_days: { type: "integer", default: DEFAULT_RANGE_DAYS, maximum: MAX_RANGE_DAYS },
    },
  },
};

export async function executeGetSchedule(
  args: Record<string, unknown>,
  deps: GetScheduleDeps,
): Promise<Record<string, unknown>> {
  const rawDays = args["date_range_days"];
  const days = typeof rawDays === "number" && Number.isInteger(rawDays)
    ? Math.min(MAX_RANGE_DAYS, Math.max(1, rawDays))
    : DEFAULT_RANGE_DAYS;

  const from = deps.now();
  const to = new Date(from.getTime() + days * 86_400_000);
  const occasions = await deps.listOccasions(from.toISOString(), to.toISOString());

  return {
    available: true,
    occasions: occasions.map((occasion) => ({
      id: occasion.id,
      title: occasion.title,
      starts_at: occasion.starts_at,
      dress_code: occasion.dress_code,
      location: occasion.location,
    })),
  };
}
