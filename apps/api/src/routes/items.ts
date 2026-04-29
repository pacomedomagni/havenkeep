import { Router } from 'express';
import { getClient, query, pool } from '../db';
import { authenticate, AuthRequest } from '../middleware/auth';
import { AppError } from '../utils/errors';
import { logger } from '../utils/logger';
import { addMonthsSafe } from '../utils/dates';
import { validate } from '../middleware/validate';
import {
  createItemSchema,
  updateItemSchema,
  paginationSchema,
  uuidParamSchema,
  csvExportQuerySchema,
} from '../validators';
import { AuditService } from '../services/audit.service';
import { config } from '../config';
import {
  writeRateLimiter,
  itemsListRateLimiter,
  csvExportRateLimiter,
} from '../middleware/rateLimiter';
import { idempotency } from '../middleware/idempotency';
import { asyncHandler } from '../utils/async-handler';
import { sendSuccess, sendMessage } from '../utils/response';
import { presignedUrlForKey } from '../config/minio';
import { harvestItemKeys, flattenHarvest, removeKeysBestEffort } from '../utils/storage-cleanup';

const router = Router();

// All routes require authentication
router.use(authenticate);

// Whitelist of allowed update fields to prevent SQL injection
// NOTE: added_via is intentionally excluded — it is a write-once audit field
const ALLOWED_UPDATE_FIELDS = new Set([
  'name', 'brand', 'model_number', 'serial_number', 'category', 'room',
  'purchase_date', 'store', 'price', 'warranty_months', 'warranty_type',
  'warranty_provider', 'notes', 'is_archived', 'product_image_url', 'barcode',
  'home_id', 'installation_date', 'last_maintenance_date', 'next_maintenance_due',
]);

// Audit Ch02-F005/F006: explicit column allowlist; drives both the list
// SELECT and the per-row payload shape so list/detail can't drift.
const ITEM_LIST_COLUMNS = `
  id, user_id, home_id, name, brand, model_number, serial_number,
  category, room, purchase_date, store, price,
  warranty_months, warranty_end_date, warranty_type, warranty_provider,
  notes, is_archived, archived_at, product_image_url, barcode, added_via,
  installation_date, last_maintenance_date, next_maintenance_due,
  expected_lifespan_years, created_at, updated_at
`;

// Default expected lifespan (in years) by category, used when the item has no explicit value
const CATEGORY_DEFAULT_LIFESPAN: Record<string, number> = {
  appliance: 12,
  electronics: 5,
  furniture: 15,
  hvac: 15,
  plumbing: 20,
  roofing: 25,
  flooring: 15,
  outdoor: 10,
  other: 10,
};

// Audit Ch02-F020: switch from local-TZ ms division (which drifts at DST and
// at year boundaries) to a UTC-aware day count and integer-month arithmetic.
function computeLifespanPercentage(item: any): number | null {
  const expectedLifespan: number | null =
    item.expected_lifespan_years ??
    CATEGORY_DEFAULT_LIFESPAN[item.category] ??
    null;
  if (!expectedLifespan || !item.purchase_date) return null;
  const purchaseDate = new Date(item.purchase_date);
  if (Number.isNaN(purchaseDate.getTime())) return null;
  const nowUtcDay = Date.UTC(
    new Date().getUTCFullYear(),
    new Date().getUTCMonth(),
    new Date().getUTCDate(),
  );
  const purchaseUtcDay = Date.UTC(
    purchaseDate.getUTCFullYear(),
    purchaseDate.getUTCMonth(),
    purchaseDate.getUTCDate(),
  );
  const daysSincePurchase = Math.max(0, (nowUtcDay - purchaseUtcDay) / 86_400_000);
  const yearsSincePurchase = daysSincePurchase / 365.2425;
  return Math.min(100, Math.round((yearsSincePurchase / expectedLifespan) * 100));
}

