"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.uuidParamSchema = exports.paginationSchema = exports.trackFeatureSchema = exports.trackEngagementSchema = exports.pushTokenSchema = exports.uploadDocumentSchema = exports.updateUserSchema = exports.updateHomeSchema = exports.createHomeSchema = exports.updateItemSchema = exports.createItemSchema = exports.refreshTokenSchema = exports.loginSchema = exports.registerSchema = void 0;
const joi_1 = __importDefault(require("joi"));
const config_1 = require("../config");
// Auth Validators
exports.registerSchema = joi_1.default.object({
    email: joi_1.default.string().email().required().max(255),
    password: joi_1.default.string()
        .min(8)
        .max(128)
        .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
        .required()
        .messages({
        'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
        'string.min': 'Password must be at least 8 characters long',
    }),
    fullName: joi_1.default.string().min(1).max(255).required(),
    referralCode: joi_1.default.string().max(64).optional(),
})
    // Accept snake_case from mobile clients
    .rename('full_name', 'fullName', { ignoreUndefined: true, override: false })
    .rename('referral_code', 'referralCode', { ignoreUndefined: true, override: false });
exports.loginSchema = joi_1.default.object({
    email: joi_1.default.string().email().required(),
    password: joi_1.default.string().min(1).required(),
});
exports.refreshTokenSchema = joi_1.default.object({
    refreshToken: joi_1.default.string().required(),
})
    .rename('refresh_token', 'refreshToken', { ignoreUndefined: true, override: false });
// Item Validators
exports.createItemSchema = joi_1.default.object({
    homeId: joi_1.default.string().uuid().required(),
    name: joi_1.default.string().min(1).max(255).required(),
    brand: joi_1.default.string().max(100).allow(null, ''),
    modelNumber: joi_1.default.string().max(100).allow(null, ''),
    serialNumber: joi_1.default.string().max(100).allow(null, ''),
    category: joi_1.default.string().valid('refrigerator', 'dishwasher', 'washer', 'dryer', 'oven_range', 'microwave', 'garbage_disposal', 'range_hood', 'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump', 'tv', 'computer', 'smart_home', 'roofing', 'windows', 'doors', 'flooring', 'plumbing', 'electrical', 'furniture', 'air_purifier', 'vacuum', 'ceiling_fan', 'smoke_detector', 'security_system', 'garage_door_opener', 'power_tools', 'lawn_mower', 'pool_equipment', 'grill', 'coffee_maker', 'home_theater', 'printer', 'networking', 'camera', 'lighting', 'dehumidifier', 'freezer', 'wine_cooler', 'trash_compactor', 'other').default('other'),
    room: joi_1.default.string().valid('kitchen', 'bathroom', 'master_bedroom', 'bedroom', 'living_room', 'dining_room', 'laundry', 'garage', 'basement', 'attic', 'outdoor', 'hvac_utility', 'office', 'other').allow(null),
    purchaseDate: joi_1.default.date().min('1970-01-01').max('now').required(),
    store: joi_1.default.string().max(100).allow(null, ''),
    price: joi_1.default.number().min(0).max(999999.99).allow(null),
    warrantyMonths: joi_1.default.number().integer().min(0).max(600).default(12),
    warrantyType: joi_1.default.string().valid('manufacturer', 'extended', 'store', 'home_warranty').default('manufacturer'),
    warrantyProvider: joi_1.default.string().max(100).allow(null, ''),
    notes: joi_1.default.string().max(5000).allow(null, ''),
    productImageUrl: joi_1.default.string().uri().max(500).allow(null, ''),
    barcode: joi_1.default.string().max(100).allow(null, ''),
    addedVia: joi_1.default.string()
        .valid('manual', 'email', 'barcode', 'barcode_scan', 'receipt_scan', 'quick_add', 'bulk_setup')
        .default('manual'),
    installationDate: joi_1.default.date().min('1970-01-01').max('now').allow(null),
    lastMaintenanceDate: joi_1.default.date().min('1970-01-01').max('now').allow(null),
    nextMaintenanceDue: joi_1.default.date().min('1970-01-01').allow(null),
})
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
exports.updateItemSchema = joi_1.default.object({
    homeId: joi_1.default.string().uuid(),
    name: joi_1.default.string().min(1).max(255),
    brand: joi_1.default.string().max(100).allow(null, ''),
    modelNumber: joi_1.default.string().max(100).allow(null, ''),
    serialNumber: joi_1.default.string().max(100).allow(null, ''),
    category: joi_1.default.string().valid('refrigerator', 'dishwasher', 'washer', 'dryer', 'oven_range', 'microwave', 'garbage_disposal', 'range_hood', 'hvac', 'water_heater', 'furnace', 'water_softener', 'sump_pump', 'tv', 'computer', 'smart_home', 'roofing', 'windows', 'doors', 'flooring', 'plumbing', 'electrical', 'furniture', 'air_purifier', 'vacuum', 'ceiling_fan', 'smoke_detector', 'security_system', 'garage_door_opener', 'power_tools', 'lawn_mower', 'pool_equipment', 'grill', 'coffee_maker', 'home_theater', 'printer', 'networking', 'camera', 'lighting', 'dehumidifier', 'freezer', 'wine_cooler', 'trash_compactor', 'other'),
    room: joi_1.default.string().valid('kitchen', 'bathroom', 'master_bedroom', 'bedroom', 'living_room', 'dining_room', 'laundry', 'garage', 'basement', 'attic', 'outdoor', 'hvac_utility', 'office', 'other').allow(null),
    purchaseDate: joi_1.default.date().min('1970-01-01').max('now'),
    store: joi_1.default.string().max(100).allow(null, ''),
    price: joi_1.default.number().min(0).max(999999.99).allow(null),
    warrantyMonths: joi_1.default.number().integer().min(0).max(600),
    warrantyType: joi_1.default.string().valid('manufacturer', 'extended', 'store', 'home_warranty'),
    warrantyProvider: joi_1.default.string().max(100).allow(null, ''),
    notes: joi_1.default.string().max(5000).allow(null, ''),
    isArchived: joi_1.default.boolean(),
    productImageUrl: joi_1.default.string().uri().max(500).allow(null, ''),
    barcode: joi_1.default.string().max(100).allow(null, ''),
    // addedVia intentionally excluded — it is a write-once audit field set at creation
    installationDate: joi_1.default.date().min('1970-01-01').max('now').allow(null),
    lastMaintenanceDate: joi_1.default.date().min('1970-01-01').max('now').allow(null),
    nextMaintenanceDue: joi_1.default.date().min('1970-01-01').allow(null),
}).min(1) // At least one field must be provided
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
exports.createHomeSchema = joi_1.default.object({
    name: joi_1.default.string().min(1).max(255).required(),
    address: joi_1.default.string().max(500).allow(null, ''),
    city: joi_1.default.string().max(100).allow(null, ''),
    state: joi_1.default.string().max(50).allow(null, ''),
    zip: joi_1.default.string().max(20).allow(null, ''),
    homeType: joi_1.default.string().valid('house', 'condo', 'apartment', 'townhouse', 'other').default('house'),
    moveInDate: joi_1.default.date().max('now').allow(null),
})
    .rename('home_type', 'homeType', { ignoreUndefined: true, override: false })
    .rename('move_in_date', 'moveInDate', { ignoreUndefined: true, override: false });
