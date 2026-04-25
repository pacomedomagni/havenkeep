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
  // F114: Cloudflare Turnstile captcha token. Optional in the schema so
  // local dev (no key set) doesn't break, but the route enforces presence
  // when TURNSTILE_SECRET_KEY is configured.
  turnstileToken: Joi.string().max(2048).optional().allow(''),
})
  .rename('cf_turnstile_response', 'turnstileToken', { ignoreUndefined: true, override: false })
  .rename('cf-turnstile-response', 'turnstileToken', { ignoreUndefined: true, override: false });
