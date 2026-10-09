export interface ScopedPageResult<T> {
  readonly data: readonly T[] | null;
  readonly error: unknown | null;
}

const DEFAULT_PAGE_SIZE = 1000;
const DEFAULT_ID_BATCH_SIZE = 100;

/** Read stable, offset-paginated rows. `null` means any page failed. */
export async function readAllUserPages<T>(
  userId: string,
  fetchPage: (userId: string, offset: number, limit: number) => Promise<ScopedPageResult<T>>,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<T[] | null> {
  const rows: T[] = [];
  for (let offset = 0;; offset += pageSize) {
    const result = await fetchPage(userId, offset, pageSize);
    if (result.error !== null && result.error !== undefined) return null;
    const page = result.data ?? [];
    rows.push(...page);
    if (page.length < pageSize) return rows;
  }
}

/** Read all rows for IDs in bounded URL-safe batches, paginating each batch. */
export async function readAllUserIdBatches<T>(
  userId: string,
  ids: readonly string[],
  fetchPage: (
    userId: string,
    ids: readonly string[],
    offset: number,
    limit: number,
  ) => Promise<ScopedPageResult<T>>,
  batchSize = DEFAULT_ID_BATCH_SIZE,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<T[] | null> {
  const uniqueIds = [...new Set(ids)];
  const rows: T[] = [];
  for (let start = 0; start < uniqueIds.length; start += batchSize) {
    const batch = uniqueIds.slice(start, start + batchSize);
    const batchRows = await readAllUserPages(
      userId,
      (ownerId, offset, limit) => fetchPage(ownerId, batch, offset, limit),
      pageSize,
    );
    if (batchRows === null) return null;
    rows.push(...batchRows);
  }
  return rows;
}
