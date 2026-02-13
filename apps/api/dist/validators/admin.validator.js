"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.dateRangeQuerySchema = exports.userIdParamSchema = void 0;
const joi_1 = __importDefault(require("joi"));
exports.userIdParamSchema = joi_1.default.object({
    id: joi_1.default.string().uuid().required(),
});
exports.dateRangeQuerySchema = joi_1.default.object({
    days: joi_1.default.number().integer().min(1).max(365).default(30),
});
//# sourceMappingURL=admin.validator.js.map