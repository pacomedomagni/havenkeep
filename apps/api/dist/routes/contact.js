"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const joi_1 = __importDefault(require("joi"));
const db_1 = require("../db");
const logger_1 = require("../utils/logger");
const validate_1 = require("../middleware/validate");
const async_handler_1 = require("../utils/async-handler");
const email_service_1 = require("../services/email.service");
const rateLimiter_1 = require("../middleware/rateLimiter");
const response_1 = require("../utils/response");
const router = (0, express_1.Router)();
// Joi schema for contact form submissions
const contactSchema = joi_1.default.object({
    name: joi_1.default.string().trim().min(1).max(255).required().messages({
        'string.empty': 'Name is required',
        'string.max': 'Name must be 255 characters or fewer',
        'any.required': 'Name is required',
    }),
    email: joi_1.default.string().trim().email().max(255).required().messages({
        'string.email': 'Please provide a valid email address',
        'string.max': 'Email must be 255 characters or fewer',
        'any.required': 'Email is required',
    }),
    subject: joi_1.default.string()
        .trim()
        .valid('Technical Support', 'Billing Question', 'Feature Request', 'Partnership Inquiry', 'Other')
        .required()
        .messages({
        'any.only': 'Please select a valid subject',
        'any.required': 'Subject is required',
    }),
    message: joi_1.default.string().trim().min(10).max(5000).required().messages({
        'string.empty': 'Message is required',
        'string.min': 'Message must be at least 10 characters',
        'string.max': 'Message must be 5000 characters or fewer',
        'any.required': 'Message is required',
    }),
});
/**
 * @route   POST /api/v1/contact
 * @desc    Submit a contact form message
 * @access  Public (no authentication required)
 */
router.post('/', rateLimiter_1.contactRateLimiter, (0, validate_1.validate)(contactSchema), (0, async_handler_1.asyncHandler)(async (req, res) => {
    const { name, email, subject, message } = req.body;
    // Store the submission in the database
    await db_1.pool.query(`INSERT INTO contact_submissions (name, email, subject, message, ip_address)
       VALUES ($1, $2, $3, $4, $5)`, [name, email, subject, message, req.ip || null]);
    // Send notification email to support
    try {
        await email_service_1.EmailService.sendContactNotificationEmail({
            name,
            email,
            subject,
            message,
        });
    }
    catch (emailError) {
        // Log the email failure but don't fail the request --
        // the submission is already persisted in the database.
        logger_1.logger.error({ error: emailError, email }, 'Failed to send contact notification email');
    }
    logger_1.logger.info({ email, subject }, 'Contact form submission received');
    return (0, response_1.sendMessage)(res, 'Message sent successfully. We will get back to you within 24 hours.');
}));
exports.default = router;
//# sourceMappingURL=contact.js.map