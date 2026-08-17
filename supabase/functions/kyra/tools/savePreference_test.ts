import { assert, assertEquals } from "@std/assert";
import {
  executeSavePreference,
  type ExistingMemoryRow,
  isContradictory,
  jaccardSimilarity,
  normalizedTokens,
  type SavePreferenceDeps,
} from "./savePreference.ts";

const SOURCE_MESSAGE = "99999999-0000-4000-8000-000000000001";
const NEW_MEMORY = "88888888-0000-4000-8000-000000000001";

interface Recorded {
  inserted: Array<
    { memoryType: string; content: string; confidence: number; sourceMessageId: string }
  >;
  updated: Array<{ id: string; confidence: number }>;
  deleted: string[];
}

function deps(
  existing: ExistingMemoryRow[],
  recorded: Recorded,
  minimumConfidence = 0.7,
): SavePreferenceDeps {
  return {
    sourceMessageId: SOURCE_MESSAGE,
    minimumConfidence,
    listMemoriesByType: () => Promise.resolve(existing),
    insertMemory: (record) => {
      recorded.inserted.push(record);
      return Promise.resolve(NEW_MEMORY);
    },
    updateMemoryConfidence: (id, confidence) => {
      recorded.updated.push({ id, confidence });
      return Promise.resolve();
    },
    deleteMemory: (id) => {
      recorded.deleted.push(id);
      return Promise.resolve();
    },
  };
}

function emptyRecorded(): Recorded {
  return { inserted: [], updated: [], deleted: [] };
}

Deno.test("§5.2: below the confidence floor is discarded, never stored quietly", async () => {
  const recorded = emptyRecorded();
  const result = await executeSavePreference(
    {
      memory_type: "dislike",
      content: "Doesn't love this specific jacket",
      confidence: 0.4,
      source_message_id: SOURCE_MESSAGE,
    },
    deps([], recorded),
  );
  assertEquals(result["action_taken"], "below_threshold_discarded");
  assertEquals(result["memory_id"], null);
  assertEquals(recorded.inserted.length, 0);
});

Deno.test("an explicit high-confidence preference is created, with the SERVER's source id", async () => {
  const recorded = emptyRecorded();
  const result = await executeSavePreference(
    {
      memory_type: "fit_note",
      content: "Slim fits don't work through the chest; keep shirts relaxed there",
      confidence: 0.85,
      // The model's claimed provenance is ignored on purpose:
      source_message_id: "00000000-0000-4000-8000-00000000beef",
    },
    deps([], recorded),
  );
  assertEquals(result["action_taken"], "created");
  assertEquals(result["memory_id"], NEW_MEMORY);
  assertEquals(recorded.inserted[0]?.sourceMessageId, SOURCE_MESSAGE);
});

Deno.test("§5.3.2: a restatement updates the existing row with a recency-biased merge", async () => {
  const recorded = emptyRecorded();
  const existing: ExistingMemoryRow = {
    id: "77777777-0000-4000-8000-000000000001",
    memory_type: "fit_note",
    content: "Slim fits don't work through the chest, keep shirts relaxed",
    confidence: 0.7,
  };
  const result = await executeSavePreference(
    {
      memory_type: "fit_note",
      content: "slim fits don't work through the chest — keep shirts relaxed",
      confidence: 0.9,
      source_message_id: SOURCE_MESSAGE,
    },
    deps([existing], recorded),
  );
  assertEquals(result["action_taken"], "updated_existing");
  assertEquals(result["memory_id"], existing.id);
  // 0.6×0.9 + 0.4×0.7 = 0.82
  assertEquals(recorded.updated[0]?.confidence, 0.82);
  assertEquals(recorded.inserted.length, 0);
});

Deno.test("§5.3.3: a contradiction supersedes — surfaced, never silently overwritten", async () => {
  const recorded = emptyRecorded();
  const existing: ExistingMemoryRow = {
    id: "77777777-0000-4000-8000-000000000002",
    memory_type: "preference",
    content: "Prefers slim fit shirts",
    confidence: 0.8,
  };
  const result = await executeSavePreference(
    {
      memory_type: "preference",
      content: "Prefers relaxed fit shirts now",
      confidence: 0.85,
      source_message_id: SOURCE_MESSAGE,
    },
    deps([existing], recorded),
  );
  assertEquals(result["action_taken"], "superseded_conflict");
  assertEquals(result["supersedes_memory_id"], existing.id);
  assertEquals(result["superseded_content"], "Prefers slim fit shirts");
  assertEquals(recorded.deleted, [existing.id]);
  assertEquals(recorded.inserted.length, 1);
});

Deno.test("an unrelated memory of the same type is simply created", async () => {
  const recorded = emptyRecorded();
  const existing: ExistingMemoryRow = {
    id: "77777777-0000-4000-8000-000000000003",
    memory_type: "preference",
    content: "Prefers olive and earth tones",
    confidence: 0.8,
  };
  const result = await executeSavePreference(
    {
      memory_type: "preference",
      content: "Bikes to work, needs trousers that move",
      confidence: 0.8,
      source_message_id: SOURCE_MESSAGE,
    },
    deps([existing], recorded),
  );
  assertEquals(result["action_taken"], "created");
  assertEquals(recorded.deleted.length, 0);
  assertEquals(recorded.updated.length, 0);
});

Deno.test("sensitive-trait content is refused at the write", async () => {
  const recorded = emptyRecorded();
  const result = await executeSavePreference(
    {
      memory_type: "general",
      content: "He is probably muslim so avoid certain cuts",
      confidence: 0.9,
      source_message_id: SOURCE_MESSAGE,
    },
    deps([], recorded),
  );
  assertEquals(result["error"], "GUARDRAIL_SENSITIVE_TRAIT");
  assertEquals(recorded.inserted.length, 0);
});

Deno.test("invalid model arguments are a structured error, not a throw", async () => {
  const recorded = emptyRecorded();
  const result = await executeSavePreference(
    { memory_type: "fit_preference", content: "x", confidence: 0.9 }, // docs/06 enum, not the DB enum
    deps([], recorded),
  );
  assertEquals(result["error"], "INVALID_ARGUMENTS");
});

Deno.test("similarity + contradiction helpers behave on the axes memories move along", () => {
  assert(isContradictory("Prefers slim fit shirts", "Prefers relaxed fit shirts"));
  assert(isContradictory("Likes bold patterns", "Dislikes bold patterns"));
  assert(!isContradictory("Prefers olive tones", "Bikes to work daily"));
  const a = normalizedTokens("Prefers slim fit shirts");
  const b = normalizedTokens("Prefers slim fitting shirts");
  assert(jaccardSimilarity(a, b) > 0.4);
});
