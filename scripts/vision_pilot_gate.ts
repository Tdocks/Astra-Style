#!/usr/bin/env -S deno run --allow-net --allow-read --allow-env
// ============================================================================
// scripts/vision_pilot_gate.ts — the docs/08 §2.5 pilot gate, as a runnable
// ============================================================================
// §2.5 makes the vendor choice conditional: "run GPT-5.6 Luna against a labeled
// sample of real (consented) user-scan photos and confirm subcategory-granularity
// accuracy is acceptable. If it isn't, Terra becomes the *default* tier." That
// sentence has been in the document since 2026-07-28 and nothing could execute
// it, so the gate stayed a paragraph. This is the executable form.
//
// It runs the REAL adapter — `OpenAIVisionAnalysisProvider`, unmodified, the
// same class `closet/index.ts` constructs — so what is measured is what ships.
// The only substitution is the storage loader, which reads from disk instead of
// Supabase Storage.
//
// ── What it measures, and why the third one exists ──────────────────────────
//
//   accuracy    per-field agreement with the manifest's ground truth
//   latency     p50/p95 of the server leg, against §2.4's ≤5.5s p50 budget
//   stability   how often repeated runs of the SAME photo disagree
//
// Stability is not in §2.5, and it needs to be. The adapter cannot send
// `temperature` — gpt-5.6-luna rejects any value but the default (see §2.5.2) —
// so every reading is drawn at the model's own sampling temperature and the
// same photograph does not produce the same answer twice. Observed on the first
// real photograph: formality 35 / 38 / 45 across three runs, subcategory
// "short-sleeve camp-collar shirt" / "short-sleeve casual button-up shirt".
// An accuracy figure from one pass over a sample is therefore a sample of a
// distribution, not a measurement, and a bar stated over one pass can be
// cleared or missed by luck. Hence `--repetitions`, defaulting to 3.
//
// ── Usage ───────────────────────────────────────────────────────────────────
//
//   export OPENAI_API_KEY=...        # or VISION_PROVIDER_API_KEY
//   deno run --allow-net --allow-read --allow-env scripts/vision_pilot_gate.ts \
//     --manifest fixtures/vision-pilot/manifest.jsonl \
//     --repetitions 3
//
// Exits 0 if every bar in `BARS` is cleared, 1 if any is missed, 2 on a usage
// or configuration error. A run that cannot reach the vendor exits 2, never 1 —
// "the gate failed" and "the gate did not run" must not look the same.
// ============================================================================

import { OpenAIVisionAnalysisProvider } from "../supabase/functions/_shared/providers/openaiVisionAnalysis.ts";
import type { GarmentAnalysisResult } from "../supabase/functions/_shared/providers/visionAnalysis.ts";
import { mapProviderResultToWire } from "../supabase/functions/closet/mapper.ts";

// ── The bar ─────────────────────────────────────────────────────────────────
//
// §2.5 says explicitly that the bar "is a product decision to set before the
// pilot runs, not defined by this document". These are a PROPOSAL, recorded
// here so that changing them is a visible commit rather than an argument after
// the numbers are in. `docs/08` §2.5.3 carries the reasoning for each.
//
// They are not uniform, and the asymmetry is the point: a wrong category sends
// a garment to the wrong rail and breaks outfit generation, while a wrong
// material is a line of text on a detail screen. The fields are weighted by
// what a mistake in each one costs the user.

interface Bar {
  readonly field: string;
  readonly minimum: number;
  readonly why: string;
}

