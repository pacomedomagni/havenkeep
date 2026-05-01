import Stripe from 'stripe';
import { config } from '../config';

/// 2.5: shared Stripe client with sane network defaults.
///
/// `maxNetworkRetries: 2` lets the SDK transparently retry idempotent
/// reads + any mutating call we already pass an `idempotencyKey` to.
/// `timeout: 15_000` caps the request at 15s — the default 80s would
/// pin a DB transaction for 80s when Stripe is called inside `BEGIN`,
/// which is exactly the failure mode P-HI-05 flagged.
///
/// API version is pinned to the SDK's current default so locally
/// generated TypeScript types match what the dashboard sends. When the
/// SDK ships a new pin, bump both this string and `package.json` together
/// — drift between SDK types and account API version is the most common
/// "field exists in JSON but TS says it doesn't" failure mode.
///
/// SDK version note: pinned to v21 (NOT v22). v22 ships a CJS-typing
/// regression that breaks `Stripe.Charge` / `Stripe.PaymentIntent` /
/// `Stripe.Event` resolution under `tsconfig.module=commonjs`
/// (see https://github.com/stripe/stripe-node/discussions/2575 — Stripe
/// acknowledges "we are still fixing the issues with CJS imports").
/// v21 keeps the same `2026-03-25.dahlia` API pin and the same runtime
/// surface (constructor, methods, parseEventNotification, Decimal types)
/// without the namespace-import regression. Move to v22+ once Stripe
/// publishes a CJS fix or we migrate the API to ESM.
export function createStripeClient(): Stripe {
  return new Stripe(config.stripe.secretKey, {
    apiVersion: '2026-03-25.dahlia',
    maxNetworkRetries: 2,
    timeout: 15_000,
  });
}
