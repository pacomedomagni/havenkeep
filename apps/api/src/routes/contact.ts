import { Router } from 'express';
import Joi from 'joi';
import { pool } from '../db';
import { logger } from '../utils/logger';
import { validate } from '../middleware/validate';
import { asyncHandler } from '../utils/async-handler';
import { EmailService } from '../services/email.service';
import { contactRateLimiter } from '../middleware/rateLimiter';
import { sendMessage } from '../utils/response';

const router = Router();

// Joi schema for contact form submissions
const contactSchema = Joi.object({
  name: Joi.string().trim().min(1).max(255).required().messages({
    'string.empty': 'Name is required',
    'string.max': 'Name must be 255 characters or fewer',
    'any.required': 'Name is required',
  }),
  email: Joi.string().trim().email().max(255).required().messages({
    'string.email': 'Please provide a valid email address',
    'string.max': 'Email must be 255 characters or fewer',
    'any.required': 'Email is required',
  }),
  subject: Joi.string()
    .trim()
    .valid(
      'Technical Support',
      'Billing Question',
      'Feature Request',
      'Partnership Inquiry',
      'Other'
    )
    .required()
    .messages({
      'any.only': 'Please select a valid subject',
      'any.required': 'Subject is required',
    }),
  message: Joi.string().trim().min(10).max(5000).required().messages({
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
router.post(
  '/',
  contactRateLimiter,
  validate(contactSchema),
  asyncHandler(async (req, res) => {
    const { name, email, subject, message } = req.body;

    // Store the submission in the database
    await pool.query(
      `INSERT INTO contact_submissions (name, email, subject, message, ip_address)
       VALUES ($1, $2, $3, $4, $5)`,
      [name, email, subject, message, req.ip || null]
    );

    // Send notification email to support
    try {
      await EmailService.sendContactNotificationEmail({
        name,
        email,
        subject,
        message,
      });
    } catch (emailError) {
      // Log the email failure but don't fail the request --
      // the submission is already persisted in the database.
      logger.error({ error: emailError, email }, 'Failed to send contact notification email');
    }

    logger.info({ email, subject }, 'Contact form submission received');

    return sendMessage(res, 'Message sent successfully. We will get back to you within 24 hours.');
  })
);

export default router;
