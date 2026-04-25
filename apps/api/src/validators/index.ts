import Joi from 'joi';
import { config } from '../config';
import { passwordSchema, emailSchema } from './auth.validator';

// Auth Validators — share the anchored password rule with auth.validator
// so a single grep finds every entry point that enforces complexity (Ch01-F001).
export const registerSchema = Joi.object({
  email: emailSchema,
  password: passwordSchema,
  fullName: Joi.string().trim().min(1).max(255).required(),
  referralCode: Joi.string().trim().max(64).optional(),
})
  .rename('full_name', 'fullName', { ignoreUndefined: true, override: false })
  .rename('referral_code', 'referralCode', { ignoreUndefined: true, override: false });

// Login: cap password length so an attacker can't ship a 100MB body and tie
// the bcrypt path up. The actual `>72 byte` truncation is handled by the
// service via SHA-256 pre-hash (Ch01-F003 / F005).
export const loginSchema = Joi.object({
  email: emailSchema,
  password: Joi.string().min(1).max(1024).required(),
});

// Refresh token bound to 4096 chars — JWT refresh tokens we issue are ~250
// chars, but a third-party client could feed garbage. (Ch01-F079)
export const refreshTokenSchema = Joi.object({
  refreshToken: Joi.string().min(20).max(4096).required(),
})
  .rename('refresh_token', 'refreshToken', { ignoreUndefined: true, override: false });

// Item Validators
// Audit Ch02-F058/F060/F061: install/maintenance date ordering enforced by
// these helpers. `purchaseDate` must be ≤ now (TZ-naive), and
// `lastMaintenanceDate` must be ≥ `installationDate` when both are present.
const itemDatesConsistent: Joi.CustomValidator<any> = (value, helpers) => {
  const install = value.installationDate ? new Date(value.installationDate) : null;
  const lastMaint = value.lastMaintenanceDate ? new Date(value.lastMaintenanceDate) : null;
  const nextMaint = value.nextMaintenanceDue ? new Date(value.nextMaintenanceDue) : null;
  const purchase = value.purchaseDate ? new Date(value.purchaseDate) : null;

  if (install && lastMaint && lastMaint.getTime() < install.getTime()) {
    return helpers.error('any.invalid', { message: 'lastMaintenanceDate must be on or after installationDate' });
  }
  if (purchase && nextMaint && nextMaint.getTime() < purchase.getTime()) {
    return helpers.error('any.invalid', { message: 'nextMaintenanceDue must be on or after purchaseDate' });
  }
  return value;
};

export const createItemSchema = Joi.object({
  homeId: Joi.string().uuid().required(),
  name: Joi.string().min(1).max(255).required(),
  brand: Joi.string().max(100).allow(null, ''),
  modelNumber: Joi.string().max(100).allow(null, ''),
  serialNumber: Joi.string().max(100).allow(null, ''),
  category: Joi.string().valid(
    'refrigerator', 'dishwasher', 'washer', 'dryer',
    'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
    'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
    'tv', 'computer', 'smart_home',
    'roofing', 'windows', 'doors', 'flooring',
    'plumbing', 'electrical',
    'furniture',
    'air_purifier', 'vacuum', 'ceiling_fan', 'smoke_detector',
    'security_system', 'garage_door_opener', 'power_tools', 'lawn_mower',
    'pool_equipment', 'grill', 'coffee_maker', 'home_theater',
    'printer', 'networking', 'camera', 'lighting',
    'dehumidifier', 'freezer', 'wine_cooler', 'trash_compactor',
    'other'
  ).default('other'),
  room: Joi.string().valid(
    'kitchen', 'bathroom', 'master_bedroom', 'bedroom',
    'living_room', 'dining_room', 'laundry',
    'garage', 'basement', 'attic',
    'outdoor', 'hvac_utility', 'office', 'other'
  ).allow(null),
  purchaseDate: Joi.date().min('1970-01-01').max('now').required(),
  store: Joi.string().max(100).allow(null, ''),
  price: Joi.number().min(0).max(999999.99).allow(null),
  warrantyMonths: Joi.number().integer().min(0).max(600).default(12),
  warrantyType: Joi.string().valid('manufacturer', 'extended', 'store', 'home_warranty').default('manufacturer'),
  warrantyProvider: Joi.string().max(100).allow(null, ''),
  notes: Joi.string().max(5000).allow(null, ''),
  productImageUrl: Joi.string().uri().max(500).allow(null, ''),
  barcode: Joi.string().max(100).allow(null, ''),
  addedVia: Joi.string()
    .valid('manual', 'email', 'barcode', 'barcode_scan', 'receipt_scan', 'quick_add', 'bulk_setup')
    .default('manual'),
  installationDate: Joi.date().min('1970-01-01').max('now').allow(null),
  lastMaintenanceDate: Joi.date().min('1970-01-01').max('now').allow(null),
  nextMaintenanceDue: Joi.date().min('1970-01-01').allow(null),
})
  .custom(itemDatesConsistent, 'item date ordering')
  // Accept snake_case from mobile clients
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false })
  .rename('model_number', 'modelNumber', { ignoreUndefined: true, override: false })
  .rename('serial_number', 'serialNumber', { ignoreUndefined: true, override: false })
  .rename('purchase_date', 'purchaseDate', { ignoreUndefined: true, override: false })
  .rename('warranty_months', 'warrantyMonths', { ignoreUndefined: true, override: false })
  .rename('warranty_type', 'warrantyType', { ignoreUndefined: true, override: false })
  .rename('warranty_provider', 'warrantyProvider', { ignoreUndefined: true, override: false })
  .rename('product_image_url', 'productImageUrl', { ignoreUndefined: true, override: false })
  .rename('added_via', 'addedVia', { ignoreUndefined: true, override: false })
  .rename('installation_date', 'installationDate', { ignoreUndefined: true, override: false })
  .rename('last_maintenance_date', 'lastMaintenanceDate', { ignoreUndefined: true, override: false })
  .rename('next_maintenance_due', 'nextMaintenanceDue', { ignoreUndefined: true, override: false });