const BARS: readonly Bar[] = [
  {
    field: "category",
    minimum: 0.98,
    why:
      "A wrong category is not a wrong label, it is a garment in the wrong rail " +
      "and excluded from every outfit its role should fill. Seven values, a " +
      "closed enum, and the on-device hint as a fallback: near-perfect or the " +
      "pipeline is broken somewhere else.",
  },
  {
    field: "subcategory",
    minimum: 0.80,
    why:
      "§2.5's own named risk — 'knit polo vs. piqué polo vs. performance polo'. " +
      "Scored by keyword recall rather than string equality, because the useful " +
      "question is whether the distinguishing words are present, not whether the " +
      "model phrased it the way the labeller did.",
  },
  {
    field: "primaryColor",
    minimum: 0.90,
    why:
      "Feeds the §10 colour subscore at 25% weight, the heaviest term in the " +
      "engine. Scored on the head noun (`resolveColorName`'s own rule), so " +
      "'dark brown' and 'brown' agree and 'brown' and 'olive' do not.",
  },
  {
    field: "pattern",
    minimum: 0.85,
    why:
      "Six values, and the genuinely ambiguous pairs (solid vs texture-only on " +
      "a chenille shirt) are handled by letting the manifest list more than one " +
      "acceptable answer rather than by lowering the bar.",
  },
  {
    field: "formality",
    minimum: 0.85,
    why:
      "Within ±15 of the labelled value on the 0-100 scale — one rung of §3's " +
      "anchor table either way. §10's formality subscore treats a 15-point gap " +
      "as barely felt and a 40-point gap as disqualifying, so ±15 is the " +
      "tolerance the engine itself already implies.",
  },
];

/** §2.4. Stated as p50 because that is how §2.4 states it. */
const LATENCY_P50_BUDGET_MS = 5_500;

/**
 * How often two runs of the same photograph may disagree on a scored field.
 *
 * No prior art in the docs — this is a first proposal. 15% is set at the level
 * where a user rescanning a garment he was unhappy with has a real chance of a
 * different answer, without demanding a determinism the API cannot give.
 */
const MAX_DISAGREEMENT_RATE = 0.15;

// ── Manifest ────────────────────────────────────────────────────────────────

interface TruthEntry {
  readonly image: string;
  readonly note?: string;
  readonly category: string;
  /** Words that must ALL appear somewhere in the returned subcategory. */
  readonly subcategoryKeywords: readonly string[];
  /** Head nouns, any of which counts as right. */
  readonly primaryColor: readonly string[];
  readonly pattern: readonly string[];
  readonly formality: number;
}

function parseManifest(text: string, base: string): TruthEntry[] {
  const entries: TruthEntry[] = [];
  for (const [index, line] of text.split("\n").entries()) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.startsWith("//")) continue;
    let parsed: TruthEntry;
    try {
      parsed = JSON.parse(trimmed) as TruthEntry;
    } catch (error) {
      throw new Error(
        `manifest line ${index + 1} is not valid JSON: ${String(error)}`,
      );
    }
    entries.push({ ...parsed, image: new URL(parsed.image, base).pathname });
  }
  return entries;
}

// ── Scoring ─────────────────────────────────────────────────────────────────

/**
 * `resolveColorName`'s rule, deliberately duplicated rather than imported.
 *
 * That function returns LCh; the question here is only whether two colour
 * *words* name the same family, and importing it would make this gate score
 * agreement through a vocabulary table that a colour outside the 58 words
 * silently falls out of. The gate should be able to mark a correct answer
 * correct even for a colour the scorer cannot yet resolve.
 */
function headNoun(raw: string): string {
  const words = raw.trim().toLowerCase().split(/\s+/);
  return words[words.length - 1] ?? "";
}

type FieldName = (typeof BARS)[number]["field"];

/** What the model actually said, so a failure is diagnosable without a rerun. */
function observedValues(
  result: GarmentAnalysisResult,
): Record<FieldName, string> {
  const wire = mapProviderResultToWire(result, {});
  return {
    category: wire.category.value,
    subcategory: wire.subcategory?.value ?? "(none)",
    primaryColor: wire.primary_color?.value ?? "(none)",
    pattern: wire.pattern?.value ?? "(none)",
    formality: String(wire.formality_score?.value ?? "(none)"),
  };
}

