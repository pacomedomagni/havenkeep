import Joi from 'joi';

// ============================================
// Audit Ch08-ContactSubmission-D081: contact route inlined its Joi schema.
// Promote it to its own validator file so admin tooling can import the same
// shape (and so test suites can spot drift between message-length cap on
// the API and the partial DB CHECK that landed in migration 070).
// ============================================

export const submitContactSchema = Joi.object({
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
      'Other',
    )
    .required()
    .messages({
      'any.only': 'Please select a valid subject',
      'any.required': 'Subject is required',
    }),
  // Ch08-ContactSubmission-D083: max 5000 characters mirrors the DB CHECK
  // landed in migration 070.
  message: Joi.string().trim().min(10).max(5000).required().messages({
    'string.empty': 'Message is required',
    'string.min': 'Message must be at least 10 characters',
    'string.max': 'Message must be 5000 characters or fewer',
    'any.required': 'Message is required',
  }),
  // Honeypot — humans never see the `website` input on the page (it's
  // visually hidden + aria-hidden + autocomplete=off). Naive bots fill
  // every field they find, so a non-empty value is a strong bot signal.
  // The route handler treats any value as an automatic reject.
  website: Joi.string().allow('').max(2048).optional(),
});
