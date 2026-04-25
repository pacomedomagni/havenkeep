import Joi from 'joi';

// Anchored password regex (Ch01-F001): the prior pattern matched any prefix
// satisfying the character classes, so `Aa1!short` would pass the lookaheads
// even though it ends after "Aa1!s". Anchoring to ^...$ makes the rule mean
// what it reads.
//
// 8..72 chars: bcrypt only hashes the first 72 bytes (Ch01-F005); enforcing
// 72-char max in Joi keeps the API contract honest. Service code SHA-256
// pre-hashes longer inputs into the bcrypt boundary.
const PASSWORD_PATTERN = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]+$/;
const PASSWORD_MESSAGES = {
  'string.pattern.base':
    'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
  'string.min': 'Password must be at least 8 characters long',
  'string.max': 'Password must be at most 72 characters long',
};

const passwordSchema = Joi.string().min(8).max(72).pattern(PASSWORD_PATTERN).required().messages(PASSWORD_MESSAGES);

// Standard email schema: trimmed + lowercased before validation so the API
// can normalize the value once instead of every callsite (Ch01-F002).
const emailSchema = Joi.string().trim().lowercase().email().max(320).required();

export const forgotPasswordSchema = Joi.object({
  email: emailSchema,
});

export const resetPasswordSchema = Joi.object({
  token: Joi.string().min(32).max(256).required(),
  newPassword: passwordSchema,
})
  .rename('new_password', 'newPassword', { ignoreUndefined: true, override: false });

export const verifyEmailSchema = Joi.object({
  token: Joi.string().min(32).max(256).required(),
});

export const verifyEmailChangeSchema = Joi.object({
  token: Joi.string().min(32).max(256).required(),
});

export const changeEmailSchema = Joi.object({
  newEmail: emailSchema,
  password: Joi.string().required(),
})
  .rename('new_email', 'newEmail', { ignoreUndefined: true, override: false });

// Re-exported so route files can pull from one place.
export { emailSchema, passwordSchema, PASSWORD_PATTERN, PASSWORD_MESSAGES };
