import type { StylistReasoningProvider } from "../_shared/providers/stylistReasoning.ts";
import { ProviderError } from "../_shared/providers/types.ts";
import { LiveStylistProvider } from "../kyra/liveStylistProvider.ts";
import { DeterministicStylistProvider } from "./deterministicStylist.ts";
import { ResilientStylistProvider } from "./providerResilience.ts";

export interface StyleDnaProviderConfig {
  readonly mode?: string;
  readonly stylistApiKey?: string;
  readonly imageProvider?: string;
  readonly imageApiKey?: string;
  readonly modelLuna?: string;
  readonly modelTerra?: string;
}

/**
 * Selects a provider from server configuration. The live OpenAI credential
 * follows Kyra's established precedence. Deterministic output is only
 * available when explicitly selected; a missing live key never masquerades
 * as a successful live generation.
 */
export function buildStyleDnaProvider(config: StyleDnaProviderConfig): StylistReasoningProvider {
  const mode = config.mode?.trim().toLowerCase();
  if (mode === "deterministic") return new DeterministicStylistProvider();

  const dedicatedKey = config.stylistApiKey?.trim();
  const sharedKey = config.imageProvider?.trim().toLowerCase() === "openai"
    ? config.imageApiKey?.trim()
    : undefined;
  const apiKey = dedicatedKey || sharedKey;
  if (!apiKey) return unconfiguredProvider();

  const modelForTier = {
    luna: config.modelLuna?.trim() || "gpt-5.6-luna",
    terra: config.modelTerra?.trim() || "gpt-5.6-terra",
    // docs/09 currently routes Style DNA directly to Terra; retain Kyra's
    // established ceiling mapping until account model availability is checked.
    sol: config.modelTerra?.trim() || "gpt-5.6-terra",
  };
  if (Object.values(modelForTier).some((model) => !/^[a-zA-Z0-9._-]{1,100}$/.test(model))) {
    return unconfiguredProvider();
  }

  return new ResilientStylistProvider(new LiveStylistProvider({ apiKey, modelForTier }));
}

function unconfiguredProvider(): StylistReasoningProvider {
  const unavailable = () =>
    new ProviderError(
      "PROVIDER_UNAVAILABLE",
      false,
      "Style DNA live provider is not configured.",
      undefined,
      true,
    );
  return {
    complete() {
      return Promise.reject(unavailable());
    },
    // deno-lint-ignore require-yield
    async *completeStream() {
      throw unavailable();
    },
  };
}