// Audit Ch02-F062/F063: dates leave the API at second precision (toISOString
// strips microseconds; archived_at and updated_at follow the same shape).
//
// S-CR-02: product_image_url is a MinIO object key; mint a presigned URL
// at response time so a leaked URL is useless within
// PRESIGNED_URL_TTL_SECONDS. Async because the MinIO presigner is async.
async function normalizeItemRow(row: any): Promise<any> {
  if (!row) return row;
  const out = { ...row };
  for (const k of ['created_at', 'updated_at', 'archived_at'] as const) {
    if (out[k] != null) {
      const d = new Date(out[k]);
      if (!Number.isNaN(d.getTime())) {
        out[k] = d.toISOString().replace(/\.\d{3}Z$/, 'Z');
      }
    }
  }
  if (out.product_image_url) {
    out.product_image_url = await presignedUrlForKey(out.product_image_url);
  }
  return out;
}

// Audit Ch02-F052: prefix any cell starting with `=,+,-,@`, tab, or CR with a
// single quote so spreadsheet apps don't interpret it as a formula.
function escapeCsv(val: any): string {
  if (val == null) return '';
  let str = String(val);
  if (/^[=+\-@\t\r]/.test(str)) {
    str = `'${str}`;
  }
  if (str.includes(',') || str.includes('"') || str.includes('\n') || str.includes('\r')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

// Audit Ch02-F049/F050/F052/F053/F066: keyset CSV stream with explicit
// archive flag, formula-injection prefix, hard-cap timeout, and dedicated
// rate limiter.
router.get(
  '/export.csv',
  csvExportRateLimiter,
  validate(csvExportQuerySchema, 'query'),
  async (req: AuthRequest, res, next) => {
  // Hard timeout so a runaway export can't pin a connection. 60s is enough
  // for a few million rows under the keyset stream below.
  const EXPORT_TIMEOUT_MS = 60_000;
  const timeout = setTimeout(() => {
    logger.warn({ userId: req.user?.id }, 'CSV export timed out');
    if (!res.headersSent) {
      res.status(504).json({ error: 'Export timed out' });
    } else {
      res.destroy();
    }
  }, EXPORT_TIMEOUT_MS);
  try {
    const headers = [
      'Name', 'Brand', 'Category', 'Room', 'Model Number', 'Serial Number',
      'Purchase Date', 'Store', 'Price', 'Warranty Type', 'Warranty Months',
      'Warranty End Date', 'Notes', 'Archived', 'Added Via', 'Created At',
    ];

    function formatRow(item: any): string {
      return [
        escapeCsv(item.name),
        escapeCsv(item.brand),
        escapeCsv(item.category),
        escapeCsv(item.room),
        escapeCsv(item.model_number),
        escapeCsv(item.serial_number),
        escapeCsv(item.purchase_date ? new Date(item.purchase_date).toISOString().split('T')[0] : ''),
        escapeCsv(item.store),
        escapeCsv(item.price != null ? Number(item.price).toFixed(2) : ''),
        escapeCsv(item.warranty_type),
        escapeCsv(item.warranty_months),
        escapeCsv(item.warranty_end_date ? new Date(item.warranty_end_date).toISOString().split('T')[0] : ''),
        escapeCsv(item.notes),
        escapeCsv(item.is_archived ? 'Yes' : 'No'),
        escapeCsv(item.added_via),
        escapeCsv(item.created_at ? new Date(item.created_at).toISOString().split('T')[0] : ''),
      ].join(',');
    }

    const date = new Date().toISOString().split('T')[0];
    const filename = `havenkeep_items_${date}.csv`;

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Transfer-Encoding', 'chunked');

    // Audit log the export
    const archivedFlag = (req.query.archived as string | undefined) ?? 'false';
    await AuditService.logFromRequest(req, 'item.export', {
      resourceType: 'item',
      description: 'User exported items as CSV',
      metadata: { archived: archivedFlag },
    });

    // Write BOM + header row
    res.write('﻿' + headers.join(',') + '\r\n');

    // Audit Ch02-F049: keyset stream by (created_at, id) so deep exports are
    // O(N) rather than O(N²) for OFFSET. Cursor is `(created_at, id)` so
    // ties on created_at are deterministic.
    const CHUNK_SIZE = 500;
    let lastCreatedAt: string | null = null;
    let lastId: string | null = null;
    let archivedClause = ' AND is_archived = FALSE';
    if (archivedFlag === 'true') archivedClause = ' AND is_archived = TRUE';
    if (archivedFlag === 'all') archivedClause = '';

    while (true) {
      const params: any[] = [req.user!.id];
      let sql = `SELECT name, brand, category, room, model_number, serial_number,
                        purchase_date, store, price, warranty_type, warranty_months,
                        warranty_end_date, notes, is_archived, added_via, created_at, id
                 FROM items
                 WHERE user_id = $1${archivedClause}`;
      if (lastCreatedAt && lastId) {
        sql += ` AND (created_at, id) < ($2, $3)`;
        params.push(lastCreatedAt, lastId);
      }
      sql += ` ORDER BY created_at DESC, id DESC LIMIT $${params.length + 1}`;
      params.push(CHUNK_SIZE);

      const result = await query(sql, params);

      for (const row of result.rows) {
        res.write(formatRow(row) + '\r\n');
      }

      if (result.rows.length < CHUNK_SIZE) {
        break;
      }
      const last = result.rows[result.rows.length - 1];
      lastCreatedAt = last.created_at;
      lastId = last.id;
    }

    res.end();
  } catch (error) {
    if (res.headersSent) {
      res.destroy();
    } else {
      next(error);
    }
  } finally {
    clearTimeout(timeout);
  }
});

// Get active item count (for free plan limit check)
router.get('/count', asyncHandler(async (req: AuthRequest, res) => {
  // Audit Ch02-F010: count and the create-time check both use
  // is_archived = FALSE so the user-facing "X / 5 used" stays in sync with
  // the limit enforced inside the create transaction.
  const result = await query(
    `SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`,
    [req.user!.id]
  );

  sendSuccess(res, { count: parseInt(result.rows[0].count, 10) });
}));

// Get all items for user (with pagination)
router.get(
  '/',
  itemsListRateLimiter,
  validate(paginationSchema, 'query'),
  asyncHandler(async (req: AuthRequest, res) => {
  const { homeId, archived, addedVia, page, limit, sort, order, cursor } = req.query as any;

  // Audit Ch12-T044: defence-in-depth clamping in case validate() is bypassed
  // (e.g. body-parser strips an unknown route). Joi already enforces these;
  // do not trust the type assertions blindly.
  const pageNum = Math.max(1, parseInt(String(page ?? '1'), 10) || 1);
  const limitNum = Math.min(100, Math.max(1, parseInt(String(limit ?? '20'), 10) || 20));
  const offset = (pageNum - 1) * limitNum;

  // Audit Ch12-T043: sort/order are constrained by paginationSchema; keep a
  // belt-and-braces allowlist here so a future caller can't pass them
  // raw without going through the validator.
  const SORT_COLUMNS = new Set(['warranty_end_date', 'created_at', 'name', 'price']);
  const safeSort = SORT_COLUMNS.has(String(sort)) ? String(sort) : 'warranty_end_date';
  const safeOrder = String(order) === 'desc' ? 'DESC' : 'ASC';

  let sql = `SELECT ${ITEM_LIST_COLUMNS} FROM items WHERE user_id = $1`;
  const params: any[] = [req.user!.id];

  if (homeId) {
    sql += ` AND home_id = $${params.length + 1}`;
    params.push(homeId);
  }

  if (archived !== undefined) {
    const isArchived = archived === 'true' || archived === true;
    sql += ` AND is_archived = $${params.length + 1}`;
    params.push(isArchived);
  }

  if (addedVia) {
    sql += ` AND added_via = $${params.length + 1}`;
    params.push(addedVia);
  }

  // Audit Ch02-F008/F009: keyset pagination via opaque cursor when supplied;
  // fall back to OFFSET only for callers still on legacy `page` mode.
  let useCursor = false;
  if (typeof cursor === 'string' && cursor.length > 0) {
    try {
      const decoded = Buffer.from(cursor, 'base64url').toString('utf8');
      const parsed = JSON.parse(decoded);
      if (parsed && typeof parsed.k !== 'undefined' && typeof parsed.id === 'string') {
        const cmp = safeOrder === 'DESC' ? '<' : '>';
        sql += ` AND (${safeSort}, id) ${cmp} ($${params.length + 1}, $${params.length + 2})`;
        params.push(parsed.k, parsed.id);
        useCursor = true;
      }
    } catch {
      throw new AppError('Invalid pagination cursor', 400);
    }
  }

  sql += ` ORDER BY ${safeSort} ${safeOrder}, id ${safeOrder} LIMIT $${params.length + 1}`;
  params.push(limitNum + 1); // fetch one extra row to detect "has more"
  if (!useCursor) {
    sql += ` OFFSET $${params.length + 1}`;
    params.push(offset);
  }

  // Get total count in parallel with the page fetch so first-page renders
  // have an accurate total. Subsequent keyset pages skip the count.
  const countPromise = useCursor
    ? Promise.resolve({ rows: [{ count: '0' }] } as any)
    : (async () => {
        let countSql = `SELECT COUNT(*) FROM items WHERE user_id = $1`;
        const countParams: any[] = [req.user!.id];
        if (homeId) {
          countSql += ` AND home_id = $${countParams.length + 1}`;
          countParams.push(homeId);
        }
        if (archived !== undefined) {
          const isArchived = archived === 'true' || archived === true;
          countSql += ` AND is_archived = $${countParams.length + 1}`;
          countParams.push(isArchived);
        }
        if (addedVia) {
          countSql += ` AND added_via = $${countParams.length + 1}`;
          countParams.push(addedVia);
        }
        return query(countSql, countParams);
      })();

  const [result, countResult] = await Promise.all([query(sql, params), countPromise]);

  const hasMore = result.rows.length > limitNum;
  const pageRows = hasMore ? result.rows.slice(0, limitNum) : result.rows;
  const total = useCursor ? null : parseInt(countResult.rows[0].count, 10);

  // Audit Ch02-F064: emit lifespan_percentage on every list row so callers
  // don't have to round-trip per-item GETs to render progress bars.
  const enriched = await Promise.all(
    pageRows.map((row: any) =>
      normalizeItemRow({
        ...row,
        lifespan_percentage: computeLifespanPercentage(row),
      }),
    ),
  );

  // Build next cursor from the tail of the page when there's more.
  let nextCursor: string | null = null;
  if (hasMore && pageRows.length > 0) {
    const last = pageRows[pageRows.length - 1];
    nextCursor = Buffer.from(
      JSON.stringify({ k: last[safeSort], id: last.id }),
    ).toString('base64url');
  }

  sendSuccess(res, enriched, {
    pagination: {
      page: pageNum,
      limit: limitNum,
      total,
      total_pages: total != null ? Math.ceil(total / limitNum) : null,
      next_cursor: nextCursor,
      has_more: hasMore,
    },
  });
}));

// Get single item
router.get('/:id', validate(uuidParamSchema, 'params'), asyncHandler(async (req: AuthRequest, res) => {
  const result = await query(
    `SELECT ${ITEM_LIST_COLUMNS} FROM items WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user!.id]
  );

  if (result.rows.length === 0) {
    throw new AppError('Item not found', 404);
  }

  const item = result.rows[0];
  const expectedLifespan: number | null =
    item.expected_lifespan_years ??
    CATEGORY_DEFAULT_LIFESPAN[item.category] ??
    null;

  sendSuccess(res, await normalizeItemRow({
    ...item,
    expected_lifespan_years: expectedLifespan,
    lifespan_percentage: computeLifespanPercentage(item),
  }));
}));

// Create item
router.post('/', writeRateLimiter, validate(createItemSchema), idempotency('items:create'), asyncHandler(async (req: AuthRequest, res) => {
  const client = await getClient();
  try {
    const {
      homeId,
      name,
      brand,
      modelNumber,
      serialNumber,
      category,
      room,
      purchaseDate,
      store,
      price,
      warrantyMonths,
      warrantyType,
      warrantyProvider,
      notes,
      barcode,
      addedVia,
      installationDate,
      lastMaintenanceDate,
      nextMaintenanceDue,
    } = req.body;

    await client.query('BEGIN');

    // Check free plan limit (5 items) with a user-level lock to prevent races
    if (req.user!.plan === 'free') {
      await client.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user!.id]);

      const countResult = await client.query(
        `SELECT COUNT(*) FROM items WHERE user_id = $1 AND is_archived = FALSE`,
        [req.user!.id]
      );

      if (parseInt(countResult.rows[0].count, 10) >= config.freeTier.itemLimit) {
        throw new AppError('Free plan limit reached. Upgrade to Premium for unlimited items.', 403);
      }
    }

    // Verify home belongs to user
    const homeResult = await client.query(
      `SELECT id FROM homes WHERE id = $1 AND user_id = $2`,
      [homeId, req.user!.id]
    );

    if (homeResult.rows.length === 0) {
      throw new AppError('Home not found', 404);
    }

    // Calculate warranty end date
    const purchaseDateObj = new Date(purchaseDate);
    if (isNaN(purchaseDateObj.getTime())) {
      throw new AppError('Invalid purchase date', 400);
    }
    const warrantyEndDate = addMonthsSafe(purchaseDateObj, warrantyMonths);

    // Audit Ch08-D017: seed `estimated_repair_cost` from category_defaults
    // when the create payload doesn't carry one. Health score and the
    // savings_feed both depend on it; without a seed value they crater for
    // brand-new items. Lookup is best-effort — if the row is missing or the
    // category isn't in the table, the column stays NULL.
    let seededRepairCost: number | null = null;
    if (req.body.estimatedRepairCost === undefined) {
      try {
        const defaults = await client.query(
          `SELECT estimated_repair_cost FROM category_defaults WHERE category = $1`,
          [category],
        );
        if (defaults.rows[0]?.estimated_repair_cost != null) {
          seededRepairCost = Number(defaults.rows[0].estimated_repair_cost);
        }
      } catch {
        // category_defaults absent in some test fixtures; fall through.
      }
    }
    const estimatedRepairCost = req.body.estimatedRepairCost ?? seededRepairCost;

    // S-CR-02: product_image_url intentionally NOT populated here. The user
    // adds an item first, then uploads an image via POST /uploads/item-image
    // which writes the MinIO object key directly.
    const result = await client.query(
      `INSERT INTO items (
        user_id, home_id, name, brand, model_number, serial_number,
        category, room, purchase_date, store, price,
        warranty_months, warranty_end_date, warranty_type, warranty_provider, notes,
        barcode, added_via,
        installation_date, last_maintenance_date, next_maintenance_due,
        estimated_repair_cost
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22)
      RETURNING ${ITEM_LIST_COLUMNS}`,
      [
        req.user!.id, homeId, name, brand, modelNumber, serialNumber,
        category, room, purchaseDate, store, price,
        warrantyMonths, warrantyEndDate, warrantyType,
        warrantyProvider, notes, barcode, addedVia || 'manual',
        installationDate || null, lastMaintenanceDate || null, nextMaintenanceDue || null,
        estimatedRepairCost,
      ]
    );

    await client.query('COMMIT');

    const item = result.rows[0];

    // Fire-and-forget: stamp first_item_added_at on any active gift for this user
    pool.query(
      `UPDATE partner_gifts
       SET first_item_added_at = COALESCE(first_item_added_at, NOW())
       WHERE activated_user_id = $1 AND is_activated = TRUE`,
      [req.user!.id]
    ).catch(() => { /* non-critical */ });

    // Audit log: item created
    await AuditService.logFromRequest(req, 'item.create', {
      resourceType: 'item',
      resourceId: item.id,
      description: `Created item: ${item.name}`,
      metadata: {
        category: item.category,
        warranty_months: item.warranty_months,
      },
    });

    sendSuccess(res, await normalizeItemRow(item), { status: 201 });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

// Update item — keyed-allowlist update, atomic warranty recompute, ownership
// check on home_id moves (audit Ch02-F011/F012/F017/F018).
router.put('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), validate(updateItemSchema), idempotency('items:update'), asyncHandler(async (req: AuthRequest, res) => {
  const { id } = req.params;
  const updates = req.body;

  // Audit Ch02-F017: column generation now drives off a single source of
  // truth (the field map). Adding a column means adding it once.
  const fieldMapping: Record<string, string> = {
    homeId: 'home_id',
    name: 'name',
    brand: 'brand',
    modelNumber: 'model_number',
    serialNumber: 'serial_number',
    category: 'category',
    room: 'room',
    purchaseDate: 'purchase_date',
    store: 'store',
    price: 'price',
    warrantyMonths: 'warranty_months',
    warrantyType: 'warranty_type',
    warrantyProvider: 'warranty_provider',
    notes: 'notes',
    isArchived: 'is_archived',
    // S-CR-02: product_image_url is intentionally NOT in the user-update
    // allowlist. POST /uploads/item-image is the only path that writes it.
    barcode: 'barcode',
    installationDate: 'installation_date',
    lastMaintenanceDate: 'last_maintenance_date',
    nextMaintenanceDue: 'next_maintenance_due',
    // addedVia intentionally excluded — write-once audit field
  };

  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Audit Ch02-F012: when home_id changes, verify the target home belongs
    // to the same user. Performed inside the txn so a concurrent home
    // delete can't slip through after the check.
    if (updates.homeId !== undefined) {
      const homeRes = await client.query(
        `SELECT id FROM homes WHERE id = $1 AND user_id = $2 FOR SHARE`,
        [updates.homeId, req.user!.id],
      );
      if (homeRes.rows.length === 0) {
        throw new AppError('Home not found', 404);
      }
    }

    const fields: string[] = [];
    const values: any[] = [];
    let paramCount = 1;

    for (const [camelKey, value] of Object.entries(updates)) {
      const dbField = fieldMapping[camelKey];
      if (dbField && ALLOWED_UPDATE_FIELDS.has(dbField)) {
        fields.push(`${dbField} = $${paramCount}`);
        values.push(value);
        paramCount++;
      }
    }

    if (fields.length === 0) {
      throw new AppError('No valid fields to update', 400);
    }

    // Audit Ch02-F011: warranty recompute lives in the same txn, no extra
    // round-trip outside.
    if (updates.warrantyMonths !== undefined || updates.purchaseDate !== undefined) {
      if (updates.purchaseDate === null || updates.purchaseDate === '') {
        // Caller cleared purchase_date → wipe warranty_end_date too.
        fields.push(`warranty_end_date = $${paramCount}`);
        values.push(null);
        paramCount++;
      } else {
        let purchaseDateForCalc: Date | null = updates.purchaseDate
          ? new Date(updates.purchaseDate)
          : null;
        let warrantyMonthsForCalc: number | null =
          updates.warrantyMonths !== undefined ? updates.warrantyMonths : null;

        if (!purchaseDateForCalc || warrantyMonthsForCalc === null) {
          const existing = await client.query(
            `SELECT purchase_date, warranty_months FROM items
             WHERE id = $1 AND user_id = $2 FOR UPDATE`,
            [id, req.user!.id],
          );
          if (existing.rows.length > 0) {
            if (!purchaseDateForCalc && existing.rows[0].purchase_date) {
              purchaseDateForCalc = new Date(existing.rows[0].purchase_date);
            }
            if (warrantyMonthsForCalc === null) {
              warrantyMonthsForCalc = existing.rows[0].warranty_months;
            }
          }
        }

        if (purchaseDateForCalc && warrantyMonthsForCalc !== null) {
          const warrantyEndDate = addMonthsSafe(purchaseDateForCalc, warrantyMonthsForCalc);
          fields.push(`warranty_end_date = $${paramCount}`);
          values.push(warrantyEndDate);
          paramCount++;
        }
      }
    }

    // Audit Ch02-F018: updated_at and archived_at are appended once. Don't
    // assign updated_at twice (would raise 42701 "duplicate column").
    fields.push('updated_at = NOW()');
    if (updates.isArchived !== undefined) {
      fields.push(updates.isArchived ? 'archived_at = NOW()' : 'archived_at = NULL');
    }

    values.push(id, req.user!.id);

    const result = await client.query(
      `UPDATE items SET ${fields.join(', ')}
       WHERE id = $${paramCount} AND user_id = $${paramCount + 1}
       RETURNING ${ITEM_LIST_COLUMNS}`,
      values,
    );

    if (result.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    await client.query('COMMIT');

    const item = result.rows[0];

    // Audit log: item updated (outside txn — best-effort)
    await AuditService.logFromRequest(req, 'item.update', {
      resourceType: 'item',
      resourceId: item.id,
      description: `Updated item: ${item.name}`,
      metadata: {
        updated_fields: Object.keys(updates),
      },
    });

    sendSuccess(res, await normalizeItemRow(item));
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}));

// Delete item.
//
// 1.1: harvests every MinIO key the item owns (its product image, plus
// every attached document's main + thumbnail key) BEFORE the cascading
// SQL DELETE wipes the rows. Storage cleanup runs post-COMMIT and is
// best-effort — orphan recovery is a periodic GC sweep, not the
// request path.
router.delete('/:id', writeRateLimiter, validate(uuidParamSchema, 'params'), idempotency('items:delete'), asyncHandler(async (req: AuthRequest, res) => {
  const client = await getClient();
  let harvest: Awaited<ReturnType<typeof harvestItemKeys>> | null = null;
  let item: { id: string; name: string; category: string } | null = null;
  try {
    await client.query('BEGIN');

    // Get item details before deleting for audit log
    const itemResult = await client.query(
      `SELECT id, name, category FROM items WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    if (itemResult.rows.length === 0) {
      throw new AppError('Item not found', 404);
    }

    item = itemResult.rows[0];

    // Harvest every storage key while we still have rows to look at.
    harvest = await harvestItemKeys(client, item!.id);

    // Delete related records first (child tables)
    await client.query(`DELETE FROM documents WHERE item_id = $1 AND user_id = $2`, [item!.id, req.user!.id]);
    await client.query(`DELETE FROM maintenance_history WHERE item_id = $1 AND user_id = $2`, [item!.id, req.user!.id]);
    await client.query(`DELETE FROM warranty_claims WHERE item_id = $1 AND user_id = $2`, [item!.id, req.user!.id]);
    await client.query(`DELETE FROM warranty_purchases WHERE item_id = $1 AND user_id = $2`, [item!.id, req.user!.id]);
    await client.query(`DELETE FROM notification_history WHERE item_id = $1 AND user_id = $2`, [item!.id, req.user!.id]);

    // Delete the item itself
    await client.query(
      `DELETE FROM items WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.user!.id]
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  // Post-commit cleanup. Storage failures are logged but don't fail
  // the request — the SQL DELETE already succeeded.
  if (harvest) {
    await removeKeysBestEffort(flattenHarvest(harvest));
  }

  // Audit log: item deleted (fire-and-forget, outside transaction)
  if (item) {
    AuditService.logFromRequest(req, 'item.delete', {
      resourceType: 'item',
      resourceId: item.id,
      description: `Deleted item: ${item.name}`,
      metadata: { category: item.category },
    }).catch((err) => {
      logger.error({ err }, 'Failed to log item.delete audit event');
    });
  }

  sendMessage(res, 'Item deleted successfully');
}));

export default router;
