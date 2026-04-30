import Joi from 'joi';

// Anchored password regex (Ch01-F001): the prior pattern matched any prefix
// satisfying the character classes, so `Aa1!short` would pass the lookaheads
// even though it ends after "Aa1!s". Anchoring to ^...$ makes the rule mean
// what it reads.
//
// 8..1024 chars: bcrypt only hashes the first 72 bytes, which would silently
// truncate any longer password to its 72-byte prefix and weaken security
// (Ch01-F005 / S1-C). Service code defends with a SHA-256 pre-hash that
// collapses any input to a 64-byte digest before bcrypt sees it. The
// validator MUST allow longer inputs to reach that pre-hash — the prior
// max(72) cap was tighter than the security model and rejected long
// passphrases at the gate, defeating S1-C entirely.
const PASSWORD_PATTERN = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]+$/;
const PASSWORD_MESSAGES = {
  'string.pattern.base':
    'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
  'string.min': 'Password must be at least 8 characters long',
  'string.max': 'Password must be at most 1024 characters long',
};

const passwordSchema = Joi.string().min(8).max(1024).pattern(PASSWORD_PATTERN).required().messages(PASSWORD_MESSAGES);

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
