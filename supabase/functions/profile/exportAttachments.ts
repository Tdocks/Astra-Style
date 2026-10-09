/**
 * Extracts private Storage object references already present in exported rows.
 * This is intentionally not a bucket listing and does not imply every object
 * in Storage is represented by the database export.
 */
export interface ExportedStorageReference {
  readonly bucket: "user-content";
  readonly path: string;
}

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";

export function extractExportedStorageReferences(
  tables: Record<string, unknown[]>,
  ownerId: string,
): ExportedStorageReference[] {
  const owner = ownerId.toLowerCase();
  if (!new RegExp(`^${UUID}$`).test(owner)) return [];

  const paths = new Set<string>();
  const add = (candidate: unknown, pattern: RegExp): void => {
    if (typeof candidate === "string" && pattern.test(candidate)) paths.add(candidate);
  };
  const rows = (table: string): Record<string, unknown>[] =>
    (tables[table] ?? []).filter(isRecord);

  for (const row of rows("profiles")) {
    if (row["id"] !== owner) continue;
    add(row["avatar_storage_path"], new RegExp(`^users/${owner}/avatars/${UUID}\\.jpg$`));
  }

  // Current scanner uploads use a flat UUID filename; older documented paths
  // may include the closet-item UUID directory. Keep both exact forms.
  const closetSource = new RegExp(
    `^users/${owner}/closet/(?:${UUID}/)?${UUID}\\.(?:jpg|png)$`,
  );
  const closetCutout = new RegExp(
    `^users/${owner}/closet/(?:${UUID}-cutout|${UUID})\\.png$`,
  );
  for (const row of rows("closet_item_images")) {
    if (row["user_id"] !== owner) continue;
    add(row["storage_path"], closetSource);
    add(row["background_removed_path"], closetCutout);
  }

  const referencePath = new RegExp(`^users/${owner}/references/${UUID}\\.jpg$`);
  const studioResultPath = new RegExp(`^users/${owner}/studio/${UUID}/result\\.png$`);
  for (const row of rows("studio_generations")) {
    if (row["user_id"] !== owner) continue;
    add(row["reference_image_path"], referencePath);
    // Edits may use a previous Studio result as their reference image.
    add(row["reference_image_path"], studioResultPath);
    add(row["result_image_path"], studioResultPath);
  }

  return [...paths].sort().map((path) => ({ bucket: "user-content", path }));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
