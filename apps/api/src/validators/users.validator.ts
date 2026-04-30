import Joi from 'joi';
import { passwordSchema } from './auth.validator';

/**
 * Change password.  Beyond the standard complexity rules (`passwordSchema`),
 * we enforce that:
 *   - the new password differs from the current one (Ch01-F072 wanted a
 *     minimal blocklist; the absolute minimum is "not the same as current");
 *   - the user supplied the current password (already enforced).
 * The "must not match account email" rule is enforced server-side because
 * Joi can't see the authenticated user's email.
 */
export const changePasswordSchema = Joi.object({
  // max(1024) (was 128) so a long passphrase can reach preHashForBcrypt
  // — see auth.validator.ts comment on passwordSchema (S1-C).
  currentPassword: Joi.string().min(1).max(1024).required(),
  newPassword: passwordSchema,
})
  .custom((value, helpers) => {
    if (value.newPassword === value.currentPassword) {
      return helpers.error('any.invalid', { message: 'New password must differ from current password' });
    }
    return value;
  })
  .rename('current_password', 'currentPassword', { ignoreUndefined: true, override: false })
  .rename('new_password', 'newPassword', { ignoreUndefined: true, override: false });

/**
 * Account deletion. `confirmDelete: true` is required (Ch01-F071: an empty
 * body used to pass). Password is required for email-auth accounts; OAuth
 * accounts use the explicit confirmDelete flag instead (handled in route).
 */
export const deleteAccountSchema = Joi.object({
  // max(1024) (was 128); see auth.validator.ts comment on passwordSchema (S1-C).
  password: Joi.string().min(1).max(1024).optional(),
  confirmDelete: Joi.boolean().valid(true).required(),
})
  .rename('confirm_delete', 'confirmDelete', { ignoreUndefined: true, override: false });

/**
 * Path-param validator for the linked-providers unlink endpoint
 * (DELETE /users/me/providers/:provider). The route handler enforces the
 * orphan-check; this just narrows the URL slug to the three sign-in paths
 * we actually expose so a typo bounces with a 400 instead of a 404.
 */
export const providerParamSchema = Joi.object({
  provider: Joi.string().valid('email', 'google', 'apple').required(),
});

/**
 * Verify-premium body schema (S-HI-01 / S-ME-01).
 *
 * The handler only consumes `revenueCatAppUserId` and only as a sanity
 * guard against passing someone else's UUID. Tightening the schema with
 * `.unknown(false)` rejects any future field a refactor accidentally
 * introduces without a validator update — defense in depth.
 */
export const verifyPremiumSchema = Joi.object({
  revenueCatAppUserId: Joi.string().uuid().optional(),
})
  .rename('revenue_cat_app_user_id', 'revenueCatAppUserId', { ignoreUndefined: true, override: false })
  .unknown(false);