function scoreOne(
  result: GarmentAnalysisResult,
  truth: TruthEntry,
): Record<FieldName, boolean> {
  const wire = mapProviderResultToWire(result, {});
  const subcategory = wire.subcategory?.value.toLowerCase() ?? "";

  return {
    category: wire.category.value === truth.category,
    subcategory: truth.subcategoryKeywords.every((k) =>
      subcategory.includes(k.toLowerCase())
    ),
    primaryColor: wire.primary_color
      ? truth.primaryColor.some((c) =>
        headNoun(c) === headNoun(wire.primary_color!.value)
      )
      : false,
    pattern: wire.pattern ? truth.pattern.includes(wire.pattern.value) : false,
    formality: wire.formality_score
      ? Math.abs(wire.formality_score.value - truth.formality) <= 15
      : false,
  };
}

function percentile(sorted: readonly number[], p: number): number {
  if (sorted.length === 0) return NaN;
  // Nearest-rank. With the sample sizes a hand-labelled pilot produces,
  // interpolating between two observations invents precision that is not there.
  const rank = Math.ceil((p / 100) * sorted.length);
  return sorted[Math.min(sorted.length, Math.max(1, rank)) - 1]!;
}

// ── Runner ──────────────────────────────────────────────────────────────────

interface Observation {
  readonly image: string;
  readonly repetition: number;
  readonly elapsedMs: number;
  readonly scores: Record<FieldName, boolean>;
  readonly values: Record<FieldName, string>;
  readonly subcategory: string;
}

