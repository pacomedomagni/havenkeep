"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getCommissionsQuerySchema = exports.getGiftsQuerySchema = exports.createGiftSchema = exports.updatePartnerSchema = exports.registerPartnerSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.registerPartnerSchema = joi_1.default.object({
    partner_type: joi_1.default.string()
        .valid('realtor', 'builder', 'contractor', 'property_manager', 'other')
        .required(),
    company_name: joi_1.default.string().max(255).optional(),
    phone: joi_1.default.string().max(50).optional(),
    website: joi_1.default.string().uri().max(255).optional(),
    brand_color: joi_1.default.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
    logo_url: joi_1.default.string().uri().optional(),
    default_message: joi_1.default.string().max(1000).optional(),
    service_areas: joi_1.default.array().items(joi_1.default.string().max(100)).optional(),
})
    // Accept camelCase from dashboard clients
    .rename('partnerType', 'partner_type', { ignoreUndefined: true, override: false })
    .rename('companyName', 'company_name', { ignoreUndefined: true, override: false })
    .rename('brandColor', 'brand_color', { ignoreUndefined: true, override: false })
    .rename('logoUrl', 'logo_url', { ignoreUndefined: true, override: false })
    .rename('defaultMessage', 'default_message', { ignoreUndefined: true, override: false })
    .rename('serviceAreas', 'service_areas', { ignoreUndefined: true, override: false });
exports.updatePartnerSchema = joi_1.default.object({
    partner_type: joi_1.default.string().valid('realtor', 'builder', 'contractor', 'property_manager', 'other'),
    company_name: joi_1.default.string().max(255).optional(),
    phone: joi_1.default.string().max(50).optional(),
    website: joi_1.default.string().uri().max(255).optional(),
    brand_color: joi_1.default.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
    logo_url: joi_1.default.string().uri().optional(),
    default_message: joi_1.default.string().max(1000).optional(),
    default_premium_months: joi_1.default.number().integer().min(1).max(12).optional(),
    service_areas: joi_1.default.array().items(joi_1.default.string().max(100)).optional(),
}).min(1)
    // Accept camelCase from dashboard clients
    .rename('companyName', 'company_name', { ignoreUndefined: true, override: false })
    .rename('brandColor', 'brand_color', { ignoreUndefined: true, override: false })
    .rename('logoUrl', 'logo_url', { ignoreUndefined: true, override: false })
    .rename('defaultMessage', 'default_message', { ignoreUndefined: true, override: false })
    .rename('defaultPremiumMonths', 'default_premium_months', { ignoreUndefined: true, override: false })
    .rename('serviceAreas', 'service_areas', { ignoreUndefined: true, override: false });
exports.createGiftSchema = joi_1.default.object({
    homebuyer_email: joi_1.default.string().email().required(),
    homebuyer_name: joi_1.default.string().max(255).required(),
    homebuyer_phone: joi_1.default.string().max(50).optional(),
    home_address: joi_1.default.string().max(500).optional(),
    closing_date: joi_1.default.date().iso().optional(),
    premium_months: joi_1.default.number().integer().min(1).max(12).optional(),
    custom_message: joi_1.default.string().max(1000).optional(),
})
    // Accept camelCase from dashboard clients
    .rename('homebuyerEmail', 'homebuyer_email', { ignoreUndefined: true, override: false })
    .rename('homebuyerName', 'homebuyer_name', { ignoreUndefined: true, override: false })
    .rename('homebuyerPhone', 'homebuyer_phone', { ignoreUndefined: true, override: false })
    .rename('homeAddress', 'home_address', { ignoreUndefined: true, override: false })
    .rename('closingDate', 'closing_date', { ignoreUndefined: true, override: false })
    .rename('premiumMonths', 'premium_months', { ignoreUndefined: true, override: false })
    .rename('customMessage', 'custom_message', { ignoreUndefined: true, override: false });
exports.getGiftsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    status: joi_1.default.string().valid('created', 'sent', 'activated', 'expired').optional(),
});
exports.getCommissionsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
});
//# sourceMappingURL=partners.validator.js.map