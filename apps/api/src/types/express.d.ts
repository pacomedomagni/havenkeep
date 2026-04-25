// Module-scoped global augmentation. Importing this file from anywhere keeps
// the augmentation isolated to TS module resolution, which avoids the audit's
// "augmentation leaks into unrelated declaration scopes" hazard (Ch11-I084).
export {};

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
    }
  }
}

/**
 * Concrete user shape attached by the auth middleware. The `role` field is a
 * discriminated union so the type system rejects nonsensical combos like
 * isAdmin && isPartner && plan === 'suspended' (Ch11-I085 / I086 / I087).
 */
export type AuthenticatedRole = 'admin' | 'partner' | 'user';

export interface AuthenticatedUser {
  id: string;
  email: string;
  /**
   * 'free' | 'premium' for paid users; 'suspended' is set on suspended/deleted
   * users so handlers can gate logic on it (the audit caught services that
   * checked role booleans but ignored 'suspended' state — Ch11-I086).
   */
  plan: 'free' | 'premium' | 'suspended';
  role: AuthenticatedRole;
  /** Convenience flags derived from `role`. Kept in sync at construction time. */
  isAdmin: boolean;
  isPartner: boolean;
  emailVerified: boolean;
  /**
   * Native Date when present so handlers don't need to re-parse a string each
   * time (Ch11-I087: was typed string but the runtime value was a Date).
   */
  planExpiresAt?: Date | null;
}
