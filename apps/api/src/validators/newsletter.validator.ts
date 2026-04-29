import Joi from 'joi';

// ============================================
// Audit Ch08-NewsletterSubscriber-D078: hand-rolled email regex inside the
// route handler is not wired through the standard validate() middleware so
// it doesn't honor the global stripUnknown / messages contract. Wrap the
// existing logic in proper Joi schemas so the route looks like every other
// route and a Joi.options() change is enough to keep formatting consistent.
//
// Audit Ch08-NewsletterSubscriber-D080: source enum mirrors the DB CHECK
// added by migration 070.
// ============================================

const subscriberSourceValues = [
  'blog',
  'footer',
  'homepage',
  'pricing',
  'partner_dashboard',
  'admin_seed',
] as const;

export const subscribeNewsletterSchema = Joi.object({
  email: Joi.string().trim().email().lowercase().max(255).required().messages({
    'string.email': 'Please provide a valid email address',
    'string.max': 'Email must be 255 characters or fewer',
    'any.required': 'Email is required',
  }),
  source: Joi.string()
    .valid(...subscriberSourceValues)
    .default('blog'),
});

// S-ME-09: bare-email POST /unsubscribe was an unauthenticated bulk
// harassment vector — anyone who guessed/scraped a user's email could
// silently unsubscribe them. Require the same HMAC token the GET path
// requires (sent in unsubscribe-list email links). RFC 8058 one-click
// unsubscribe still works because the email's `List-Unsubscribe-Post`
// header carries the token.
export const unsubscribeNewsletterBodySchema = Joi.object({
  email: Joi.string().trim().email().lowercase().max(255).required().messages({
    'string.email': 'Please provide a valid email address',
    'any.required': 'Email is required',
  }),
  t: Joi.string().length(64).hex().required().messages({
    'any.required': 'Unsubscribe token is required',
  }),
});

export const confirmNewsletterQuerySchema = Joi.object({
  token: Joi.string().min(20).max(128).required(),
});

// One-click unsubscribe link from outbound emails (RFC 8058). The token is
// the full SHA-256 HMAC hex digest (64 chars) per Phase 4 hardening (F110).
export const unsubscribeNewsletterQuerySchema = Joi.object({
  email: Joi.string().trim().email().lowercase().max(255).required(),
  t: Joi.string().length(64).hex().required(),
});
