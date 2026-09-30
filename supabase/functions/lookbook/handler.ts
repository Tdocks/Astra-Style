import {
  AppError,
  badRequest,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { CORS_HEADERS } from "../_shared/cors.ts";
import { parseEnvelope, parsePublicLookImageRequests } from "./schema.ts";

export interface PublicLookGarmentRow {
  readonly outfit_id: string;
  readonly closet_item_id: string;
  readonly display_image_id: string | null;
}

export interface ImagePathRow {
  readonly id: string;
  readonly storage_path: string;
  readonly background_removed_path: string | null;
}

export interface SignedImagePath {
  readonly path: string;
  readonly signed_url: string;
}

export interface SignPublicLookImagesDependencies {
  readonly authClient: AuthClient;
  readonly rateLimiter: RateLimiter;
  readonly now: () => number;
  readonly fetchPublicGarments: (
    authorizationHeader: string,
    outfitIDs: string[],
  ) => Promise<PublicLookGarmentRow[]>;
  readonly fetchImages: (imageIDs: string[]) => Promise<ImagePathRow[]>;
  readonly signStoragePaths: (
    paths: string[],
    expiresInSeconds: number,
  ) => Promise<SignedImagePath[]>;
}

const SIGNED_URL_LIFETIME_SECONDS = 600;

export async function handleSignPublicLookImages(
  req: Request,
  deps: SignPublicLookImagesDependencies,
): Promise<Response> {
  let requestID = resolveRequestId(req);
  try {
    if (req.method !== "POST") {
      throw methodNotAllowed("POST /lookbook/sign-images only accepts POST.");
    }

    const authorizationHeader = req.headers.get("authorization") ?? "";
    const userID = await authenticateRequest(req, deps.authClient);
    const limit = deps.rateLimiter.check(userID, deps.now());
    if (!limit.allowed) {
      return errorResponse(rateLimited(), requestID, {
        ...CORS_HEADERS,
        "Retry-After": String(limit.retryAfterSeconds),
      });
    }

    const raw = await req.json().catch(() => null);
    if (raw === null) throw badRequest("Request body must be valid JSON.");
    const envelope = parseEnvelope(raw);
    requestID = resolveRequestId(req, envelope.requestId ?? null);
    const requests = parsePublicLookImageRequests(envelope.body);
    const outfitIDs = [...new Set(requests.map((image) => image.outfit_id))];

    // This RPC is caller-scoped. It returns only display-safe garment rows
    // when each outfit is public, active, and has been worn.
    const publicRows = await deps.fetchPublicGarments(authorizationHeader, outfitIDs);
    const allowed = new Set(
      publicRows
        .filter((row) => row.display_image_id !== null)
        .map((row) => `${row.outfit_id}:${row.closet_item_id}:${row.display_image_id}`),
    );
    const authorized = requests.filter((image) =>
      allowed.has(`${image.outfit_id}:${image.closet_item_id}:${image.image_id}`)
    );
    if (authorized.length === 0) {
      return jsonResponse({ images: [] }, {
        status: 200,
        requestId: requestID,
        extraHeaders: CORS_HEADERS,
      });
    }

    const imageIDs = [...new Set(authorized.map((image) => image.image_id))];
    const imageRows = await deps.fetchImages(imageIDs);
    const pathByImageID = new Map<string, string>();
    for (const image of imageRows) {
      pathByImageID.set(image.id, image.background_removed_path ?? image.storage_path);
    }
    const imagePaths = [...new Set(imageIDs.flatMap((id) => pathByImageID.get(id) ?? []))];
    const signed = await deps.signStoragePaths(imagePaths, SIGNED_URL_LIFETIME_SECONDS);
    const signedURLByPath = new Map(signed.map((image) => [image.path, image.signed_url]));

    const responseImages = authorized.flatMap((image) => {
      const path = pathByImageID.get(image.image_id);
      const signedURL = path ? signedURLByPath.get(path) : undefined;
      return signedURL ? [{ image_id: image.image_id, signed_url: signedURL }] : [];
    });
    return jsonResponse({ images: responseImages }, {
      status: 200,
      requestId: requestID,
      extraHeaders: CORS_HEADERS,
    });
  } catch (error) {
    const appError = error instanceof AppError ? error : serverError();
    return errorResponse(appError, requestID, CORS_HEADERS);
  }
}