async function main(): Promise<number> {
  const args = new Map<string, string>();
  for (let i = 0; i < Deno.args.length; i += 2) {
    args.set(Deno.args[i]!.replace(/^--/, ""), Deno.args[i + 1] ?? "");
  }

  const manifestPath = args.get("manifest");
  if (!manifestPath) {
    console.error(
      "usage: vision_pilot_gate.ts --manifest <path.jsonl> [--repetitions N]",
    );
    return 2;
  }
  const repetitions = Number.parseInt(args.get("repetitions") ?? "3", 10);
  if (!Number.isFinite(repetitions) || repetitions < 1) {
    console.error("--repetitions must be a positive integer");
    return 2;
  }

  const apiKey = Deno.env.get("VISION_PROVIDER_API_KEY") ??
    Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    console.error(
      "set VISION_PROVIDER_API_KEY (or OPENAI_API_KEY) — the gate cannot run offline",
    );
    return 2;
  }

  const manifestUrl = new URL(manifestPath, `file://${Deno.cwd()}/`);
  const entries = parseManifest(
    await Deno.readTextFile(manifestUrl),
    manifestUrl.href,
  );
  if (entries.length === 0) {
    console.error(
      "manifest is empty — a gate over zero photographs passes vacuously",
    );
    return 2;
  }

  const provider = new OpenAIVisionAnalysisProvider({
    apiKey,
    model: Deno.env.get("VISION_PROVIDER_MODEL") ?? "gpt-5.6-luna",
    loadImageBytes: (path: string) => Deno.readFile(path),
  });

  const observations: Observation[] = [];
  for (const entry of entries) {
    for (let rep = 1; rep <= repetitions; rep++) {
      const started = performance.now();
      let result: GarmentAnalysisResult;
      try {
        result = await provider.analyzeGarment({
          imageStoragePath: entry.image,
        }, {
          requestId: `pilot-gate-${rep}`,
          userId: "00000000-0000-0000-0000-000000000000",
          timeoutMs: 60_000,
          // Deliberately unique per repetition. Reusing one key would let the
          // vendor serve a cached response and turn the stability measurement
          // into a measurement of the vendor's cache.
          idempotencyKey: `pilot-gate-${entry.image}-${rep}`,
        });
      } catch (error) {
        console.error(
          `CANNOT RUN: ${entry.image} rep ${rep}: ${String(error)}`,
        );
        return 2;
      }
      const elapsedMs = performance.now() - started;
      observations.push({
        image: entry.image,
        repetition: rep,
        elapsedMs,
        scores: scoreOne(result, entry),
        values: observedValues(result),
        subcategory: mapProviderResultToWire(result, {}).subcategory?.value ??
          "",
      });
      console.error(
        `  ${entry.image.split("/").pop()} rep ${rep}: ${
          Math.round(elapsedMs)
        }ms`,
      );
    }
  }

  // ── Report ────────────────────────────────────────────────────────────────
  let failed = false;
  console.log(
    `\nPILOT GATE — ${entries.length} photo(s) × ${repetitions} repetition(s)\n`,
  );

  console.log("ACCURACY");
  for (const bar of BARS) {
    const passes = observations.filter((o) => o.scores[bar.field]).length;
    const rate = passes / observations.length;
    const ok = rate >= bar.minimum;
    if (!ok) failed = true;
    console.log(
      `  ${ok ? "PASS" : "FAIL"}  ${bar.field.padEnd(14)} ${
        (rate * 100).toFixed(1)
      }%` +
        `  (bar ${(bar.minimum * 100).toFixed(0)}%)`,
    );
    // Print what was actually said on every miss. A bare percentage tells you
    // the gate failed; it does not tell you whether the model was confused or
    // the label was wrong, and those need opposite responses.
    if (!ok) {
      for (const o of observations.filter((x) => !x.scores[bar.field])) {
        console.log(
          `          ↳ ${o.image.split("/").pop()} rep ${o.repetition}: ` +
            `"${o.values[bar.field]}"`,
        );
      }
    }
  }

  const latencies = observations.map((o) => o.elapsedMs).sort((a, b) => a - b);
  const p50 = percentile(latencies, 50);
  const p95 = percentile(latencies, 95);
  const latencyOk = p50 <= LATENCY_P50_BUDGET_MS;
  if (!latencyOk) failed = true;
  console.log(`\nLATENCY (§2.4 budget: p50 ≤ ${LATENCY_P50_BUDGET_MS}ms)`);
  console.log(
    `  ${latencyOk ? "PASS" : "FAIL"}  p50 ${Math.round(p50)}ms   p95 ${
      Math.round(p95)
    }ms   ` +
      `min ${Math.round(latencies[0]!)}ms   max ${
        Math.round(latencies[latencies.length - 1]!)
      }ms`,
  );

  // Stability: for each photo and each field, did every repetition agree?
  console.log(
    `\nSTABILITY (repeat runs of the same photo; max disagreement ${
      (MAX_DISAGREEMENT_RATE * 100).toFixed(0)
    }%)`,
  );
  if (repetitions < 2) {
    console.log("  SKIP  --repetitions 1 measures nothing about stability");
  } else {
    for (const bar of BARS) {
      let disagreeing = 0;
      for (const entry of entries) {
        const forImage = observations.filter((o) => o.image === entry.image);
        const values = new Set(forImage.map((o) => o.scores[bar.field]));
        if (values.size > 1) disagreeing++;
      }
      const rate = disagreeing / entries.length;
      const ok = rate <= MAX_DISAGREEMENT_RATE;
      if (!ok) failed = true;
      console.log(
        `  ${ok ? "PASS" : "FAIL"}  ${bar.field.padEnd(14)} ${
          (rate * 100).toFixed(1)
        }% of photos ` +
          `changed verdict across repetitions`,
      );
      if (!ok) {
        for (const entry of entries) {
          const seen = [
            ...new Set(
              observations.filter((o) => o.image === entry.image).map((o) =>
                o.values[bar.field]
              ),
            ),
          ];
          if (seen.length > 1) {
            console.log(
              `          ↳ ${entry.image.split("/").pop()}: ${
                seen.join(" | ")
              }`,
            );
          }
        }
      }
    }
    // Free-text drift is not scored — it cannot be — but it is the thing a
    // reader most needs to see, so it is printed.
    const varied = entries.filter((e) =>
      new Set(
        observations.filter((o) => o.image === e.image).map((o) =>
          o.subcategory
        ),
      ).size > 1
    );
    console.log(
      `  note: ${varied.length}/${entries.length} photo(s) returned more than one distinct ` +
        `subcategory string across repetitions`,
    );
  }

  console.log(`\n${failed ? "GATE NOT CLEARED" : "GATE CLEARED"}\n`);
  return failed ? 1 : 0;
}

if (import.meta.main) Deno.exit(await main());
