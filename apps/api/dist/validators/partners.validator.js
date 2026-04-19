"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getCommissionsQuerySchema = exports.getGiftsQuerySchema = exports.createGiftSchema = exports.updatePartnerSchema = exports.registerPartnerSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.registerPartnerSchema = joi_1.default.object({
    partnerType: joi_1.default.string()
        .valid('realtor', 'builder', 'contractor', 'property_manager', 'other')
        .required(),
    companyName: joi_1.default.string().max(255).optional(),
    phone: joi_1.default.string().max(50).optional(),
    website: joi_1.default.string().uri().max(255).optional(),
    brandColor: joi_1.default.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
    logoUrl: joi_1.default.string().uri().optional(),
    defaultMessage: joi_1.default.string().max(1000).optional(),
    serviceAreas: joi_1.default.array().items(joi_1.default.string().max(100)).optional(),
    licenseNumber: joi_1.default.string().max(100).allow(null, ''),
})
    // Accept snake_case from clients
    .rename('partner_type', 'partnerType', { ignoreUndefined: true, override: false })
    .rename('company_name', 'companyName', { ignoreUndefined: true, override: false })
    .rename('brand_color', 'brandColor', { ignoreUndefined: true, override: false })
    .rename('logo_url', 'logoUrl', { ignoreUndefined: true, override: false })
    .rename('default_message', 'defaultMessage', { ignoreUndefined: true, override: false })
    .rename('service_areas', 'serviceAreas', { ignoreUndefined: true, override: false })
    .rename('license_number', 'licenseNumber', { ignoreUndefined: true, override: false });
exports.updatePartnerSchema = joi_1.default.object({
    partnerType: joi_1.default.string().valid('realtor', 'builder', 'contractor', 'property_manager', 'other'),
    companyName: joi_1.default.string().max(255).optional(),
    phone: joi_1.default.string().max(50).optional(),
    website: joi_1.default.string().uri().max(255).optional(),
    brandColor: joi_1.default.string().pattern(/^#[0-9A-F]{6}$/i).optional(),
    logoUrl: joi_1.default.string().uri().optional(),
    defaultMessage: joi_1.default.string().max(1000).optional(),
    defaultPremiumMonths: joi_1.default.number().integer().min(1).max(12).optional(),
    serviceAreas: joi_1.default.array().items(joi_1.default.string().max(100)).optional(),
    licenseNumber: joi_1.default.string().max(100).allow(null, ''),
}).min(1)
    // Accept snake_case from clients
    .rename('partner_type', 'partnerType', { ignoreUndefined: true, override: false })
    .rename('company_name', 'companyName', { ignoreUndefined: true, override: false })
    .rename('brand_color', 'brandColor', { ignoreUndefined: true, override: false })
    .rename('logo_url', 'logoUrl', { ignoreUndefined: true, override: false })
    .rename('default_message', 'defaultMessage', { ignoreUndefined: true, override: false })
    .rename('default_premium_months', 'defaultPremiumMonths', { ignoreUndefined: true, override: false })
    .rename('service_areas', 'serviceAreas', { ignoreUndefined: true, override: false })
    .rename('license_number', 'licenseNumber', { ignoreUndefined: true, override: false });
exports.createGiftSchema = joi_1.default.object({
    homebuyerEmail: joi_1.default.string().email().required(),
    homebuyerName: joi_1.default.string().max(255).required(),
    homebuyerPhone: joi_1.default.string().max(50).optional(),
    homeAddress: joi_1.default.string().max(500).optional(),
    closingDate: joi_1.default.date().iso().optional(),
    premiumMonths: joi_1.default.number().integer().min(1).max(12).optional(),
    customMessage: joi_1.default.string().max(1000).optional(),
})
    // Accept snake_case from clients
    .rename('homebuyer_email', 'homebuyerEmail', { ignoreUndefined: true, override: false })
    .rename('homebuyer_name', 'homebuyerName', { ignoreUndefined: true, override: false })
    .rename('homebuyer_phone', 'homebuyerPhone', { ignoreUndefined: true, override: false })
    .rename('home_address', 'homeAddress', { ignoreUndefined: true, override: false })
    .rename('closing_date', 'closingDate', { ignoreUndefined: true, override: false })
    .rename('premium_months', 'premiumMonths', { ignoreUndefined: true, override: false })
    .rename('custom_message', 'customMessage', { ignoreUndefined: true, override: false });
exports.getGiftsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
    status: joi_1.default.string().valid('created', 'sent', 'activated', 'expired', 'pending_payment').optional(),
});
exports.getCommissionsQuerySchema = joi_1.default.object({
    limit: joi_1.default.number().integer().min(1).max(100).optional().default(50),
    offset: joi_1.default.number().integer().min(0).optional().default(0),
});
//# sourceMappingURL=partners.validator.js.map