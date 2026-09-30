import { badRequest } from "../_shared/errors.ts";
import { isRecord, isUUID, requireRecord } from "../_shared/validation.ts";

export interface PublicLookImageRequest {
  readonly outfit_id: string;
  readonly closet_item_id: string;
  readonly image_id: string;
}

export interface PublicLookImageEnvelope {
  readonly requestId?: string;
  readonly body: unknown;
}

export function parseEnvelope(raw: unknown): PublicLookImageEnvelope {
  const record = requireRecord(raw, "request");
  const body = record["body"];
  if (body === undefined) throw badRequest("Request envelope must include body.");
  const requestId = record["request_id"];
  if (requestId !== undefined && typeof requestId !== "string") {
    throw badRequest("request_id must be a string.");
  }
  return { requestId: requestId as string | undefined, body };
}

export function parsePublicLookImageRequests(raw: unknown): PublicLookImageRequest[] {
  const record = requireRecord(raw, "body");
  const images = record["images"];
  if (!Array.isArray(images) || images.length === 0 || images.length > 100) {
    throw badRequest("body.images must contain between 1 and 100 images.");
  }

  const parsed = images.map((entry, index): PublicLookImageRequest => {
    if (!isRecord(entry)) throw badRequest(`body.images[${index}] must be an object.`);
    const outfitID = entry["outfit_id"];
    const closetItemID = entry["closet_item_id"];
    const imageID = entry["image_id"];
    if (!isUUID(outfitID) || !isUUID(closetItemID) || !isUUID(imageID)) {
      throw badRequest(
        `body.images[${index}] must contain valid outfit_id, closet_item_id, and image_id UUIDs.`,
      );
    }
    return { outfit_id: outfitID, closet_item_id: closetItemID, image_id: imageID };
  });

  const unique = new Map<string, PublicLookImageRequest>();
  for (const image of parsed) {
    unique.set(`${image.outfit_id}:${image.closet_item_id}:${image.image_id}`, image);
  }
  return [...unique.values()];
}
