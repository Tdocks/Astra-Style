import { assert, assertEquals } from "@std/assert";
import {
  buildContextPacket,
  type ContextPacketInput,
  estimateTokens,
  type PacketClosetItemRow,
  selectClosetItems,
} from "./contextPacket.ts";

const NOW = new Date("2026-08-16T09:00:00Z");

function closetItem(overrides: Partial<PacketClosetItemRow> & { id: string }): PacketClosetItemRow {
  return {
    category: "top",
    subcategory: "knit polo",
    brand: null,
    primary_color: "olive",
    formality_score: 40,
    fit: "regular",
    availability_state: "available",
    laundry_state: "clean",
    wear_count: 3,
    last_worn_at: "2026-08-01T00:00:00Z",
    ...overrides,
  };
}

function baseInput(overrides: Partial<ContextPacketInput> = {}): ContextPacketInput {
  return {
    now: NOW,
    requestText: "What should I wear tonight?",
    attachments: [],
    styleProfile: {
      primary_identity: "smart_casual",
      secondary_identities: ["minimalist"],
      preferred_colors: ["olive", "navy"],
      avoided_colors: ["orange"],
      preferred_fit: "regular",
      formality_preference: "smart_casual",
      logo_tolerance: 20,
      trend_tolerance: 40,
    },
    bodyProfile: {
      fit_notes: ["broad_chest"],
      shirt_size: "L",
      trouser_size: "34x32",
      shoe_size: "10.5",
    },
    lifestyleProfile: {
      monthly_budget: 250,
      currency: "USD",
      sustainability_preference: null,
    },
    weather: { temperatureHigh: 22, temperatureLow: 15, condition: "partly_cloudy" },
    occasions: [],
    closetItems: [],
    recentFeedback: [],
    memories: [],
    ...overrides,
  };
}

function bigCloset(count: number): PacketClosetItemRow[] {
  const categories = ["top", "bottom", "shoes", "outerwear", "accessory"];
  return Array.from({ length: count }, (_, i) =>
    closetItem({
      id: `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
      category: categories[i % categories.length]!,
      subcategory: `piece number ${i} with a fairly long descriptive subcategory name`,
      last_worn_at: i % 7 === 0 ? null : `2026-0${(i % 7) + 1}-01T00:00:00Z`,
    }));
}

Deno.test("packet stays inside the 4000-token budget regardless of closet size", () => {
  // P5-KYRA-03 acceptance: bounded regardless of closet size.
  const result = buildContextPacket(baseInput({ closetItems: bigCloset(400) }));
  assert(estimateTokens(result.packet) <= 4_000);
  assertEquals(result.overflowed, false);
});

Deno.test("truncation_applied is always present, empty when nothing was cut", () => {
  const result = buildContextPacket(baseInput({ closetItems: bigCloset(5) }));
  assertEquals(result.packet["truncation_applied"], []);
  assertEquals(result.truncationApplied.length, 0);
});

Deno.test("truncation follows §1.3's order: memories, feedback, occasions, then closet K", () => {
  const memories = Array.from({ length: 12 }, (_, i) => ({
    id: `10000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    memory_type: "preference",
    content:
      `A deliberately long durable memory number ${i} describing a nuanced styling preference ` +
      "in enough words that the packet assembly has real weight to carry per entry.",
    confidence: 0.9 - i * 0.01,
  }));
  const feedback = Array.from({ length: 8 }, (_, i) => ({
    target_type: "closet_item",
    target_id: `20000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    signal: "dislike",
    reason_tags: ["wrong_color", "poor_fit", "not_my_style"],
    created_at: `2026-08-${String(15 - i).padStart(2, "0")}T00:00:00Z`,
  }));
  const occasions = Array.from({ length: 5 }, (_, i) => ({
    id: `30000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    title: `Occasion ${i} with a long descriptive name to occupy budget meaningfully`,
    starts_at: new Date(NOW.getTime() + (i + 1) * 86_400_000).toISOString(),
    dress_code: "smart_casual",
    location: "A venue with a long address line to weigh the entry down further",
  }));

  const result = buildContextPacket(baseInput({
    closetItems: bigCloset(400),
    memories,
    recentFeedback: feedback,
    occasions,
  }));

  assert(estimateTokens(result.packet) <= 4_000);
  const order = result.truncationApplied;
  // Whatever subset of steps ran, it ran in the documented order.
  const expectedSequence = [
    "durable_memories_truncated_to_5",
    "recent_feedback_truncated_to_5",
    "occasions_truncated_to_3",
  ];
  const observedPrefix = order.filter((label) => expectedSequence.includes(label));
  assertEquals(observedPrefix, expectedSequence.slice(0, observedPrefix.length));
  // Step 1 must have fired before any closet reduction appears.
  const closetSteps = order.filter((label) => label.startsWith("closet_items_reduced"));
  if (closetSteps.length > 0) {
    assert(order.indexOf("durable_memories_truncated_to_5") < order.indexOf(closetSteps[0]!));
  }
  const memoriesInPacket = result.packet["durable_memories"] as unknown[];
  assert(memoriesInPacket.length <= 5);
});