exports.updateHomeSchema = joi_1.default.object({
    name: joi_1.default.string().min(1).max(255),
    address: joi_1.default.string().max(500).allow(null, ''),
    city: joi_1.default.string().max(100).allow(null, ''),
    state: joi_1.default.string().max(50).allow(null, ''),
    zip: joi_1.default.string().max(20).allow(null, ''),
    homeType: joi_1.default.string().valid('house', 'condo', 'apartment', 'townhouse', 'other'),
    moveInDate: joi_1.default.date().max('now').allow(null),
}).min(1)
    .rename('home_type', 'homeType', { ignoreUndefined: true, override: false })
    .rename('move_in_date', 'moveInDate', { ignoreUndefined: true, override: false });
// User Validators
exports.updateUserSchema = joi_1.default.object({
    fullName: joi_1.default.string().min(1).max(255),
    avatarUrl: joi_1.default.string().uri().max(500).allow(null, '')
        .custom((value, helpers) => {
        if (!value)
            return value;
        try {
            const url = new URL(value);
            if (!url.hostname.includes(config_1.config.minio.endpoint)) {
                return helpers.error('any.invalid');
            }
        }
        catch {
            return helpers.error('any.invalid');
        }
        return value;
    }, 'avatar URL domain validation'),
}).min(1)
    .rename('full_name', 'fullName', { ignoreUndefined: true, override: false })
    .rename('avatar_url', 'avatarUrl', { ignoreUndefined: true, override: false });
// Document Validators
exports.uploadDocumentSchema = joi_1.default.object({
    itemId: joi_1.default.string().uuid().required(),
    type: joi_1.default.string().valid('receipt', 'warranty_card', 'manual', 'invoice', 'other').default('other'),
})
    .rename('item_id', 'itemId', { ignoreUndefined: true, override: false });
// Push Token Validators
exports.pushTokenSchema = joi_1.default.object({
    fcmToken: joi_1.default.string().min(1).max(512).required(),
    platform: joi_1.default.string().valid('ios', 'android', 'web', 'unknown').default('unknown'),
})
    .rename('fcm_token', 'fcmToken', { ignoreUndefined: true, override: false });
// Engagement Tracking Validators
exports.trackEngagementSchema = joi_1.default.object({
    type: joi_1.default.string().min(1).max(100).required(),
    sessionDuration: joi_1.default.number().integer().min(0).max(86400).allow(null),
})
    .rename('session_duration', 'sessionDuration', { ignoreUndefined: true, override: false });
// Feature Tracking Validators
exports.trackFeatureSchema = joi_1.default.object({
    feature: joi_1.default.string().min(1).max(100).required(),
});
// Query Validators
exports.paginationSchema = joi_1.default.object({
    page: joi_1.default.number().integer().min(1).default(1),
    limit: joi_1.default.number().integer().min(1).max(100).default(20),
    homeId: joi_1.default.string().uuid(),
    archived: joi_1.default.string().valid('true', 'false'),
    addedVia: joi_1.default.string().valid('manual', 'email', 'barcode', 'barcode_scan', 'receipt_scan', 'quick_add', 'bulk_setup'),
})
    .rename('home_id', 'homeId', { ignoreUndefined: true, override: false })
    .rename('added_via', 'addedVia', { ignoreUndefined: true, override: false });
exports.uuidParamSchema = joi_1.default.object({
    id: joi_1.default.string().uuid().required(),
});
//# sourceMappingURL=index.js.map