export const updateItemSchema = Joi.object({
  homeId: Joi.string().uuid(),
  name: Joi.string().min(1).max(255),
  brand: Joi.string().max(100).allow(null, ''),
  modelNumber: Joi.string().max(100).allow(null, ''),
  serialNumber: Joi.string().max(100).allow(null, ''),
  category: Joi.string().valid(
    'refrigerator', 'dishwasher', 'washer', 'dryer',
    'oven_range', 'microwave', 'garbage_disposal', 'range_hood',
    'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump',
    'tv', 'computer', 'smart_home',
    'roofing', 'windows', 'doors', 'flooring',
    'plumbing', 'electrical',
    'furniture',
    'air_purifier', 'vacuum', 'ceiling_fan', 'smoke_detector',
    'security_system', 'garage_door_opener', 'power_tools', 'lawn_mower',
    'pool_equipment', 'grill', 'coffee_maker', 'home_theater',
    'printer', 'networking', 'camera', 'lighting',
    'dehumidifier', 'freezer', 'wine_cooler', 'trash_compactor',
    'other'
  ),
  room: Joi.string().valid(
    'kitchen', 'bathroom', 'master_bedroom', 'bedroom',
    'living_room', 'dining_room', 'laundry',
    'garage', 'basement', 'attic',
    'outdoor', 'hvac_utility', 'office', 'other'
  ).allow(null),
  purchaseDate: Joi.date().min('1970-01-01').max('now'),
  store: Joi.string().max(100).allow(null, ''),
  price: Joi.number().min(0).max(999999.99).allow(null),
  warrantyMonths: Joi.number().integer().min(0).max(600),
  warrantyType: Joi.string().valid('manufacturer', 'extended', 'store', 'home_warranty'),
  warrantyProvider: Joi.string().max(100).allow(null, ''),
  notes: Joi.string().max(5000).allow(null, ''),
  isArchived: Joi.boolean(),
  productImageUrl: Joi.string().uri().max(500).allow(null, ''),
  barcode: Joi.string().max(100).allow(null, ''),
  // addedVia intentionally excluded — it is a write-once audit field set at creation
  installationDate: Joi.date().min('1970-01-01').max('now').allow(null),
  lastMaintenanceDate: Joi.date().min('1970-01-01').max('now').allow(null),
  nextMaintenanceDue: Joi.date().min('1970-01-01').allow(null),
}).min(1) // At least one field must be provided
  .custom(itemDatesConsistent, 'item date ordering')
  // Accept snake_case from mobile clients
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false })
  .rename('model_number', 'modelNumber', { ignoreUndefined: true, override: false })
  .rename('serial_number', 'serialNumber', { ignoreUndefined: true, override: false })
  .rename('purchase_date', 'purchaseDate', { ignoreUndefined: true, override: false })
  .rename('warranty_months', 'warrantyMonths', { ignoreUndefined: true, override: false })
  .rename('warranty_type', 'warrantyType', { ignoreUndefined: true, override: false })
  .rename('warranty_provider', 'warrantyProvider', { ignoreUndefined: true, override: false })
  .rename('is_archived', 'isArchived', { ignoreUndefined: true, override: false })
  .rename('product_image_url', 'productImageUrl', { ignoreUndefined: true, override: false })
  .rename('installation_date', 'installationDate', { ignoreUndefined: true, override: false })
  .rename('last_maintenance_date', 'lastMaintenanceDate', { ignoreUndefined: true, override: false })
  .rename('next_maintenance_due', 'nextMaintenanceDue', { ignoreUndefined: true, override: false });