Deno.test("never-truncated sections survive even a floor packet", () => {
  const result = buildContextPacket(baseInput({
    requestText: "Pack me for a two-week trip with several formal dinners and hiking days",
    closetItems: bigCloset(400),
  }));
  const packet = result.packet;
  const task = packet["requested_task"] as Record<string, unknown>;
  assertEquals(
    task["raw_text"],
    "Pack me for a two-week trip with several formal dinners and hiking days",
  );
  const weather = packet["weather"] as Record<string, unknown>;
  assertEquals(weather["available"], true);
  const body = packet["body_fit_profile"] as Record<string, unknown>;
  assertEquals(body["fit_notes"], ["broad_chest"]);
  const budget = packet["budget_constraints"] as Record<string, unknown>;
  assertEquals(budget["monthly_budget"], 250);
});

Deno.test("weather absent is {available: false}, never an invented reading", () => {
  const result = buildContextPacket(baseInput({ weather: null }));
  assertEquals(result.packet["weather"], { available: false });
});

Deno.test("occasions outside the 14-day window are excluded; soonest-first cap of 5", () => {
  const mk = (i: number, daysOut: number) => ({
    id: `40000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    title: `Occasion ${i}`,
    starts_at: new Date(NOW.getTime() + daysOut * 86_400_000).toISOString(),
    dress_code: null,
    location: null,
  });
  const result = buildContextPacket(baseInput({
    occasions: [mk(1, 20), mk(2, 3), mk(3, 1), mk(4, 10), mk(5, -1), mk(6, 5), mk(7, 6), mk(8, 7)],
  }));
  const occasions = result.packet["occasions"] as Array<Record<string, unknown>>;
  assertEquals(occasions.length, 5);
  assertEquals(occasions[0]?.["title"], "Occasion 3"); // soonest first
  assert(!occasions.some((occasion) => occasion["title"] === "Occasion 1")); // 20 days out
  assert(!occasions.some((occasion) => occasion["title"] === "Occasion 5")); // past
});

Deno.test("closetItemIds reports exactly the packet's items", () => {
  const items = bigCloset(10);
  const result = buildContextPacket(baseInput({ closetItems: items }));
  const packetItems = result.packet["closet_items"] as Array<Record<string, unknown>>;
  assertEquals(result.closetItemIds.size, packetItems.length);
  for (const item of packetItems) {
    assert(result.closetItemIds.has(item["id"] as string));
  }
});

// ---------------------------------------------------------------------------
// selectClosetItems retrieval behavior (§1.5, as implementable today)
// ---------------------------------------------------------------------------

Deno.test("selectClosetItems filters unavailable items — and inverts for laundry queries", () => {
  const items = [
    closetItem({ id: "50000000-0000-4000-8000-000000000001", laundry_state: "laundry" }),
    closetItem({ id: "50000000-0000-4000-8000-000000000002" }),
    closetItem({
      id: "50000000-0000-4000-8000-000000000003",
      availability_state: "unavailable",
    }),
  ];
  const normal = selectClosetItems(items, "what should I wear", 10);
  assertEquals(normal.map((item) => item.id), ["50000000-0000-4000-8000-000000000002"]);

  const laundry = selectClosetItems(items, "what's in the laundry right now", 10);
  assertEquals(laundry.length, 2);
  assert(!laundry.some((item) => item.id === "50000000-0000-4000-8000-000000000002"));
});

Deno.test("selectClosetItems guarantees three items per essential category when owned", () => {
  const items: PacketClosetItemRow[] = [];
  for (let i = 0; i < 30; i++) {
    items.push(closetItem({
      id: `60000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
      category: "top",
      subcategory: "wedding shirt", // keyword-relevant: crowds the ranking
    }));
  }
  for (let i = 0; i < 4; i++) {
    items.push(closetItem({
      id: `61000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
      category: i < 2 ? "bottom" : "shoes",
      subcategory: "plain",
    }));
  }
  const selected = selectClosetItems(items, "something for a wedding shirt occasion", 12);
  const bottoms = selected.filter((item) => item.category === "bottom").length;
  const shoes = selected.filter((item) => item.category === "shoes").length;
  assertEquals(bottoms, 2); // only two owned; floor cannot invent a third
  assertEquals(shoes, 2);
});

Deno.test("selectClosetItems prefers least-recently-worn among equally relevant", () => {
  const items = [
    closetItem({
      id: "70000000-0000-4000-8000-000000000001",
      last_worn_at: "2026-08-15T00:00:00Z",
    }),
    closetItem({ id: "70000000-0000-4000-8000-000000000002", last_worn_at: null }),
    closetItem({
      id: "70000000-0000-4000-8000-000000000003",
      last_worn_at: "2026-07-01T00:00:00Z",
    }),
  ];
  const selected = selectClosetItems(items, "anything", 2);
  assertEquals(selected.map((item) => item.id), [
    "70000000-0000-4000-8000-000000000002",
    "70000000-0000-4000-8000-000000000003",
  ]);
});
