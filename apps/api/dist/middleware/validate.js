"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validate = validate;
const errors_1 = require("../utils/errors");
function validate(schema, property = 'body') {
    return (req, res, next) => {
        // NOTE: stripUnknown silently removes unrecognized fields, which can mask client bugs
        // (e.g., sending 'fullname' instead of 'fullName'). Consider setting allowUnknown: false
        // in development/staging to surface these issues early.
        const { error, value } = schema.validate(req[property], {
            abortEarly: false,
            stripUnknown: true,
        });
        if (error) {
            const errors = error.details.map(detail => ({
                field: detail.path.join('.'),
                message: detail.message,
            }));
            throw new errors_1.ValidationError('Validation failed', errors);
        }
        // Replace request property with validated and sanitized value
        req[property] = value;
        next();
    };
}
//# sourceMappingURL=validate.js.map