import { ProviderError, type ProviderRequestContext } from "./types.ts";

export interface BackgroundRemovalProvider {
  remove(image: Uint8Array, ctx: ProviderRequestContext): Promise<Uint8Array>;
}

const MAX_BYTES = 8 * 1024 * 1024;
const PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10];
/** Optional segmentation adapter. Not enabled until server cost reservations and credentials exist. */
export class RemoveBgBackgroundRemovalProvider implements BackgroundRemovalProvider {
  constructor(private readonly apiKey: string, private readonly fetchImpl: typeof fetch = fetch) {}

  async remove(image: Uint8Array, ctx: ProviderRequestContext): Promise<Uint8Array> {
    if (!this.apiKey.trim()) {
      throw new ProviderError("AUTH_FAILED", false, "Background removal is unconfigured.");
    }
    if (!ctx.idempotencyKey || image.byteLength === 0 || image.byteLength > MAX_BYTES) {
      throw new ProviderError(
        "INVALID_INPUT",
        false,
        "Background removal requires a reserved request and bounded image.",
      );
    }
    const controller = new AbortController();
    const timer = setTimeout(
      () => controller.abort(),
      Math.max(1, Math.min(ctx.timeoutMs, 30_000)),
    );
    try {
      const form = new FormData();
      form.append("image_file", new Blob([new Uint8Array(image)]), "garment.jpg");
      form.append("size", "auto");
      form.append("format", "png");
      form.append("crop", "false");
      const response = await this.fetchImpl("https://api.remove.bg/v1.0/removebg", {
        method: "POST",
        headers: { "X-Api-Key": this.apiKey },
        body: form,
        signal: controller.signal,
        redirect: "error",
      });
      if (!response.ok) {
        const status = response.status;
        throw new ProviderError(
          status === 401 || status === 403
            ? "AUTH_FAILED"
            : status === 402
            ? "PROVIDER_QUOTA_EXCEEDED"
            : status === 429
            ? "RATE_LIMITED"
            : status >= 500
            ? "PROVIDER_UNAVAILABLE"
            : "INVALID_INPUT",
          status === 429 || status >= 500,
          "Background removal could not complete.",
        );
      }
      if (!response.headers.get("Content-Type")?.toLowerCase().startsWith("image/png")) {
        throw new ProviderError(
          "PROVIDER_UNAVAILABLE",
          false,
          "Background removal returned an invalid image.",
        );
      }
      const reader = response.body?.getReader();
      if (!reader) {
        throw new ProviderError(
          "PROVIDER_UNAVAILABLE",
          false,
          "Background removal returned no image.",
        );
      }
      const chunks: Uint8Array[] = [];
      let size = 0;
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > MAX_BYTES) {
            await reader.cancel();
            throw new ProviderError(
              "PROVIDER_UNAVAILABLE",
              false,
              "Background removal image is too large.",
            );
          }
          chunks.push(value);
        }
      } finally {
        reader.releaseLock();
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      // Validate structure and bounded dimensions, not subjective segmentation quality.
      if (!validCutoutStructure(bytes)) {
        throw new ProviderError(
          "PROVIDER_UNAVAILABLE",
          false,
          "Background removal returned an invalid cutout.",
        );
      }
      return bytes;
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      throw new ProviderError(
        controller.signal.aborted ? "TIMEOUT" : "PROVIDER_UNAVAILABLE",
        true,
        "Background removal is temporarily unavailable.",
      );
    } finally {
      clearTimeout(timer);
    }
  }
}

function validCutoutStructure(bytes: Uint8Array): boolean {
  if (bytes.length < 45 || !PNG_SIGNATURE.every((value, index) => bytes[index] === value)) {
    return false;
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(8) !== 13 || String.fromCharCode(...bytes.slice(12, 16)) !== "IHDR") {
    return false;
  }
  const width = view.getUint32(16), height = view.getUint32(20);
  if (
    width === 0 || height === 0 || width * height > 25_000_000 ||
    ![4, 6].includes(bytes[25] ?? -1) ||
    ![8, 16].includes(bytes[24] ?? -1) || bytes[26] !== 0 || bytes[27] !== 0 ||
    ![0, 1].includes(bytes[28] ?? -1)
  ) return false;
  let offset = 8, hasData = false;
  while (offset + 12 <= bytes.length) {
    const length = view.getUint32(offset), end = offset + length + 12;
    if (end > bytes.length) return false;
    const type = String.fromCharCode(...bytes.slice(offset + 4, offset + 8));
    if (type === "IDAT" && length > 0) hasData = true;
    if (type === "IEND") return length === 0 && hasData && end === bytes.length;
    offset = end;
  }
  return false;
}
