export interface RetentionJob {
  id: string;
  user_id: string;
  generation_id: string | null;
  generation_key: string;
  result_image_path: string | null;
  kind?: "studio" | "reference";
}

export interface OrphanResultCleanupJob {
  id: string;
  owner_user_id: string;
  generation_id: string;
  storage_path: string;
}

export type OrphanResultDisposition = "remove" | "defer" | "preserve";

export interface RetentionRepository {
  authorize(secret: string): Promise<boolean>;
  prepare(): Promise<number>;
  claim(token: string): Promise<RetentionJob[]>;
  finish(jobID: string, token: string, succeeded: boolean): Promise<boolean>;
  claimOrphanResults(token: string): Promise<OrphanResultCleanupJob[]>;
  orphanResultDisposition(ownerID: string, generationID: string): Promise<OrphanResultDisposition>;
  finishOrphanResult(jobID: string, token: string, succeeded: boolean): Promise<boolean>;
}

export interface RetentionDeps {
  repository: RetentionRepository;
  removeImage(path: string): Promise<void>;
  token(): string;
}

/** Reject malformed or cross-owner paths before a privileged Storage deletion. */
export function validResultPath(job: RetentionJob): boolean {
  if (job.result_image_path === null) return true;
  const parts = job.result_image_path.split("/");
  if (job.kind === "reference") {
    return job.generation_id === null && parts.length === 4 && parts[0] === "users" &&
      parts[1] === job.user_id.toLowerCase() && parts[2] === "references" &&
      parts[3] === `${job.generation_key.toLowerCase()}.jpg` &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(job.generation_key);
  }
  if (job.kind !== undefined && job.kind !== "studio") return false;
  return parts.length === 5 && parts[0] === "users" &&
    parts[1] === job.user_id.toLowerCase() && parts[2] === "studio" &&
    parts[3] === job.generation_key.toLowerCase() &&
    /^result\.(png|jpg|jpeg|webp)$/.test(parts[4] ?? "");
}

/** Exact generated-result paths only; these jobs can outlive both owner and generation rows. */
export function validOrphanResultCleanupPath(job: OrphanResultCleanupJob): boolean {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  return uuid.test(job.owner_user_id) && uuid.test(job.generation_id) &&
    job.storage_path ===
      `users/${job.owner_user_id}/studio/${job.generation_id}/result.png`;
}

export async function handleRetention(req: Request, deps: RetentionDeps): Promise<Response> {
  const reply = (body: unknown, status = 200) => Response.json(body, { status });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const secret = req.headers.get("x-astra-retention-secret") ?? "";
  if (!/^[a-f0-9]{64}$/.test(secret)) return reply({ error: "unauthorized" }, 401);
  try {
    if (!(await deps.repository.authorize(secret))) return reply({ error: "unauthorized" }, 401);
    const prepared = await deps.repository.prepare();
    const token = deps.token();
    const jobs = await deps.repository.claim(token);
    let completed = 0, retrying = 0;
    for (const job of jobs) {
      try {
        if (!validResultPath(job)) throw new Error("Invalid private result path");
        if (job.result_image_path !== null) await deps.removeImage(job.result_image_path);
        if (await deps.repository.finish(job.id, token, true)) completed += 1;
        else retrying += 1;
      } catch {
        // Never expose paths, identities, tokens or upstream error details.
        await deps.repository.finish(job.id, token, false);
        retrying += 1;
      }
    }
    const orphanJobs = await deps.repository.claimOrphanResults(token);
    let orphanCompleted = 0, orphanRetrying = 0;
    for (const job of orphanJobs) {
      try {
        if (!validOrphanResultCleanupPath(job)) {
          throw new Error("Invalid orphan result path");
        }
        const disposition = await deps.repository.orphanResultDisposition(
          job.owner_user_id,
          job.generation_id,
        );
        if (disposition === "defer") {
          if (await deps.repository.finishOrphanResult(job.id, token, false)) orphanRetrying += 1;
          else orphanRetrying += 1;
          continue;
        }
        if (disposition === "remove") await deps.removeImage(job.storage_path);
        else if (disposition !== "preserve") throw new Error("Unknown cleanup disposition");
        if (await deps.repository.finishOrphanResult(job.id, token, true)) orphanCompleted += 1;
        else orphanRetrying += 1;
      } catch {
        try {
          await deps.repository.finishOrphanResult(job.id, token, false);
        } catch { /* The claim expires and remains recoverable. */ }
        orphanRetrying += 1;
      }
    }
    return reply({ prepared, completed, retrying, orphanCompleted, orphanRetrying });
  } catch {
    return reply({ error: "cleanup_unavailable" }, 503);
  }
}
