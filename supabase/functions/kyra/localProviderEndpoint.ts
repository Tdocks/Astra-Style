/**
 * The local UI acceptance stack may point the OpenAI-compatible adapter at a
 * host-side provider stub. Fail closed unless both this function runtime and
 * the configured endpoint are local. Deployed functions have no variable set
 * and keep the fixed OpenAI Responses URL.
 */
export function resolveLocalStylistProviderEndpoint(
  supabaseURL: string | undefined,
  configuredEndpoint: string | undefined,
): string | undefined {
  if (configuredEndpoint === undefined) return undefined;

  const runtimeURL = parseURL(supabaseURL);
  const endpointURL = parseURL(configuredEndpoint);
  if (!runtimeURL || !endpointURL) {
    throw new Error("Local stylist stubs require an HTTP local Supabase runtime.");
  }
  if (runtimeURL.protocol !== "http:" || !isLocalRuntimeHost(runtimeURL.hostname)) {
    throw new Error("Local stylist stubs are disabled for hosted Supabase runtimes.");
  }
  if (endpointURL.protocol !== "http:") {
    throw new Error("Local stylist stub URL must target the local Responses endpoint.");
  }
  if (
    !isLocalProviderHost(endpointURL.hostname) || endpointURL.pathname !== "/v1/responses" ||
    endpointURL.username || endpointURL.password || endpointURL.search || endpointURL.hash
  ) {
    throw new Error("Local stylist stub URL must target the local Responses endpoint.");
  }
  return endpointURL.toString();
}

function parseURL(raw: string | undefined): URL | undefined {
  if (raw === undefined) return undefined;
  try {
    return new URL(raw);
  } catch {
    return undefined;
  }
}

function isLocalRuntimeHost(host: string): boolean {
  return host === "kong" || host === "localhost" || host === "127.0.0.1" || host === "::1";
}

function isLocalProviderHost(host: string): boolean {
  return host === "host.docker.internal" || host === "localhost" || host === "127.0.0.1" ||
    host === "::1";
}
