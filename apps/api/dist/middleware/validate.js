"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validate = validate;
const errors_1 = require("../utils/errors");
function validate(schema, property = 'body') {
    return (req, res, next) => {
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