import {
  createServiceRoleClient,
  createUserScopedClient,
  readEdgeEnv,
} from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import type { ImagePathRow, PublicLookGarmentRow, SignedImagePath } from "./handler.ts";
import { handleSignPublicLookImages } from "./handler.ts";

const env = readEdgeEnv();
const rateLimiter = createRateLimiter({ limit: 60, windowMs: 60_000 });
const serviceRole = createServiceRoleClient(env);

const handler = createRouter("lookbook", [{
  method: "POST",
  pattern: "/sign-images",
  handler: (req) =>
    handleSignPublicLookImages(req, {
      authClient: createUserScopedClient(env, req.headers.get("authorization") ?? ""),
      rateLimiter,
      now: () => Date.now(),
      async fetchPublicGarments(authorizationHeader, outfitIDs) {
        const userClient = createUserScopedClient(env, authorizationHeader);
        const { data, error } = await userClient.rpc("fetch_public_look_garments", {
          p_outfit_ids: outfitIDs,
        });
        if (error) throw serverError("Couldn't verify that shared look.");
        return (data ?? []) as PublicLookGarmentRow[];
      },
      async fetchImages(imageIDs) {
        if (imageIDs.length === 0) return [];
        const { data, error } = await serviceRole
          .from("closet_item_images")
          .select("id, storage_path, background_removed_path")
          .in("id", imageIDs);
        if (error) throw serverError("Couldn't load the selected look image.");
        return (data ?? []) as ImagePathRow[];
      },
      async signStoragePaths(paths, expiresInSeconds) {
        if (paths.length === 0) return [];
        const { data, error } = await serviceRole.storage
          .from("user-content")
          .createSignedUrls(paths, expiresInSeconds);
        if (error) throw serverError("Couldn't sign the selected look image.");
        return (data ?? []).flatMap((entry): SignedImagePath[] => {
          if (!entry.path || !entry.signedUrl) return [];
          return [{
            path: entry.path,
            signed_url: new URL(entry.signedUrl, env.supabaseUrl).toString(),
          }];
        });
      },
    }),
}]);

Deno.serve(handler);