// Home Validators
export const createHomeSchema = Joi.object({
  name: Joi.string().min(1).max(255).required(),
  // Ch08-Home-D006: DB column is TEXT (unlimited) — keep a generous upper
  // bound so multi-line "address line 1 / line 2 / unit" entries don't bounce.
  address: Joi.string().max(2000).allow(null, ''),
  city: Joi.string().max(100).allow(null, ''),
  state: Joi.string().max(50).allow(null, ''),
  zip: Joi.string().max(20).allow(null, ''),
  homeType: Joi.string().valid('house', 'condo', 'apartment', 'townhouse', 'other').default('house'),
  moveInDate: Joi.date().max('now').allow(null),
})
  .rename('home_type', 'homeType', { ignoreUndefined: true, override: false })
  .rename('move_in_date', 'moveInDate', { ignoreUndefined: true, override: false });

export const updateHomeSchema = Joi.object({
  name: Joi.string().min(1).max(255),
  // Ch08-Home-D006: DB column is TEXT (unlimited) — keep a generous upper
  // bound so multi-line "address line 1 / line 2 / unit" entries don't bounce.
  address: Joi.string().max(2000).allow(null, ''),
  city: Joi.string().max(100).allow(null, ''),
  state: Joi.string().max(50).allow(null, ''),
  zip: Joi.string().max(20).allow(null, ''),
  homeType: Joi.string().valid('house', 'condo', 'apartment', 'townhouse', 'other'),
  moveInDate: Joi.date().max('now').allow(null),
}).min(1)
  .rename('home_type', 'homeType', { ignoreUndefined: true, override: false })
  .rename('move_in_date', 'moveInDate', { ignoreUndefined: true, override: false });

// Audit Ch01-F073: hostname `.includes(endpoint)` accepted any domain that
// has the endpoint as a substring (e.g. `minio.evil.com` if endpoint is
// `minio`). Compare exact host or pre-approved suffix. Trailing port is
// stripped before compare. ALLOWED_AVATAR_HOSTS is the explicit allowlist.
const ALLOWED_AVATAR_HOSTS = new Set<string>([
  config.minio.endpoint.toLowerCase(),
  // Public OAuth provider avatar CDNs that we accept verbatim.
  'lh3.googleusercontent.com',
  'lh4.googleusercontent.com',
  'lh5.googleusercontent.com',
  'lh6.googleusercontent.com',
  'avatars.slack-edge.com',
  'gravatar.com',
  'www.gravatar.com',
]);

function avatarHostAllowed(host: string): boolean {
  const h = host.toLowerCase();
  if (ALLOWED_AVATAR_HOSTS.has(h)) return true;
  // Allow direct match against MINIO_PUBLIC_URL host if configured.
  const publicUrl = process.env.MINIO_PUBLIC_URL;
  if (publicUrl) {
    try { if (new URL(publicUrl).host.toLowerCase() === h) return true; } catch { /* ignore */ }
  }
  return false;
}

// User Validators
export const updateUserSchema = Joi.object({
  fullName: Joi.string().trim().min(1).max(255),
  avatarUrl: Joi.string().uri({ scheme: ['http', 'https'] }).max(500).allow(null, '')
    .custom((value, helpers) => {
      if (!value) return value;
      try {
        const url = new URL(value);
        if (!avatarHostAllowed(url.hostname)) {
          return helpers.error('any.invalid');
        }
      } catch {
        return helpers.error('any.invalid');
      }
      return value;
    }, 'avatar URL host allowlist'),
}).min(1)
  .rename('full_name', 'fullName', { ignoreUndefined: true, override: false })
  .rename('avatar_url', 'avatarUrl', { ignoreUndefined: true, override: false });

// Document Validators
//
// Audit Ch02-F067: tighten schema so unknown fields are rejected (do NOT rely
// on `validate()` global stripUnknown). The route registers multer first and
// validates after — Ch02-F068 — so the schema only sees fields parsed from
// multipart text segments.
export const uploadDocumentSchema = Joi.object({
  itemId: Joi.string().uuid().required(),
  type: Joi.string().valid('receipt', 'warranty_card', 'manual', 'invoice', 'other').default('other'),
})
  .unknown(false)
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });

