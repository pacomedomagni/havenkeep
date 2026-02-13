"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.barcodeLookupSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.barcodeLookupSchema = joi_1.default.object({
    barcode: joi_1.default.string()
        .pattern(/^[0-9]{8,14}$/)
        .required()
        .messages({
        'string.pattern.base': 'Barcode must be 8-14 digits',
        'any.required': 'Barcode is required',
    }),
});
//# sourceMappingURL=barcode.js.map