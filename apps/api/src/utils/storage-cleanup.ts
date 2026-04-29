import { PoolClient } from 'pg';
import { minioClient, BUCKET_NAME } from '../config/minio';
import { logger } from '../utils/logger';

// Centralised MinIO cleanup routines. Best-effort by design — storage
// failures don't roll back the SQL DELETE; the orphan-recovery story is
// a periodic GC sweep, not the request path. Centralising the harvest
// prevents item / user / cron paths from drifting on which objects need
// to be cleaned (the bug 1.1 fixes was item-delete forgetting them
// entirely).

interface KeyHarvest {
  productImageKeys: string[];
  documentKeys: string[];
  thumbnailKeys: string[];
  avatarKey: string | null;
}

const EMPTY: KeyHarvest = {
  productImageKeys: [],
  documentKeys: [],
  thumbnailKeys: [],
  avatarKey: null,
};

/**
 * SELECT every MinIO object key owned by a single item. The caller's
 * client should be inside its own transaction; the DELETE happens
 * after this returns. Actual MinIO removal is done post-COMMIT via
 * [removeKeysBestEffort] so a storage outage never blocks a DB write.
 */
export async function harvestItemKeys(
  client: PoolClient,
  itemId: string,
): Promise<KeyHarvest> {
  const [docs, item] = await Promise.all([
    client.query<{ object_key: string | null; thumbnail_key: string | null }>(
      `SELECT object_key, thumbnail_key FROM documents WHERE item_id = $1`,
      [itemId],
    ),
    client.query<{ product_image_url: string | null }>(
      `SELECT product_image_url FROM items WHERE id = $1`,
      [itemId],
    ),
  ]);

  const productImageKey = item.rows[0]?.product_image_url ?? null;
  return {
    ...EMPTY,
    productImageKeys: productImageKey ? [productImageKey] : [],
    documentKeys: docs.rows.map((r) => r.object_key).filter((k): k is string => !!k),
    thumbnailKeys: docs.rows.map((r) => r.thumbnail_key).filter((k): k is string => !!k),
  };
}

/**
 * SELECT every MinIO object key owned by a user. Used by admin
 * hard-delete and the 30-day soft-delete purge cron.
 */
export async function harvestUserKeys(
  client: PoolClient,
  userId: string,
): Promise<KeyHarvest> {
  const [docs, items, user] = await Promise.all([
    client.query<{ object_key: string | null; thumbnail_key: string | null }>(
      `SELECT object_key, thumbnail_key FROM documents WHERE user_id = $1`,
      [userId],
    ),
    client.query<{ product_image_url: string | null }>(
      `SELECT product_image_url FROM items
         WHERE user_id = $1 AND product_image_url IS NOT NULL`,
      [userId],
    ),
    client.query<{ avatar_url: string | null }>(
      `SELECT avatar_url FROM users WHERE id = $1`,
      [userId],
    ),
  ]);

  return {
    productImageKeys: items.rows
      .map((r) => r.product_image_url)
      .filter((k): k is string => !!k),
    documentKeys: docs.rows.map((r) => r.object_key).filter((k): k is string => !!k),
    thumbnailKeys: docs.rows.map((r) => r.thumbnail_key).filter((k): k is string => !!k),
    avatarKey: user.rows[0]?.avatar_url ?? null,
  };
}

/**
 * Flatten a harvest into a single array suitable for [removeKeysBestEffort].
 */
export function flattenHarvest(harvest: KeyHarvest): string[] {
  return [
    ...harvest.productImageKeys,
    ...harvest.documentKeys,
    ...harvest.thumbnailKeys,
    ...(harvest.avatarKey ? [harvest.avatarKey] : []),
  ];
}

/**
 * Remove every captured key from MinIO. Best-effort — failures are
 * logged and swallowed; the underlying DB rows are already gone by the
 * time this runs. Orphans get reaped by a future GC sweep.
 */
export async function removeKeysBestEffort(
  keys: ReadonlyArray<string | null | undefined>,
): Promise<{ removed: number; failed: number }> {
  let removed = 0;
  let failed = 0;
  for (const key of keys) {
    if (!key) continue;
    try {
      await minioClient.removeObject(BUCKET_NAME, key);
      removed++;
    } catch (err) {
      failed++;
      logger.warn({ err, key }, 'MinIO cleanup: removeObject failed (orphan)');
    }
  }
  return { removed, failed };
}