// Audit Ch08-Document-D020: PUT /documents/:id needs a schema. Only the
// fields a user is allowed to retitle / re-tag are accepted; file_url and
// file_size are write-once and re-uploaded via /documents/upload, never
// patched in place.
export const updateDocumentSchema = Joi.object({
  type: Joi.string().valid('receipt', 'warranty_card', 'manual', 'invoice', 'other'),
  fileName: Joi.string().min(1).max(255),
  itemId: Joi.string().uuid().allow(null),
}).min(1)
  .unknown(false)
  .rename('file_name', 'fileName', { ignoreUndefined: true, override: false })
  .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });

// Audit Ch02-F042/F047/Ch09-FlowA-T-A6/A13: receipts/scan body validator.
// `image` must be base64 (full-string check, not first-100-char prefix), and
// the optional `mimeType` field constrains the data: URL we hand OpenAI
// (which previously hard-coded image/jpeg regardless of the actual file).
export const receiptScanSchema = Joi.object({
  image: Joi.string()
    .min(64)
    .max(7_500_000) // ~5MB after base64 expansion (5MB * 1.37 ≈ 6.85MB; cap a bit higher to absorb wrapping)
    .pattern(/^[A-Za-z0-9+/]+={0,2}$/) // strict base64; padding 0–2 trailing '='
    .required(),
  mimeType: Joi.string()
    .valid('image/jpeg', 'image/png', 'image/webp')
    .default('image/jpeg'),
})
  .unknown(false)
  .rename('mime_type', 'mimeType', { ignoreUndefined: true, override: false });

// Push Token Validators
export const pushTokenSchema = Joi.object({
  fcmToken: Joi.string().min(1).max(512).required(),
  platform: Joi.string().valid('ios', 'android', 'web', 'unknown').default('unknown'),
})
  .rename('fcm_token', 'fcmToken', { ignoreUndefined: true, override: false });

// Engagement Tracking Validators
export const trackEngagementSchema = Joi.object({
  type: Joi.string().min(1).max(100).required(),
  sessionDuration: Joi.number().integer().min(0).max(86400).allow(null),
})
  .rename('session_duration', 'sessionDuration', { ignoreUndefined: true, override: false });

// Feature Tracking Validators
export const trackFeatureSchema = Joi.object({
  feature: Joi.string().min(1).max(100).required(),
});

// Query Validators
// Audit Ch01-F064: paginationSchema was reused on partner-list / commission
// routes that pass `partner_type` / `is_active`, which the old schema would
// silently strip. Add them as explicit known query params so the validator
// is a single source of truth for "what query keys are accepted".
// Audit Ch12-T043/T044: sort/order params constrained to a closed allowlist so
// hostile values can't be concatenated into SQL. `cursor` is base64-encoded
// for keyset pagination (Ch02-F009) — opaque to clients.
export const paginationSchema = Joi.object({
  page: Joi.number().integer().min(1).max(100_000).default(1),
  limit: Joi.number().integer().min(1).max(100).default(20),
  cursor: Joi.string().base64({ paddingRequired: false, urlSafe: true }).max(512),
  sort: Joi.string().valid('warranty_end_date', 'created_at', 'name', 'price').default('warranty_end_date'),
  order: Joi.string().valid('asc', 'desc').default('asc'),
  homeId: Joi.string().uuid(),
  archived: Joi.string().valid('true', 'false'),
  addedVia: Joi.string().valid(
    'manual', 'email', 'barcode', 'barcode_scan', 'receipt_scan', 'quick_add', 'bulk_setup'
  ),
  // Filters used by admin routes — accepted here so validate() doesn't strip.
  partner_type: Joi.string().valid('realtor', 'builder', 'contractor', 'property_manager', 'other'),
  is_active: Joi.string().valid('true', 'false'),
  // `status` is shared between the partners listing (pending/active/rejected,
  // audit Ch10-W054) and the commissions listing (pending/approved/paid/
  // cancelled/reversed). The route handler narrows further to the values
  // its own table accepts.
  status: Joi.string().valid(
    'pending', 'approved', 'paid', 'cancelled', 'reversed', 'active', 'rejected'
  ),
  partner_id: Joi.string().uuid(),
})
  .rename('home_id', 'homeId', { ignoreUndefined: true, override: false })
  .rename('added_via', 'addedVia', { ignoreUndefined: true, override: false });

// Audit Ch01-F067: hand-rolled UUID regex on individual routes drifts. Joi's
// .uuid() validates per RFC 4122 — use it everywhere.
export const uuidParamSchema = Joi.object({
  id: Joi.string().uuid().required(),
});

// Audit Ch02-F053: CSV export accepts `?archived=true|false|all` so callers
// have to ask explicitly for archived rows; default omits them.
export const csvExportQuerySchema = Joi.object({
  archived: Joi.string().valid('true', 'false', 'all').default('false'),
});
