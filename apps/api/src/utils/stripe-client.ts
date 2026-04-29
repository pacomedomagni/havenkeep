import Stripe from 'stripe';
import { config } from '../config';

/// 2.5: shared Stripe client with sane network defaults.
///
/// `maxNetworkRetries: 2` lets the SDK transparently retry idempotent
/// reads + any mutating call we already pass an `idempotencyKey` to.
/// `timeout: 15_000` caps the request at 15s — the default 80s would
/// pin a DB transaction for 80s when Stripe is called inside `BEGIN`,
/// which is exactly the failure mode P-HI-05 flagged.
export function createStripeClient(): Stripe {
  return new Stripe(config.stripe.secretKey, {
    apiVersion: '2023-10-16',
    maxNetworkRetries: 2,
    timeout: 15_000,
  });
}
