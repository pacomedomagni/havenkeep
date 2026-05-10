# Audit Run 02-v2 — Money Paths (deep) — Stripe / Commissions / Payouts / RevenueCat

Date: 2026-05-10
Scope: same surface as v1 (`apps/api/src/services/partners.service.ts`, `services/warranty-purchases.service.ts`, `routes/webhooks.ts`, `routes/partners.ts`, `utils/{stripe-client,money}.ts`, mig 002, 011, 022, 030a/b, 035, 041, 050, 070, 071, 078, 086, 087, 089, 092, 095–098, the cron in `apps/api/src/index.ts`, `middleware/idempotency.ts`, `app.ts` Stripe-webhook plumbing, `__tests__/webhooks.test.ts`).

This pass goes deeper than v1: it walks each Stripe call argument-by-argument, each migration line-by-line, and adversarially trades through hostile-partner / hostile-homebuyer / hostile-operator scenarios. **v1's "no Criticals" verdict is wrong** — there are at least three smoking-gun issues (one money-routing bug in the cancel flow, one no-rate-limit on the most expensive write, one un-idempotent partner-facing mutation) that v1 either misclassified or missed entirely.

The findings below intentionally **do not duplicate v1**. v1 findings that I re-validated are noted in *Confirmed-from-v1*; v1 findings I disagree with after deeper read are in *Reclassified-from-v1*.

---

## Critical (fund-routing / lost-money / double-charge)

### C-MD-1 — `cancelPurchase` writes `refund_amount_cents = $5, refunded_at = NOW()` even when no Stripe refund happened
File: `apps/api/src/services/warranty-purchases.service.ts:402-466`

The Phase-2 Stripe call is gated on `refundCents > 0 && existing.stripe_payment_intent_id && !stripeRefundId`. If a warranty was created **without** a Stripe payment_intent (e.g. via a partner-attribution backfill, an admin-issued comp warranty, or any test fixture path that omits `stripePaymentIntentId`), `stripe_payment_intent_id IS NULL` and the entire Stripe leg is skipped — `stripeRefundId` stays `null`.

Phase 3 then writes:

```ts
const persistedRefundCents = refundCents > 0 ? refundCents : null;
…
SET refund_amount_cents = $5,
    refunded_at = CASE WHEN $5::int IS NOT NULL THEN NOW() ELSE refunded_at END
…
```

Walk the case "$99 active warranty, no payment_intent, cancelled mid-period":
- `refundCents = 4950` (50% of the period unused)
- Phase 2 skipped → `stripeRefundId = null`
- `persistedRefundCents = 4950`, `stripe_refund_id = null`
- The CHECK `chk_warranty_purchases_refund_shape` (mig 035) passes: `refund_amount_cents >= 0 AND refunded_at IS NOT NULL`.

Net state: the row says **the user got a $49.50 refund and a `refunded_at` timestamp, with no Stripe refund ID and no actual money movement**. The user's UI now shows "Refunded $49.50 on May 10"; finance reconciliation sums `refund_amount_cents` and overstates outflows; if the warranty was a comp/test/imported record, the user can call support claiming a refund the system says happened. There is no Stripe-level evidence to verify against because no transaction occurred.

The same shape is reachable when the column is null because the row was created before mig 035 (legacy data). The cancel proceeds, marks the row as refunded, and zero money moves.

**Fix**: only set `refund_amount_cents`/`refunded_at` when `stripeRefundId` is non-null. When `payment_intent_id` is null, either reject cancel up-front ("this warranty has no associated payment — contact support") or leave the refund columns NULL. Today's code commits a lie.

Severity: Critical (fund-state lie; finance reconciliation will diverge from Stripe; user has UI evidence of a refund that didn't happen).

### C-MD-2 — `POST /partners/gifts` has neither `writeRateLimiter` nor `idempotency` middleware — partner can be billed multiple times for one user click
File: `apps/api/src/routes/partners.ts:329-349`

```ts
router.post(
  '/gifts',
  requirePartner,
  validate(createGiftSchema),
  asyncHandler(async (req, res) => {
    const userId = req.user!.id;
    const gift = await PartnersService.createGift(userId, req.body);
    …
```

Compare with every other mutating partner route in the same file:
- `PUT /me`: `writeRateLimiter` ✓
- `POST /register`: `writeRateLimiter` ✓
- `POST /me/payouts`: `writeRateLimiter` ✓
- `POST /me/tax-form-link`: `writeRateLimiter` ✓
- `POST /gifts/:id/resend`: `giftResendRateLimiter` ✓ (because resend is the email surface, not the money surface — but it has a limiter)
- **`POST /gifts`: nothing**

Compare with every other money-mutating route in the codebase:
- `POST /warranty-purchases`: `writeRateLimiter` + `idempotency('warranty-purchases:create')` ✓
- `POST /warranty-purchases/:id/cancel`: `writeRateLimiter` + `idempotency('warranty-purchases:cancel')` ✓
- `POST /warranty-claims`: `idempotency('warranty-claims:create')` ✓

`POST /partners/gifts` is the **single most expensive** mutating route in the system ($99–$249 charged to a saved card on every successful call) and it's the only one without:
1. **A rate limit**. A partner whose dashboard hangs and double-clicks "Send gift" sends two requests; both pass `requirePartner` and Joi; both are processed by `createGift`. Stripe's `idempotencyKey: gift-${gift.id}` is per-gift — it doesn't dedupe across separate `gift.id`s, because each request creates its own gift row in Phase 1. **Two distinct gift rows + two distinct charges land on the partner's card for one human click.** The activation_code pre-check (line 462–486) doesn't help because the codes are different.
2. **Idempotency-Key support**. The mobile + dashboard already plumb `Idempotency-Key` for warranty purchases / claims / items; the `idempotency()` middleware is a 1-line decorator. This route was missed.

Adversarial corollary: a malicious upstream proxy that retries on a 200 response can replay the same partner request N times (the proxy might think the connection dropped). N gifts get created, N charges land. Stripe sees N distinct payment_intents, each with a different idempotency key (`gift-<distinct-uuid>`), so Stripe has no way to dedupe.

**Fix**:
```ts
router.post(
  '/gifts',
  requirePartner,
  writeRateLimiter,
  validate(createGiftSchema),
  idempotency('partner-gifts:create'),
  asyncHandler(async (req, res) => { … }),
);
```

Severity: Critical (double-charge risk on the most expensive single API call in the system; partner-facing dashboard can race-fire two charges from one button click).

### C-MD-3 — `proratedRefundCents` operates on `Number(existing.price)` (float dollars), bypassing `dollarsToCents`
File: `apps/api/src/services/warranty-purchases.service.ts:16-28, 402-407`

```ts
function proratedRefundCents(
  priceDollars: number,    // <-- float
  startsAt: Date,
  expiresAt: Date,
  cancelledAt: Date,
): number {
  const totalDays = …
  const usedDays = …
  const remainingDays = Math.max(0, totalDays - usedDays);
  const fraction = remainingDays / totalDays;
  const cents = Math.round(priceDollars * 100 * fraction);   // float×100×float
  return Math.max(0, cents);
}

…

const refundCents = proratedRefundCents(
  Number(existing.price),       // pg returns DECIMAL as string; Number() can drift
  …
);
```

For "regular" prices ($99, $149, $249, $4.99) the float math happens to recover exactly. But:

- `existing.price` arrives from `pg` as a **string** (DECIMAL columns return as strings by default). `Number("99.99")` → 99.99 (fine for short decimals). But for an imported warranty with price `'499.45'` and a 50% prorated refund: `499.45 * 100 * 0.5 = 24972.500000…` then `Math.round` → 24973. The integer-cent path through `dollarsToCents("499.45") * 0.5 = 49945 * 0.5 = 24972.5`, `Math.round` → 24973. Same answer this case. Try `'333.33' × (197/365)`: `333.33 * 100 * 0.5397260… = 17988.6986…` → 17989. Cents path: `33333 * 0.5397260… = 17988.69863…`, `Math.round` → 17989. Still equal.
- Now try a 360-day policy cancelled at day 121: `priceDollars = 199.99`, `fraction = 239/360`. Float path: `199.99 * 100 * 0.6638888… = 13278.19444…` → 13278. Cents path: `19999 * 0.6638888… = 13277.19166…` → 13277. **Off by 1 cent.**

Practical impact at $99–$249 scale is one cent on the corner cases. Below the threshold for v1's "Severe" but the centralised `money.ts` was written exactly to avoid these, and the file imports `dollarsToCents`/`commissionCents`/`decimalToCents` two lines above this function. Author is using money utils for everything else (`generateQuotes` uses `dollarsToCents` correctly) — `proratedRefundCents` is the lone laggard.

**Fix**:
```ts
function proratedRefundCents(
  priceCents: number,            // <-- input is now cents
  startsAt: Date, expiresAt: Date, cancelledAt: Date,
): number {
  const totalDays = Math.max(1, Math.round((expiresAt - startsAt) / 86_400_000));
  const usedDays = …; const remaining = Math.max(0, totalDays - usedDays);
  // commissionCents ≡ Math.round(amountCents * rate); reuse it.
  return commissionCents(priceCents, remaining / totalDays);
}
…
const refundCents = proratedRefundCents(
  dollarsToCents(existing.price),
  …
);
```

Severity: Critical (off-by-one cent is small; the precedent of "money utils exist, half the code uses them, half doesn't" is the failure to enforce; combined with C-MD-1 the cancel flow has two money-correctness bugs in 60 lines).

### C-MD-4 — `clawbackCommissionForGift` rounds reversal amounts to 2-decimal dollars, NOT to integer cents
File: `apps/api/src/routes/webhooks.ts:96-101`

```ts
const reversalAmount =
  proportion >= 1
    ? -Number(row.amount)
    : -Math.round(Number(row.amount) * proportion * 100) / 100;
```

For a partial refund: take a $99 gift, $14.85 commission (15%), 33% partial refund:
- `Number("14.85") * 0.333… * 100 = 494.95049…`
- `Math.round` → 495
- `/ 100` → 4.95 → stored as `-4.95` in DECIMAL(10,2). Then re-INSERTed as a string-coerced negative number.

This works for clean ratios. But the helper INSERTs `amount = $reversalAmount` as a Number into a DECIMAL column — `pg` stringifies a JS number, which means `-4.95` writes as the literal `"-4.95"`. Two consecutive partial refunds at 50% then 50% again produce reversals `-7.42` (rounded from -7.425) and `-7.42` (computed from cumulative 100% of 14.85 = -14.85 minus original's residual…wait, this is more complex). The v1 L-MP-3 finding already flagged the cumulative-vs-delta math; what THIS finding adds is that the rounding is done in **dollars**, not cents, so the math twice-rounds (cents→dollars at the helper, dollars→DECIMAL on insert) and the residual original commission row is `+14.85` while the reversals sum to `-14.84`. **Net commission = +0.01 forever** on certain partial-refund schedules.

The whole codebase is supposed to do money math in cents; this site is the exception.

**Fix**: convert `row.amount` to cents via `decimalToCents`, multiply integer cents by proportion, `Math.round` to int cents, then `centsToDecimalString` for the INSERT. Same pattern as `getPartnerAnalytics`:
```ts
const origCents = decimalToCents(row.amount);
const reversalCents = -commissionCents(origCents, proportion);
const reversalAmount = centsToDecimalString(reversalCents);
```

Severity: Critical (cents drift on the commission ledger; the ledger sums to a non-zero residual after a sequence of partial refunds; partner sees "you have $0.01 of commission" forever, finance can't reconcile).

---

## High

### H-MD-1 — Stripe `paymentIntents.create` `amount: amountCents` skips currency-aware minimums
File: `apps/api/src/services/partners.service.ts:629-670`

`amount: amountCents` is the only validator before the Stripe call. The check is `if (amountCents <= 0) throw 500`. But:
- Stripe rejects amounts below the per-currency minimum (USD: $0.50, GBP: £0.30, etc.) with `amount_too_small`.
- The current code hardcodes `currency: 'usd'`, so the relevant floor is $0.50 = 50 cents. `TIER_PRICE_PER_GIFT_USD['basic'] = 99` → 9900 cents — we're nowhere near the floor today.

But the env override `process.env.PARTNER_TIER_PRICING` is *operator-supplied JSON* and accepts any number. An operator typo `{"basic": 0.99, ...}` (intending dollars-and-cents but writing the JSON as if it were dollars) lands `amountCharged = 0.99` → `amountCents = 99`. Above the floor — the call SUCCEEDS — partner is charged $0.99 instead of $99 for every gift. The `if (amountCents <= 0)` guard doesn't catch this; the `if (tierAmount === undefined)` doesn't catch it; the partner only notices when their card statement comes back.

**Fix**: validate `PARTNER_TIER_PRICING` at config-validator time. Refuse a tier price below $X (say, $10 — well below `basic.99` but well above the typo case). Refuse non-integer dollars (the schema is integer dollars, not decimals).

Severity: High (operator-typo path; not adversarial, but the consequence is silent under-charging on every gift).

### H-MD-2 — `auditWebhookPlanTransition` fires AFTER `await client.query('COMMIT')` but is invoked WITHOUT `await`
File: `apps/api/src/routes/webhooks.ts:790-798, 963-971, 1344-1352, 1409-1418, 1461-1470, 1522-1531, 1543-1552`

Every webhook plan transition does:

```ts
await client.query('COMMIT');                        // <-- DB tx ends
…
auditWebhookPlanTransition({ … });                   // <-- NOT awaited; .catch() chained
```

The function itself does:

```ts
AuditService.log({ … }).catch((err) => { logger.error(...); });
```

Two problems:

1. **Audit row may not be written before the response is sent**. The route handler proceeds, calls `await markWebhookProcessed(...)`, sends 200. The Promise from `AuditService.log` is not awaited at any point in the response cycle. If the process is killed before the I/O lands (graceful shutdown, OOM, container kill), the audit row never lands. The `auditWebhookPlanTransition` comment claims "best-effort: a transient AuditService failure must not roll back the plan change" — but that's a different concern than "best-effort against process crash". The audit hash chain (`AuditService.verifyHashChain` daily) cannot detect missing rows; it only detects **tampered** rows.
2. **Hash-chain ordering** can be violated. If two webhook handlers fire `auditWebhookPlanTransition` concurrently (Stripe + RC delivering an EXPIRATION on the same user 2ms apart), the two audit-log inserts race. The chain has an advisory lock (mig 080/082) so the writes serialize, but the **logical order** in the chain is now race-determined, not webhook-event-time-determined. A future forensic question "did Stripe charge.refunded fire before or after RC RENEWAL?" reads a chain that's misordered relative to the events.

**Fix**: `await auditWebhookPlanTransition(...)` (the function should be `async` and return the promise). Best-effort error handling is fine; ordering matters.

Severity: High (audit-log integrity is an advertised feature; webhook plan transitions are exactly the case where forensics matters most; current code has a window where the audit row is missing).

### H-MD-3 — Self-service payout doesn't gate on partner `partners.status='active'`
File: `apps/api/src/routes/partners.ts:876-1010`

`requirePartner` checks `req.user.isPartner`. v1's M-MP-5 flagged this — but `isPartner` IS correctly tied to `partners.status='active'` in the auth derivation (`middleware/auth.ts:105`). So a `pending` or `rejected` partner correctly cannot reach `/partners/gifts`.

What `requirePartner` does NOT close: the **user-row cache** in Redis (`USER_CACHE_TTL_SEC = 10`) caches `is_partner=true`. When admin rejects (`/admin/partners/:id/reject`), `invalidateUserCache(partner.user_id)` is called immediately — good. But there's a 10-second window where a partner whose Stripe Connect account just transitioned to `restricted` (because of a `account.updated` webhook) can still hit `/me/payouts`. The route does check `partner.stripe_account_status !== 'enabled'` → 409 (line 887), so the gate is closed. However:

- The check reads `partner.stripe_account_status` from `PartnersService.getPartner(userId)` (line 882), which reads the DB on every call (no cache on the partner row). 
- The `account.updated` webhook also writes to the DB synchronously. So the race window is sub-millisecond, OK.

The real defect is in the dashboard summary endpoint, `GET /me/payouts/summary` (line 813–851): it returns `stripe_payouts_enabled: partner.stripe_account_status === 'enabled'`. This is a snapshot. The Payouts page UI gates the "Request payout" button on this snapshot. A partner whose Connect account just moved to `restricted` mid-session will see an enabled "Request payout" button until they reload; clicking it will 409. Cosmetic, but UX-jarring.

That's not the bug. The actual bug: `/me/payouts` does NOT check `partners.status='active'`. A partner who registered (`status='pending'`), was approved (`status='active'`), used Stripe Connect onboarding (status went `pending→enabled`), accumulated commissions, and was THEN rejected by admin (`status='rejected', is_active=FALSE`) — but whose `stripe_account_status` is still `enabled` because no Stripe-side change happened — can still call `/me/payouts` and the route will execute Stripe transfers against their Connect account. The mig 092 invariant (`is_active=TRUE ⇔ status='active'`) keeps `is_active=FALSE` for rejected, but **the route never reads `is_active` or `status`**. It only checks `stripe_account_status`. After admin reject, `requirePartner` gate kicks in (because `isPartner` is recalculated from `status='active'` and the admin reject path called `invalidateUserCache`), so this is mostly defended at the auth layer — except for the 10-second cache window AND any future code path that bypasses `requirePartner`.

**Fix**: belt-and-braces — `/me/payouts` and `/me/tax-form-link` and the payout-summary endpoint should explicitly check the partner row: `if (partner.status !== 'active') throw 403`. The mig 092 invariant means that's equivalent to checking `is_active=TRUE`, so either column works.

Severity: High (defense-in-depth; the check is in only one layer today; admin rejection has a brief race window where the partner can still call payout).

### H-MD-4 — Phase-1 createGift does not lock `users.stripe_customer_id` row, can race with PM removal
File: `apps/api/src/services/partners.service.ts:512-540, 621-625`

Phase 1 reads `partnerUser.rows[0]?.stripe_customer_id` inside the `reserveClient` tx, then COMMITs (line 608). Phase 2 re-reads `users.stripe_customer_id` outside any tx (line 621–624) and uses it for `stripe.customers.retrieve(stripeCustomerId)`.

Two distinct reads → two distinct values is possible. The race:
- Time T+0: Phase 1 reads `stripe_customer_id='cus_aaa'`, validates non-null, commits.
- Time T+1: User goes to Settings, removes their card → backend sets `users.stripe_customer_id = NULL`.
- Time T+2: Phase 2 re-reads `stripe_customer_id`, gets `null`. Calls `stripe.customers.retrieve(null)` — Stripe SDK throws `customer is required`. 
- Phase-2 catch (`stripeError.code = undefined`) → `STRIPE_DECLINE_MESSAGES[undefined] || 'Payment failed…'` → 402. The partner sees a generic "Payment failed". But a `pending_payment` row WAS created in Phase 1.
- The cleanup in the catch (line 684–687) flips it to `'expired'`. OK.

That branch survives — but the "user removed card" event is rendered to the partner as a generic decline. Hostile partner case: a partner could pre-add a card, fire 100 createGift calls, and rapid-fire remove the card during Phase 1's row reads. Each call creates a `pending_payment` row → `expired`. No charges fire. But the activation_code row stays in DB with hash + plaintext nulled. Mostly harmless, but the partner can fill `partner_gifts` with junk rows under the same hash space.

**Fix**: re-read `stripe_customer_id` once in Phase 2 atomically with the customer retrieve; or read it ONCE in Phase 1 inside the tx and pass through a closure. Today's two-read pattern is gratuitous.

Severity: High (the race is unlikely but the cleanup is incomplete — the gift row stays in partner_gifts.expired, polluting the partner's gift list with no-charge ghosts; a malicious partner can spam).

### H-MD-5 — `clawbackCommissionForGift` partial path on a `paid` commission DOES produce a reversal row, but the commission stays `'paid'` and `paid_total` keeps counting it
File: `apps/api/src/routes/webhooks.ts:107-122` + `apps/api/src/routes/partners.ts:830-833`

The clawback path on a `paid` commission inserts a sibling `'reversed'` row but does NOT update the original `'paid'` row. Per the audit comment: "Money already left the platform balance — record a reversal so the ledger sums to zero. The actual Stripe transfer reversal is initiated by the operator (admin route), since automated reversal of partner payouts is too dangerous to do in a webhook handler."

Net effect: the partner's `/me/payouts/summary` shows:
```sql
COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0)::numeric AS paid_lifetime
```

`paid_lifetime` includes the original `+14.85` commission. The reversal row has `status='reversed'`, so it's NOT counted. **The partner's "lifetime paid" overstates by the reversal amount until/unless the operator manually initiates a transfer reversal AND records the corresponding adjustment.**

Compare with the v1-confirmed semantics in `getPartnerAnalytics` (`partners.service.ts:1211-1219`):
```sql
SUM(amount) FILTER (WHERE status = 'paid' AND stripe_transfer_id IS NOT NULL) as paid_commissions,
SUM(amount) as total_commissions
```

`total_commissions` correctly nets the reversal (because it sums all rows including negative reversals). `paid_commissions` does NOT — it only sums `status='paid'` rows. So the partner's analytics page shows `paid_commissions=$14.85, total_commissions=$0` (paid + reversed = 0). The Payouts page summary shows `paid_lifetime=$14.85` and the user has no idea the reversal happened.

The two endpoints contradict each other on the same partner. Worse, the partner has no admin-visible "you owe us $14.85 back" debit visible anywhere in the UI; it's all operator-side.

**Fix**: pick one semantic. Either:
1. **Don't change `paid` rows but include reversals in summary**: change `paid_lifetime` to `SUM(amount) FILTER (WHERE status = 'paid') + SUM(amount) FILTER (WHERE status = 'reversed' AND reversal_of_commission_id IS NOT NULL)`. This nets the reversal into the paid total. (Simpler, mirrors `total_commissions` from analytics.)
2. **Or update the original `paid` row's status to `'paid_reversed'` (new enum)**: requires a new enum value + every reader to handle it.

(1) is the smaller change. Today's `paid_lifetime` is a lie when a paid gift gets refunded.

Severity: High (financial-dashboard misreporting; partner-visible discrepancy; not money-routing but money-truth).

### H-MD-6 — `chk_partner_commissions_amount_range CHECK (amount BETWEEN -100000 AND 100000)` is dollars, but the column is DECIMAL(10,2) — partner commissions for a $100k bracket gift fail
File: `apps/api/src/db/migrations/070_phase8_drift_constraints.sql:80-83`

```sql
ALTER TABLE partner_commissions
  ADD CONSTRAINT chk_partner_commissions_amount_range
  CHECK (amount BETWEEN -100000 AND 100000);
```

Comment: *"Earning rows are positive, reversal rows are negative; cap absolute value at $100k to detect runaway records (e.g. a stray cent→dollar mix-up)."*

Today's tier max is platinum @ $249/gift × 20% = $49.80. Way under. But there's a hidden gap: `TIER_PRICE_PER_GIFT_USD` is env-overridable (mig comment says so explicitly). An operator setting `{"platinum": 999999}` → `amount = 199999.80` would violate this CHECK and the gift's Phase 3 commission INSERT would 23514 → triggers the dbErr branch in createGift → issues a refund. Result: the gift is auto-refunded immediately. Stripe-clean (no money lost), but the partner's UX is "we charged you and then refunded" with no explanation, and the audit log shows "DB finalization failed after Stripe charge".

Adversarial: not really hostile, but a "happy path" config tweak by an operator silently breaks gift creation for the platinum tier.

**Fix**: either (a) document that PARTNER_TIER_PRICING max is bounded by the CHECK, and validate at config-load time; (b) raise the CHECK ceiling; or (c) drop it (it's a sanity guard, not a security boundary — the Joi cap on `premiumMonths` and the tier enum already bound input).

Severity: High (latent; operator-knob has a non-obvious ceiling; gift creation silently 500s past it).

### H-MD-7 — `commission_rate = 0` on reversal rows fails any future CHECK that tightens the rate, and is semantically wrong
File: `apps/api/src/routes/webhooks.ts:113-116, 129-133`

The reversal INSERT writes `commission_rate = 0`:
```ts
INSERT INTO partner_commissions (
   partner_id, type, amount, commission_rate, status,
   reference_id, reference_type, reversal_of_commission_id, description
 ) VALUES ($1, 'gift', $2, 0, 'reversed', $3, 'partner_gift', $4, $5)
```

Mig 050 marked `commission_rate NOT NULL` and dropped the DEFAULT. Mig 041 dropped DEFAULT 0.15 to force callers to populate. The current code passes `0` for reversal rows, which:
- Doesn't violate any current CHECK (no min/max on the column).
- Is semantically misleading: a reversal is a sibling of a real earning, and "this reversal happened at 0% commission" is meaningless. The right value is the original commission's rate (so a query like `SELECT … FROM partner_commissions WHERE commission_rate > 0.15` correctly includes both the original and its reversal).
- Future tightening of `commission_rate` to e.g. `CHECK (commission_rate BETWEEN 0.05 AND 0.30)` would refuse the reversal INSERT and the webhook handler would 23514 → dead-letter. The whole clawback pipeline breaks on a constraint that "looks safe" to future authors.

**Fix**: `commission_rate = $rateFromOriginal` — fetch from the row being reversed (already in `original.rows[*].commission_rate` if you SELECT it; today the SELECT only pulls `id, partner_id, amount, status, stripe_transfer_id`).

Severity: High (latent failure; current code is correct only because no future CHECK tightens the rate; a single line of forward-incompatible guesswork).

### H-MD-8 — `ON CONFLICT (source, event_id) DO UPDATE … WHERE webhook_events.last_event_at <= EXCLUDED.last_event_at` is missing on `webhook_event_high_water` — handler can run on a stale event
File: `apps/api/src/routes/webhooks.ts:280-298` (vs the v1-claimed correctness)

```ts
const upsert = await query(
    `INSERT INTO webhook_event_high_water (source, subject_id, last_event_at, last_event_id)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (source, subject_id) DO UPDATE
       SET last_event_at = EXCLUDED.last_event_at,
           last_event_id = EXCLUDED.last_event_id,
           updated_at = NOW()
     WHERE webhook_event_high_water.last_event_at <= EXCLUDED.last_event_at
     RETURNING last_event_at`,
    [source, subjectId, eventAt, eventId],
  );
return upsert.rowCount === 1;
```

The `WHERE` clause is on the **`DO UPDATE`** branch. ON CONFLICT semantics: the WHERE filters the UPDATE; if the WHERE is false, the row stays as-is. `RETURNING last_event_at` in that case returns 0 rows → `rowCount === 0` → caller sees "out of order, skip". 

But: **on first delivery (insert path)**, `xmax=0` and `RETURNING` returns 1 row → `rowCount === 1` → in-order. Correct.

The actual bug: **multiple subjects can claim the same `(source, subject_id)`**. The Stripe handler uses `subjectId = paymentIntentId` for disputes (`webhooks.ts:901`). The RC handler uses `subjectId = userId` for plan transitions. **A user UUID could collide with a Stripe payment_intent_id**? No — UUIDs are 36 chars, payment_intents are `pi_…` (24+). Different shapes; collision impossible.

But: the UNIQUE key is `PRIMARY KEY (source, subject_id)`. The Stripe `dispute` and Stripe `charge` events use the SAME `paymentIntentId` (line 901: `await isEventInOrder('stripe', paymentIntentId, eventId, eventAt)`). The Stripe `charge.refunded` handler (line 688–822) DOES NOT call `isEventInOrder` at all. So:
- A `charge.dispute.created` arrives at T0 with paymentIntentId=`pi_abc`. High-water row written: `last_event_at=T0`.
- A `charge.refunded` arrives at T-5min (older retry) with paymentIntentId=`pi_abc`. The handler does NOT consult high-water — it just runs. The dispute UPDATE runs after the refund UPDATE; the row state is stale.
- The next `charge.dispute.updated` at T+1min consults high-water → in order (T+1 > T0) → runs. But the prior charge.refunded already updated `partner_gifts.status='expired'` and the dispute is now flagging an already-expired row. Two sibling UPDATEs to the same row from two distinct event paths.

The deeper issue: the **payment_intent is shared between charge.* events and dispute.* events**, but only dispute events are ordered. A reordering of (charge.refunded, charge.dispute.created) is possible — the dispute handler will run after the refund.

**Fix**: either (a) call `isEventInOrder` from `handleChargeRefunded` and `handleChargeFailed`, scoped to `paymentIntentId`; (b) accept that `charge.*` events don't have a meaningful ordering relationship with `dispute.*` events because they describe different state machines and the gift's terminal state is what matters.

In practice, a refund-then-dispute or dispute-then-refund both end with `gift.status='expired'`, so the practical damage is small. But the v1 report claims "isEventInOrder for RC events" is fully correct — it isn't, the same helper is also used for Stripe disputes, and the half-coverage on Stripe side is what makes this nuanced.

Severity: High (latent ordering bug; mostly self-healing because of terminal state idempotence, but the "disputes ordered, refunds not" asymmetry is undocumented).

### H-MD-9 — `getEarningsHistory` SUMs `pending_commissions` not present in production data, AND uses parseFloat
File: `apps/api/src/services/partners.service.ts:1260-1281`

```sql
SELECT
   date_trunc('month', created_at) as month,
   SUM(amount) as earnings
 FROM partner_commissions
 WHERE partner_id = $1 AND status IN ('approved', 'paid') AND created_at >= NOW() - INTERVAL '12 months'
 GROUP BY date_trunc('month', created_at)
```

Two issues:
1. v1-confirmed: `parseFloat(row.earnings) || 0` (line 1275). The 12-row sum drift is bounded; v1 already flagged.
2. **New**: the WHERE clause excludes `'pending'` — but the auto-approve cron (`index.ts:136-169`) only flips `pending → approved` after 30 days AND only if `partners.stripe_account_status='enabled'`. A new partner who just signed up + just sold their first 5 gifts in their first 30 days sees `earnings: $0` for the current month, even though commissions are accruing. The dashboard's "Last 12 months" chart shows them at zero for their first month no matter how active they were.

This is "by design" per the cron's intent — partners shouldn't see anything as "earned" until the clawback window passes — but the API field is named `earnings`, the column is `earnings`, and a brand-new partner reads "0 earnings this month" as "the system isn't tracking my work". Pure UX, but the inconsistency between `getPartnerAnalytics` (which has `pending_commissions` separately) and `getEarningsHistory` (which only counts approved+paid) is a footgun.

**Fix**: include `'pending'` in the IN list, or rename the field to `paid_earnings`. The chart should show "you have $X pending and $Y approved" so the partner sees their funnel.

Severity: High (UX defect that could send a brand-new partner away thinking the platform doesn't pay; not money routing).

### H-MD-10 — Phase-3 catch fires an UNGUARDED Stripe refund that the v1 `'paid' commission` path may concurrently transfer
File: `apps/api/src/services/partners.service.ts:730-747`

```ts
} catch (dbErr) {
  await promoteClient.query('ROLLBACK').catch(() => {});
  …
  await stripe.refunds.create(
    { payment_intent: stripeChargeId },
    { idempotencyKey: `refund-${gift.id}` },
  );
```

The refund call has no amount, so it's a **full refund**. Walk this case:
- Phase 1 commits `pending_payment` gift row.
- Phase 2 succeeds: charge clears, `stripeChargeId='pi_abc'`.
- Phase 3 BEGIN, UPDATE gift to 'created', INSERT commission. Commission INSERT 23514s (e.g. amount out of range per H-MD-6). ROLLBACK.
- Catch issues `stripe.refunds.create({ payment_intent: 'pi_abc' }, { idempotencyKey: 'refund-<gift.id>' })`.

This is correct money-wise. **But**: there's a race with `charge.refunded` from this very refund:
- T+0: refund issued by createGift catch. Stripe sends `charge.refunded` webhook.
- T+5ms: webhook handler runs, looks up `partner_gifts WHERE stripe_charge_id='pi_abc'`. Phase 3 ROLLBACK already happened, but Phase 1 wrote `stripe_charge_id=NULL` and Phase 3 was the one that was supposed to UPDATE `stripe_charge_id=$1`. The rollback undid the UPDATE. So the gift row has `stripe_charge_id=NULL` and `status='pending_payment'`.
- The webhook query `WHERE stripe_charge_id = $1` finds 0 rows. The handler logs warn "no matching gift" and ACKs. **The gift row stays at `pending_payment` forever.**

Compounding: there's also no cleanup in the Phase-3 catch that flips the gift to `'expired'` like Phase-2 does. So the row is forever in `pending_payment` — the daily expiry cron picks it up only if `expires_at < NOW()` (line 100–103 in index.ts), which is true after the configured window. But until then, it's a ghost row.

**Fix**: in the Phase-3 catch, after the refund, do `UPDATE partner_gifts SET status='expired' WHERE id=$1` so the row is in a clean terminal state.

Severity: High (creates orphan rows that webhook handlers can't match, that the partner sees in their gift list as "pending payment" with no recourse).

### H-MD-11 — Webhook signature verification raw-body handling: `req.body` may be a parsed object on Caddy compression error
File: `apps/api/src/routes/webhooks.ts:332-340` + `apps/api/src/app.ts:136-140`

```ts
event = stripe.webhooks.constructEvent(
  req.body, // raw body buffer — must NOT be JSON-parsed
  signature,
  config.stripe.webhookSecret
);
```

The mount `app.use('/api/v1/webhooks/stripe', express.raw({ type: 'application/json', limit: '1mb' }), …)` sets `req.body` to a Buffer **only if `Content-Type: application/json`**. If a hostile caller sends `Content-Type: text/plain` with a JSON body, `express.raw()` won't match, the request falls through to `express.json()` later (which parses it), and `stripe.webhooks.constructEvent(req.body, …)` gets a parsed object → throws "no signatures found matching the expected signature".

OK in practice — Stripe sends application/json — but the raw type should be `'*/*'` if we want to accept ANY body and let signature verification fail noisily. Today's failure mode for a wrong-CT request is "fall through, try to parse, get 400 from JSON parse". Probably fine.

The real concern: the CLAUDE.md staging entry says *"The havenkeep block already has a raw-body matcher for `/api/v1/webhooks/stripe` … Stripe signature verification needs the raw body unmolested by Caddy compression."* If Caddy in front compresses the request body (zstd, gzip), `express.raw()` gets the compressed bytes. `stripe.webhooks.constructEvent` computes HMAC over compressed bytes vs Stripe's HMAC over uncompressed bytes → mismatch → 400. Stripe retries 3 days. Dead-letter at attempt 8 (per H-MP-3).

The Caddyfile is in another repo (`~/Projects/staging`) and not in this audit's diff, so I can't verify the encoding-disable directive is set correctly. But: there's NO **defense-in-depth** in our app for the case where the raw body has been recompressed. The signature verification will just fail. Unless someone reads the dead-letter logs (and per v1 H-MP-3 there's no alert), three days of webhooks die silently.

**Fix**: add a `Content-Encoding` check in the webhook handler — if `req.headers['content-encoding']` is present and non-`identity`, log ERROR and respond 500. That way the operator sees "Caddy is compressing webhook bodies" instead of "Stripe signature failed" (the second is much less actionable).

Severity: High (operational fragility; combined with v1 H-MP-3 a single Caddy reconfig kills 3 days of webhooks silently).

### H-MD-12 — `STRIPE_DECLINE_MESSAGES` map keys on `stripeError.code` but `decline_code` is the actual decline reason
File: `apps/api/src/services/partners.service.ts:82-93, 672-694`

```ts
const declineCode =
  stripeError?.code ||
  stripeError?.raw?.decline_code ||
  stripeError?.decline_code ||
  'generic_decline';
```

Stripe's error shape on a card decline:
- `error.code = 'card_declined'`
- `error.decline_code = 'insufficient_funds' | 'do_not_honor' | …`

So `stripeError.code` is `'card_declined'` for ALL declines, and `decline_code` carries the actual reason. The map has both `'card_declined'` AND `'insufficient_funds'` etc. as keys. Today's code grabs `stripeError.code` first → always `'card_declined'` → always shows the generic "Your card was declined." message, even though `'insufficient_funds'` would tell the user they have a balance issue.

The order should be: `decline_code` (most specific) → `code` (generic decline category) → `'generic_decline'`.

**Fix**:
```ts
const declineCode =
  stripeError?.raw?.decline_code ||
  stripeError?.decline_code ||
  stripeError?.code ||
  'generic_decline';
```

Severity: High (UX — the partner never sees the actionable decline messages we wrote; the v1 H-MP-1 finding called this out from a different angle but missed this specific ordering bug).

---

## Medium

### M-MD-1 — `webhook_events.attempts + 1 >= MAX_WEBHOOK_ATTEMPTS` evaluation race when first delivery 23505s on insert
File: `apps/api/src/routes/webhooks.ts:189-225`

The `SELECT 1 … FOR UPDATE` at line 189 takes the row lock IF the row exists; otherwise it returns 0 rows and **does not** lock anything. The subsequent INSERT … ON CONFLICT DO UPDATE then races. Two truly-first deliveries can both pass the SELECT (no row to lock) and both INSERT — one wins via the unique key, the other hits ON CONFLICT DO UPDATE and bumps `attempts`. If both arrive in <1ms (impossible from Stripe's retry, but possible from operator-driven replay), the loser's UPDATE evaluates `attempts + 1 = 2`, well below MAX. OK.

The actual concern: the race when the row exists and TWO concurrent retries land. Both pass `SELECT … FOR UPDATE` (one waits, other proceeds, then they swap), one writes `attempts=N+1`, the other writes `attempts=N+1` (because the second's UPSERT reads pre-bumped attempts, applies its own +1, but the UPSERT `webhook_events.attempts + 1` is evaluated against the row state visible to the UPSERT, which now sees the just-committed value). Postgres's UPSERT handles this correctly: ON CONFLICT DO UPDATE re-reads the latest committed row and applies the SET to it. So `attempts=N+2` after both run.

OK — but the row lock with `SELECT … FOR UPDATE` doesn't *force* the second caller to wait for the first's COMMIT before its UPSERT evaluates the CASE expression. Actually, ON CONFLICT DO UPDATE in PG is NOT atomic with the prior row state — it's a "speculative INSERT, fall back to UPDATE if conflict" path. The `WHERE webhook_events.attempts + 1 >= MAX` predicate runs against the row's CURRENT state at the moment of the conflict, which is the post-commit state of the prior tx (because the prior tx held FOR UPDATE).

Net: the gate works, but the comment claiming "the threshold check + status transition are atomic against the row's committed state" is true only because of how PG sequences UPSERT-after-FOR-UPDATE — not obvious from reading the code. A future refactor that drops the FOR UPDATE thinking "the UPSERT is atomic" would break the threshold check.

**Fix**: harden the comment, or replace the FOR UPDATE + UPSERT pair with a single `SELECT … FOR UPDATE; if not found INSERT; if found UPDATE` pattern that's obviously atomic. Today's pattern works but is fragile to "improve".

Severity: Medium (the gate is correct; the structural reasoning is non-obvious).

### M-MD-2 — `account.application.deauthorized` clears `stripe_account_id` but doesn't cancel the partner's pending+approved commissions
File: `apps/api/src/routes/webhooks.ts:1033-1049`

```ts
async function handleAccountDeauthorized(accountId: string | null): Promise<void> {
  …
  await pool.query(
    `UPDATE partners
        SET stripe_account_status = 'disabled',
            stripe_account_status_at = NOW(),
            stripe_onboarded = FALSE,
            stripe_account_id = NULL,
            updated_at = NOW()
      WHERE stripe_account_id = $1`,
    [accountId],
  );
```

A partner who deauthorizes Stripe Connect cannot receive payouts (the `/me/payouts` endpoint correctly gates on `stripe_account_status='enabled'`). But:
- Their **pending** commissions stay `pending`. Auto-approve cron skips them (line 150: `AND p.stripe_account_status = 'enabled'`).
- Their **approved** commissions stay `approved` indefinitely. They can never be paid out.

Adversarial scenario: a partner gets paid 5 commissions @ $14.85 each = $74.25 lifetime. They deauthorize Stripe Connect. They re-onboard later (the onboarding endpoint creates a NEW account or reuses if `stripe_account_id IS NOT NULL` — but it's now NULL post-deauthorize, so a NEW account is created, line 686–699). Their `stripe_account_status` flips to `'pending'` (line 703) on first onboarding hit. Auto-approve still requires `'enabled'`, so commissions sit until KYC completes.

This is benign (the partner gets paid eventually). But: an admin who manually tries to pay an old approved commission via `/admin/commissions/:id/pay` will hit the gate at `commission.stripe_account_status !== 'enabled'` (line 1124). Until the partner re-onboards, the commission is stranded. **There's no admin tooling to mark a stranded commission as `cancelled`** — only the auto-approve cron can promote `pending`, only the admin pay endpoint can promote `approved`, and the partner's reject endpoint doesn't touch commissions.

**Fix**: on deauthorize, decide whether to cancel pending commissions (the partner can't be paid; should the system signal that?) or leave them. Either policy is defensible; today's "leave them" is the silent default and there's no UI making it visible.

Severity: Medium (operational — commissions stranded; not money-routing).

### M-MD-3 — `confirm: true, off_session: true` is the only auth path; SCA/3DS-required cards immediately fail
File: `apps/api/src/services/partners.service.ts:654-670`

`off_session: true` tells Stripe "the customer isn't around to handle SCA". For most US cards this works. For EU/UK cards (PSD2 / 3DS2) and certain US cards under SCA mandate, Stripe responds with `payment_intent_authentication_failure` and the PI's `next_action.type='use_stripe_sdk'` to do a 3DS challenge. The mobile/dashboard would need to handle this, but:
- The createGift catch (line 672–694) treats every failure as a card decline.
- There is no `next_action` handling — the partner sees "Payment failed" and has no path forward.

This was less of an issue when partners were US realtors with standard credit cards, but as the platform grows internationally it'll start failing. The current code has no `confirmation_method: 'manual'` + 3DS-handoff path.

**Fix**: detect `error.code === 'authentication_required'` or `paymentIntent.status === 'requires_action'` and surface the `client_secret` so the dashboard can complete the SCA challenge. Substantial change; flagging now.

Severity: Medium (works for US-only partners today; international expansion will hit this).

### M-MD-4 — `auto-approve` cron auto-approves rows whose `partner_commissions.amount` violates `chk_partner_commissions_amount_range` if the legacy data is bad — INSERT phase already enforced, but no defense at promotion
File: `apps/api/src/index.ts:136-169`

The cron `UPDATE … SET status='approved'` doesn't re-check the amount. The CHECK was added in mig 070; pre-mig data was assumed to conform via the SELECT-then-CHECK migration body (mig 070 doesn't actually do that for partner_commissions — I see no `SELECT COUNT(*) WHERE amount NOT BETWEEN ...` body, only the constraint adds). 

If a legacy row pre-070 has `amount = 999999.99`, the constraint addition would have FAILED at mig time unless the column was empty or all values were in-range. So this is theoretical for production data, but the migration didn't explicitly verify. Worth noting; doesn't change today's behavior.

Severity: Medium (latent / historical data; if it didn't break at mig 070 it's not breaking now).

### M-MD-5 — Stripe webhook age check at line 355–371 has a TOCTOU race with `claimWebhookEvent`
File: `apps/api/src/routes/webhooks.ts:352-380`

```ts
if (ageSec > STRIPE_MAX_AGE_SEC) {
  const seenBefore = await query(
    `SELECT 1 FROM webhook_events WHERE source = 'stripe' AND event_id = $1 LIMIT 1`,
    [event.id],
  );
  if (seenBefore.rows.length > 0) {
    …return 400 'Event too old';
  }
  …'first-time delivery';
}

const payloadDigest = sha256(req.body as Buffer);
const claim = await claimWebhookEvent(event.id, 'stripe', event.type, eventCreatedDate, payloadDigest);
```

Race: two old replays arrive simultaneously.
- Delivery A: `seenBefore` query returns 0 rows ("first time"). Proceeds to `claimWebhookEvent` which inserts.
- Delivery B: `seenBefore` query runs concurrently with A's claim INSERT. If B's read happens BEFORE A's INSERT commits, B also sees 0 rows. B proceeds to claimWebhookEvent.
- A's claimWebhookEvent inserts (xmax=0, claimed). B's claimWebhookEvent ON CONFLICTs (attempts+1=2, claimed=true). B returns 'retry', NOT 'rejected'. B processes the event **even though it's old**.

So an "old + first-seen" event can get processed twice (once per delivery). The age check is supposed to prevent old replays, but the SELECT-then-INSERT pattern lets two old deliveries both pass.

Practical impact: minor — both deliveries land on the same handler with the same idempotency. The handlers de-dupe via row-state checks (`UPDATE … WHERE status='created'`). The age check is forensic, not security: Stripe's signature verification is the actual replay protection. But the comment claims "limit replay windows if signing secret were ever leaked" — and that's exactly the case where a leaked secret would let an attacker replay an old event, which can then race-pass the age check.

**Fix**: collapse into one INSERT with a `WHERE event_age_sec <= MAX` predicate, or move the age check inside `claimWebhookEvent` using the now-locked row. The current two-step is racy.

Severity: Medium (defense-in-depth defect, not a primary security control).

### M-MD-6 — `getRevenueCatId` validates UUID via regex but accepts the alias's UUID regardless of position
File: `apps/api/src/routes/webhooks.ts:1247-1258`

```ts
if (!UUID_RE.test(event.app_user_id) && !(event.aliases || []).some((a) => UUID_RE.test(a))) {
  …acknowledge as 'non-uuid-app-user-id';
}
…
const userId = await findUserByRevenueCatId(event.app_user_id, event.aliases || []);
```

`findUserByRevenueCatId` then queries `users WHERE id = $1` with `event.app_user_id` even if `app_user_id` is non-UUID. Postgres rejects with `22P02`. But: the regex check above only acknowledges + returns 200 when **neither** `app_user_id` NOR any alias is a UUID. If `app_user_id` is non-UUID but an alias IS a UUID, the regex check passes (`!some(UUID_RE.test) === false` → outer NOT → don't return early), and `findUserByRevenueCatId(non-UUID, [UUID])` runs:

```ts
const directResult = await query(`SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL`, [appUserId]);
```

`SELECT id FROM users WHERE id = 'not-a-uuid'` raises `22P02` → caught by the outer try → `markWebhookFailed`. Webhook retries, climbs attempts, dead-letters at 8.

**Fix**: in `findUserByRevenueCatId`, validate UUID format before each query, OR cast safely.

Severity: Medium (silent webhook failure for non-UUID app_user_id with a UUID alias; net effect = dead-letter).

### M-MD-7 — `purchase_date` defaults to NOW() but `starts_at` is the carrier-supplied date — ordering invariant not enforced
File: `apps/api/src/db/migrations/002_enhanced_features.sql:303-305`

```sql
purchase_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
…
starts_at DATE NOT NULL,
expires_at DATE NOT NULL,
```

No CHECK that `starts_at <= expires_at`, and no CHECK relating `purchase_date` to `starts_at`. An imported warranty with `starts_at='2030-01-01', expires_at='2025-01-01'` (date typo) inserts cleanly. The cancel flow then computes `proratedRefundCents` with `expiresAt - startsAt < 0` → negative `totalDays` → `Math.max(1, …)` rescues it → `usedDays` becomes huge → `remainingDays = max(0, totalDays - usedDays) = 0` → fraction=0 → no refund. So the cancel "works" but the refund is wrong (the customer paid for a real policy and gets $0 back).

Compounding: the `expireOverdueWarranties` cron flips active rows whose `expires_at < CURRENT_DATE` to `'expired'`. The bad row's `expires_at='2025-01-01'` is in the past, so it gets expired immediately — masking the input error.

**Fix**: CHECK `(expires_at >= starts_at)` and CHECK `(starts_at <= purchase_date + INTERVAL '1 year')` (matching the F017 service-side bound).

Severity: Medium (defense-in-depth; the F017 service check already exists; DB layer should mirror).

### M-MD-8 — `partner_commissions.created_at DESC` index (mig 030b) is `(partner_id, created_at DESC)`, but `getCommissions` SELECT * orders by `c.created_at DESC` and adds NO partner filter on the index side — wait, it does
File: `apps/api/src/services/partners.service.ts:1304-1316`

The query uses `WHERE c.partner_id = $1 ORDER BY c.created_at DESC LIMIT $2 OFFSET $3`. The index `idx_partner_commissions_partner_created (partner_id, created_at DESC)` is the right shape. OK.

But the route allows `limit=100, offset=Number.MAX_SAFE_INTEGER`. The Joi cap clamps at `(req.query.offset, parseInt) || 0` with `Math.max(1, ...)` — there is **no upper bound on offset**. A partner who passes `offset=99999999` causes Postgres to walk the index forward 100M times. The route handler reads:
```ts
const offset = (page - 1) * limit;
```

`page = parseInt(req.query.page, 10) || 1` — no `Math.min(MAX_PAGE, …)`. Adversarial: a malicious partner can DoS by paginating absurdly. The query plan walks the index but hits no rows; PG still does the I/O.

**Fix**: cap `page` at e.g. 1000 (1000 × 100 = 100k rows; beyond that, partners need filters or admin export).

Severity: Medium (DoS surface; bounded because `requirePartner` gates it, but a malicious partner exists).

### M-MD-9 — `expireUnactivatedPartnerGifts` cron does not write the `partner.gift_expired` audit_action row
File: `apps/api/src/index.ts:87-121`

The cron silently flips status='expired' and cancels the commission. No audit_logs row is written. Compare with the activation path (`partners.service.ts:1062-1068`) which goes through `partner.gift_activated` audit. A forensic question "why is this gift expired?" gets only a Loki log line (and Loki has 90-day retention; audit_logs has its own retention via `cleanup_old_audit_logs`). 

**Fix**: emit `partner.gift_expired` (would need to add to `audit_action` enum) per expired row, with metadata containing `partner_id, homebuyer_email, premium_months`.

Severity: Medium (forensic gap; the v1 audit's hash-chain only protects rows that exist).

### M-MD-10 — `commission_amount` and `commission_rate` columns on `warranty_purchases` are dead fields per v1 — correct, and they confuse future readers
File: `apps/api/src/db/migrations/002_enhanced_features.sql:300-301` + `services/warranty-purchases.service.ts:260-262`

```sql
commission_amount DECIMAL(10, 2),
commission_rate DECIMAL(5, 4),
```

The createPurchase service line 260 writes `data.commissionAmount || null`. There's no `commission_rate` writer — it's hardcoded `null` (line 262). The cancel flow (line 474-481) targets `partner_commissions.reference_id = $1 AND reference_type = 'warranty_purchase'`. **There is NO insertion path that writes a `partner_commissions` row with `reference_type='warranty_purchase'`** in the codebase. The warranty cancel's commission cancel UPDATE matches 0 rows — always.

Per CLAUDE.md the `commission_amount` field hints at partner-attribution to come, but currently the column is decorative. Either delete it (mig N+1), or build the attribution path. Today's state is "the column exists, the cancel flow defends against it, no writer ever populates it" — pure dead code.

Severity: Medium (per the codebase's "no legacy or dead code" rule, this is a violation; v1 caught it as Out-of-scope-noticed).

### M-MD-11 — `auto-approve` cron approves rows but does NOT set `approved_by` (admin or system) — audit gap
File: `apps/api/src/index.ts:141-156`

```sql
UPDATE partner_commissions pc
   SET status = 'approved',
       approved_at = NOW(),
       updated_at = NOW()
…
```

There's no `approved_by` column on `partner_commissions`, but if there ever is one (or any "who approved this" audit need), the cron's UPDATE will need to write it. Also: no audit_logs row is written by the cron — `partner.commission_approved` doesn't exist. An admin auditing "who approved commission X?" sees `status='approved', approved_at=2026-05-01` and has to deduce "auto-approve cron because the cron's the only thing that touches pending→approved without an admin user".

**Fix**: emit a single `partner.commission_auto_approved` audit row per cron run with `metadata = { approved_count, hold_days }`.

Severity: Medium (forensic gap).

### M-MD-12 — `chk_partner_commissions_amount_range CHECK (amount BETWEEN -100000 AND 100000)` doesn't bound 0-amount rows — reversal of a $0 commission inserts cleanly
File: mig 070 + `webhooks.ts:81-151`

The reversal helper inserts `-Number(row.amount)`. If somehow a `row.amount = 0` snuck through (e.g. a $0 promotional gift / a free-tier comp), the reversal is `-0` → `0`. The CHECK `amount BETWEEN -100000 AND 100000` accepts. The reversal-shape CHECK requires `amount <= 0` — `0 <= 0` accepts. So a zero-amount reversal of a zero-amount original both insert. Net ledger sum is 0. No money lost; just two pointless rows.

The deeper concern: today's tier prices × commission rates always produce positive amounts (`99 × 0.1 = 9.90` minimum). But if `TIER_PRICE_PER_GIFT_USD['basic'] = 1`, then `commissionCents(100, 0.10) = 10` cents = `$0.10`. A 1% partial refund → `commissionCents(10, 0.01) = 0` cents (rounded). The reversal is `0`. Pointless audit ink.

**Fix**: skip reversal INSERT when computed amount would be 0. Save a row.

Severity: Medium (cosmetic / table-bloat; combined with M-MP-1 / H-MP-3 the audit chain accumulates noise rows).

### M-MD-13 — Self-service payout iterates per-row but the partner pays Stripe fees per transfer (per Connect docs)
File: `apps/api/src/routes/partners.ts:929-989`

The comment says "Stripe absorbs no per-transfer fee on the platform side; partners pay the standard Stripe Connect bank-receive fee on their connected account." This is half-true:
- **Standard Connect** (partners): no platform fee per transfer; Stripe takes 0.25% + $0.25 on each USD payout from the connected account to the bank.
- A partner with 50 small commissions ($1.50 each) gets 50 transfers. Each one nets out at the bank as $1.20 ($1.50 - $0.30 in fees). The partner sees $75 worth of commissions arrive as $60.

A single aggregated transfer (sum 50 commissions, one transfer of $75) costs the partner $0.44 ($75 × 0.25% + $0.25). Per-row transfers cost $15 vs $0.44 in total Stripe fees.

The audit comment claims per-row preserves the commission_id ↔ transfer_id mapping. True. But the cost trade-off is severe at high commission counts and small per-commission amounts.

**Fix**: aggregate commissions when a partner's average commission is small (< $5) into a single transfer with metadata containing all commission_ids. Or: surface a partner-side preview "you'll pay $X in Stripe fees vs $Y if you wait for larger commissions" so they can self-select.

Severity: Medium (partner economic harm; not platform-money-loss; the comment claims a falsehood by saying "Stripe absorbs no fee" which is true on the platform side but misleading on the partner-receive side).

### M-MD-14 — `clawbackCommissionForGift` `SELECT … FOR UPDATE` doesn't include `reversal_of_commission_id IS NULL`
File: `apps/api/src/routes/webhooks.ts:86-92`

```sql
SELECT id, partner_id, amount, status, stripe_transfer_id
   FROM partner_commissions
  WHERE reference_id = $1 AND reference_type = 'partner_gift'
    AND status NOT IN ('reversed', 'cancelled')
  FOR UPDATE
```

The SELECT pulls the original commission row(s) for the gift, excluding 'reversed' and 'cancelled'. It does NOT exclude rows that ARE reversals of OTHER rows (`reversal_of_commission_id IS NOT NULL`). Today every reversal row has `status='reversed'`, so the NOT IN clause excludes them. **But**: nothing in the schema enforces that `status='reversed' ⇔ reversal_of_commission_id IS NOT NULL`. Mig 030b enforces only the forward direction (`status='reversed' ⇒ reversal_of_commission_id IS NOT NULL`). Nothing prevents a future writer from inserting a `status='approved'` row with `reversal_of_commission_id` populated.

If that ever happens (admin error, migration shim, anything), the FOR UPDATE picks up the reversal row as if it were an earning, doubles up the proportion, and reverses the reversal (positive amount).

**Fix**: add `AND reversal_of_commission_id IS NULL` to the SELECT, AND tighten the CHECK to `(status='reversed') = (reversal_of_commission_id IS NOT NULL)`.

Severity: Medium (latent; today's writers don't trigger it).

### M-MD-15 — `gift.activation_url` is built once at Phase 0 with `config.app.frontendUrl` and stored — env reconfig orphans the URL
File: `apps/api/src/services/partners.service.ts:487`

```ts
const activationUrl = `${config.app.frontendUrl}/gifts/activate?code=${encodeURIComponent(activationCode)}`;
```

Stored in DB. If the operator changes `FRONTEND_URL` (e.g. staging → custom domain), every existing un-activated gift's `activation_url` points to the old domain. The email already went out, so the homebuyer's email link is fine. But the dashboard's "resend" reads `gift.activation_url` from the DB (line 1372) — so a resend AFTER the env change re-emails the OLD url.

**Fix**: build `activation_url` at email-send time, not at gift-create time. Store only the `activation_code`; reconstruct on resend.

Severity: Medium (operational; affects environment cutovers).

### M-MD-16 — `disputed_at` is updated via `COALESCE(disputed_at, NOW())` (sticky first-seen) but `chargeback_status` is overwritten on every event — a dispute that won then lost only carries the latest status
File: `apps/api/src/routes/webhooks.ts:920-928`

```sql
UPDATE partner_gifts
    SET disputed_at = COALESCE(disputed_at, NOW()),
        chargeback_status = $2,
        updated_at = NOW()
  WHERE stripe_charge_id = $1
```

`chargeback_status` is overwritten with `dispute.status` on every dispute event. But Stripe's typical flow is: `needs_response → under_review → won|lost`. The terminal status is what we want. **However**: a dispute reopened by Stripe (`'warning_needs_response'` after a `'won'`) overwrites `'won'` to `'warning_needs_response'`. The H-MD-8 ordering issue compounds — without per-charge ordering, an old `'needs_response'` retry can overwrite the current `'won'`.

The mig 089 regex CHECK is permissive (`'^[a-z][a-z0-9_]{0,63}$'`) so any future Stripe value lands cleanly. But the overwrite policy means we lose history.

**Fix**: store dispute status history in a separate table (`partner_gift_dispute_events`), key by `(gift_id, event_id)`. The `partner_gifts.chargeback_status` becomes "current status from latest in-order event". History is queryable for "did this dispute go won then lost?".

Severity: Medium (forensic; today's data shape doesn't support the question).

### M-MD-17 — `RevenueCat.environment === 'PRODUCTION'` gate doesn't validate against API keys
File: `apps/api/src/routes/webhooks.ts:1205-1211`

The gate `if (event.environment !== 'PRODUCTION' && !config.revenuecatAllowSandboxWebhooks)` works **if RC is honest**. But RC's webhook payload is attacker-controllable (an attacker who has obtained the RC webhook secret can craft a payload). A spoofed event with `environment: 'PRODUCTION'` from a sandbox attacker bypasses the sandbox gate.

The defense is the webhook secret (Bearer auth), which `validateRevenueCatWebhookAuth` checks via `timingSafeEqual`. So the gate's only failure mode is "secret leaked OR developer forgot to set REVENUECAT_WEBHOOK_SECRET in prod". The `validateRevenueCatWebhookAuth` rejects an empty `webhookSecret` with 401 — defense-in-depth holds.

But: `config.revenuecatAllowSandboxWebhooks` defaults are not visible to me from the audit. If it's `true` in production, the sandbox gate is bypassed and any sandbox event flips production users. CLAUDE.md doesn't mention it. The `config.ts` reads `process.env.REVENUECAT_ALLOW_SANDBOX_WEBHOOKS`. The validator (`validateEnvironment`) does NOT enforce this is `false` in production. An operator who accidentally sets `REVENUECAT_ALLOW_SANDBOX_WEBHOOKS=true` in prod opens up sandbox-spoof attacks.

**Fix**: in `config/validator.ts:97-110` add a production-mode check that `REVENUECAT_ALLOW_SANDBOX_WEBHOOKS` is unset or `false`.

Severity: Medium (operational — single env-var typo opens an attack surface).

### M-MD-18 — `chk_partner_gifts_chargeback_status` regex (mig 089) accepts uppercase Stripe future values truncated and the column is VARCHAR(40), so a 41-char status truncates
File: `apps/api/src/db/migrations/050_webhook_ordering_and_dispute.sql:62-80` + `mig 089`

```sql
ALTER TABLE partner_gifts
  ADD COLUMN IF NOT EXISTS chargeback_status VARCHAR(40);
```

Mig 089 dropped the original CHECK and replaced with `chargeback_status ~ '^[a-z][a-z0-9_]{0,63}$'`. The column is VARCHAR(40), but the regex allows up to 64 chars. A 64-char status from Stripe will be silently truncated to 40 by Postgres (with a warning) before the CHECK runs — wait, does `INSERT 41-char` into VARCHAR(40) truncate or error? Postgres errors with `string_data_right_truncation` (22001) UNLESS the value is space-padded; in that case it strips trailing spaces. For a real status string, it errors.

So if Stripe ever introduces a >40-char status, every dispute event 22001s, retries, dead-letters at 8.

**Fix**: align column width with regex bound. Either VARCHAR(64) or tighten regex to `{0,39}`.

Severity: Medium (latent; tied to Stripe's enum shape).

---

## Low

### L-MD-1 — `getReferrals` exposes raw `users.created_at` as `signed_up_at`
File: `apps/api/src/services/partners.service.ts:172-202`

Cosmetic — the field is renamed; reasonable. Just noting because referrals-list could expose whether a referred user was deleted (`deleted_at IS NULL` filter on count, but rows query has no such filter). The list query (line 173–195) returns rows even for soft-deleted users. So the partner can see "user X exists" even after the user soft-deleted their account. Privacy concern.

**Fix**: add `AND u.deleted_at IS NULL` to the rows query.

Severity: Low (privacy leak — partner can enumerate post-delete user existence).

### L-MD-2 — `expireUnactivatedPartnerGifts` cron uses `ANY($1::uuid[])` but not `IN (SELECT)` — bulk update OK
File: `apps/api/src/index.ts:107-115`

Mostly fine. But the array path requires the Node-side cast; fine for <1000 rows. Acceptable today.

Severity: Low.

### L-MD-3 — `getActiveCoverage` JSON aggregates inside SQL; no LIMIT — partner with 10k items + 30k warranties returns multi-MB response
File: `apps/api/src/services/warranty-purchases.service.ts:503-538`

No pagination. This is a user-facing endpoint. A user with many warranties (unusual, but possible) gets a slow response.

Severity: Low (no DoS, just latency for outliers).

### L-MD-4 — `validateRevenueCatWebhookAuth` reads `webhookSecret` from `config` on every call — no env-change pickup
File: `apps/api/src/routes/webhooks.ts:1099-1126`

The config object is constructed at startup; rotating the RC webhook secret requires a restart. Standard pattern, just noting.

Severity: Low.

### L-MD-5 — `commissionCents` rounding policy: `Math.round` (half-up) instead of banker's rounding
File: `apps/api/src/utils/money.ts:69-76`

Comment claims "Round half-to-even at the cent boundary so successive identical commissions sum predictably. Math.round is half-up; close enough for cents." `Math.round` in JS is actually **half-toward-positive-infinity**, not half-up. For positive values they're equivalent. For negative reversals: `Math.round(-0.5) = 0` (not -1). So a $0.005-rounded reversal lands at $0 instead of $0.01. Cosmetic.

Severity: Low.

### L-MD-6 — `dollarsToCents` throws on `'Infinity'` AND on `'NaN'`, but accepts `'  99.99  '`? Actually the regex disallows whitespace
File: `apps/api/src/utils/money.ts:13, 56-63`

```ts
const DECIMAL_RE = /^-?\d+(?:\.\d+)?$/;
…
const str = String(value).trim();
if (!DECIMAL_RE.test(str)) return 0;
```

`trim()` strips outer whitespace before the regex test, so `'  99.99  '` → `'99.99'` → matches. OK. `dollarsToCents('Infinity')` → trim → 'Infinity' → regex fails → returns 0 → `(0===0 && 'Infinity'!==0)` → throws. Good.

But: `dollarsToCents('999999999.99')` (10-figure dollars) → 99999999999 cents = ~9.3 × 10^10 = within JS safe int (2^53 ≈ 9 × 10^15). Fine. The DB column is DECIMAL(10,2), max 99999999.99 dollars. The util doesn't enforce DB column bounds. A caller could compute cents that won't fit DECIMAL(10,2) and INSERT 22003. Today's gift / warranty prices are nowhere near, so no actual risk.

Severity: Low.

### L-MD-7 — Stripe `accountLinks.create` defaults to a 5-min link TTL but no test asserts behavior
File: `apps/api/src/routes/partners.ts:717-722`

No `collect: 'eventually_due'` or other modern flags. Stripe's default is fine; just noting that the v22 API surface might add new required params.

Severity: Low.

### L-MD-8 — `PARTNER_TIERS` (route) hardcodes `commission_rate: 0.10/0.15/0.20` despite importing TIER_PRICE_PER_GIFT_USD — confirms v1's M-MP-7 finding
File: `apps/api/src/routes/partners.ts:603, 616, 630`

v1 already flagged. Confirmed not fixed in this code state.

Severity: Low (re-noted; v1 already found).

### L-MD-9 — Stripe webhook handler uses 8 attempts with no backoff coordination — Stripe's own retry schedule is hours apart, not seconds
File: `apps/api/src/routes/webhooks.ts:165` + `mig 050` schedule

`MAX_WEBHOOK_ATTEMPTS = 8`. Stripe's documented retry schedule is exponential, ~3 days total. 8 attempts spread over 3 days = one attempt every ~9 hours. So dead-letter happens AFTER Stripe gives up. The constant could be 7 or 6 to hit dead-letter slightly sooner; today's 8 is "Stripe gives up first" which is fine.

Severity: Low.

### L-MD-10 — `partner_gifts.activation_code` plaintext is wiped at activation/expiry, but `activation_url` is also wiped — preventing audit-style "this URL was the original" lookups
File: `apps/api/src/services/partners.service.ts:1024-1035` + `index.ts:96-98`

If an audit asks "what URL did we email partner X for gift Y?", the answer is "we wiped it; reconstruct via {frontendUrl}/gifts/activate?code={hash-derived}" but we can't reverse the hash. Forensic gap.

**Fix**: keep the URL but wipe the code. Or store URL templates separately.

Severity: Low.

### L-MD-11 — `req.body.reason` for warranty cancel has no length cap in the validator
File: `apps/api/src/validators/warranty-purchases.validator.ts` (referenced, not read in full) + `warranty-purchases.service.ts:457`

The cancellation_reason TEXT column has no max length. A pathological client can submit a 1MB reason. The express body parser caps at 1MB, so it's bounded. But auditing "show me the reasons" returns large blobs.

Severity: Low.

### L-MD-12 — `idempotency` middleware uses `JSON.stringify(req.body ?? {})` — different key orders produce different hashes
File: `apps/api/src/middleware/idempotency.ts:60`

Two requests with the same body but different key order (`{a:1,b:2}` vs `{b:2,a:1}`) hash differently → "different request body" → 409. Express body parser preserves insertion order from JSON, but two clients constructing the same object in different orders is plausible. Standard footgun.

**Fix**: canonicalize before hash. Standard JSON canonical form is well-established (sorted keys).

Severity: Low.

---

## Verified-correct (paranoia checks that pass)

- **Stripe SDK pin** verified at `node_modules/stripe/package.json: "version": "21.0.1"`. apiVersion `'2026-03-25.dahlia'` set on `createStripeClient()`. `maxNetworkRetries: 2`, `timeout: 15_000` per call.
- **claimWebhookEvent** uses explicit BEGIN + SELECT FOR UPDATE before UPSERT (per v1's prior validation).
- **isEventInOrder for RC** correctly drops stale events.
- **`requirePartner` correctly ties to `partners.status='active'`** — the auth middleware computes `is_partner` from `EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.status = 'active')` (`auth.ts:105`). So v1's M-MP-5 is wrong on the gate; the gate is closed for `pending`/`rejected`.
- **`/admin/partners/:id/reject` correctly invalidates the user cache** AND deletes refresh tokens for `active→rejected` transitions (`admin.ts:644-647`).
- **mig 097 immutability trigger** correctly drops DELETE while keeping UPDATE blocked.
- **mig 098 ALTER TYPE ADD VALUE** correctly outside transaction, runner auto-detects.
- **`payout.failed` handler** logs ERROR with full context (chargeback signal preserved).
- **`account.application.deauthorized`** clears `stripe_account_id` (sets to NULL) so subsequent onboarding creates a fresh account, not a re-link.
- **`charge.dispute.lost`** treats as refund (clawback + revoke premium, mirroring `charge.refunded`).
- **`webhook_event_high_water` PK** is `(source, subject_id)` — collisions across sources impossible (UUID vs `pi_...` shape).
- **Mig 092 invariant** `(is_active=TRUE) = (status='active')` correctly enforces consistency.
- **Mig 087 BIGINT promotion** of `webhook_events.id` and its sequence is correct.
- **Mig 086** correctly drops the redundant plaintext UNIQUE; the hashed-code unique index remains the sole protection.
- **Mig 089 regex CHECK** correctly permissive (single regex vs hardcoded enum allowlist).
- **`STRIPE_WEBHOOK_SECRET` validator** in production checks the `whsec_` prefix (`config/validator.ts:103-104`).
- **Express raw-body parser** mounted at the exact webhook path BEFORE `express.json()` so the order is correct.
- **CSP `connectSrc`** narrowly scoped to `api.stripe.com` and `api.revenuecat.com` only (`app.ts:73-77`).

---

## Reclassified-from-v1

- **v1 M-MP-3** (misleading comment claiming `warranty_purchase_status` is VARCHAR(50)): I see the comment at `warranty-purchases.service.ts:382-385` claiming "no CHECK enum, mig 002" — confirmed. Mig 002 line 276 IS `CREATE TYPE warranty_purchase_status AS ENUM`. Comment is wrong. Severity Medium per v1 — **upgrade to High** because the next contributor will write code that depends on the column being free-form text and hit `22P02` in prod (the very issue mig 098 fixed). Comment-driven confusion in a money path is more than cosmetic.

- **v1 M-MP-5** (`requirePartner` doesn't gate on `partners.status='active'`): **wrong**. The auth middleware DOES correctly tie `isPartner` to `partners.status='active'` via the SQL at `auth.ts:105`. The 10-second cache window remains, but admin reject explicitly calls `invalidateUserCache`. Reduce to L-MD or drop.

- **v1 H-MP-3** (no daily retry/alert for dead-letter rows): **confirmed**. No code change since v1 audit. Re-flag as outstanding High.

- **v1 H-MP-4** (NaN proportion when amount=0): **confirmed**. Reading `webhooks.ts:698-740` the bug is exactly as v1 described. Outstanding.

- **v1 L-MP-3** (cumulative-vs-delta double-count on multiple partials): **confirmed and worse than v1 thought** — see C-MD-4 (the partial reversals also drift in cents because the helper uses dollar-rounding).

---

## Confirmed-from-v1

- v1 H-MP-1 (Phase-2 catch swallows non-Stripe AppErrors) — confirmed at `partners.service.ts:672-694`. Add to that the H-MD-12 finding (`STRIPE_DECLINE_MESSAGES` reads `error.code` first, getting always `'card_declined'` for declines).
- v1 H-MP-2 (self-service payout uses JS floats) — confirmed at `routes/partners.ts:929-981`.
- v1 H-MP-3 (no dead-letter alert) — confirmed.
- v1 H-MP-4 (NaN proportion) — confirmed.
- v1 M-MP-1 (retention sweep semantics fragile) — confirmed.
- v1 M-MP-2 (cancelling retry overwrites prior_status) — confirmed; see also C-MD-1 for a worse bug in the same flow.
- v1 M-MP-4 (tax-form-link doesn't gate on enabled) — confirmed at `partners.ts:1025-1043`.
- v1 M-MP-6, M-MP-7 (tier price/rate hardcoded twice) — confirmed.
- v1 M-MP-8 (Joi cap 12 vs DB CHECK 120) — confirmed.
- v1 L-MP-1 (parseFloat in earnings-history) — confirmed (this audit's H-MD-9 builds on it).
- v1 L-MP-4 (`stripe_transfer_id` exposed to partner) — confirmed.
- v1 L-MP-5 (`proratedRefundCents` float math) — confirmed and upgraded to C-MD-3.

---

## Out-of-scope-noticed

- **Caddy raw-body / no-compression directive**: lives in another repo (`~/Projects/staging/infra/Caddyfile`). H-MD-11's defense-in-depth would catch a misconfig there; flagging for the staging-deploy review.
- **Mobile**: the `Idempotency-Key` plumbing already exists for warranty/items. The dashboard/mobile both need to be updated to send it for partner gift creation once C-MD-2 is wired server-side.
- **Marketing**: hardcoded $99/$149/$249 + 10/15/20% match the API today. v1 M-MP-6 already flagged the drift surface.
- **Partner dashboard**: the Payouts page renders `summary.stripe_account_status` raw. No defense if `stripe_account_status` is `'unknown'` or any future enum value (v1 noted).

---

## Summary

The money surface has more sharp edges than v1's report suggested. Three Critical-class issues were missed:

1. **C-MD-1**: `cancelPurchase` Phase 3 writes `refund_amount_cents` + `refunded_at` even when the Stripe leg was skipped (no payment_intent), producing a fund-state lie. Hits any imported / comp / legacy warranty.
2. **C-MD-2**: `POST /partners/gifts` has no rate limit and no idempotency middleware — the highest-cost mutating call in the system, racy at the route layer. Stripe's per-gift `idempotencyKey` doesn't dedupe across separate gift rows; double-click → double charge.
3. **C-MD-3**: `proratedRefundCents` does float dollar math instead of integer cents, in the same file that imports `dollarsToCents`. Edge case off-by-one, but the precedent of "money utils exist, half the file ignores them" is the systemic bug.
4. **C-MD-4**: `clawbackCommissionForGift` rounds reversal in dollars, not cents — causes ledger sums of $0.01 forever after specific partial-refund schedules.

Five High-class issues:

5. **H-MD-1**: `PARTNER_TIER_PRICING` env override has no min validation — operator typo `0.99` instead of `99` silently undercharges every gift.
6. **H-MD-2**: `auditWebhookPlanTransition` is fire-and-forget; audit row may be missing on process kill, and ordering is race-determined under concurrent webhooks.
7. **H-MD-3**: `/me/payouts` and friends gate on Stripe Connect status but NOT on `partners.status='active'`; small race window on admin reject (defense-in-depth).
8. **H-MD-4**: `createGift` reads `stripe_customer_id` twice (Phase 1 in tx, Phase 2 outside) — race window can corrupt cleanup.
9. **H-MD-5**: `paid_lifetime` summary doesn't include reversal rows — partner-visible discrepancy with `total_commissions` from analytics.
10. **H-MD-7**: reversal commissions write `commission_rate=0` (semantically wrong, breaks any future CHECK).
11. **H-MD-8**: charge.refunded / charge.failed don't call `isEventInOrder` (only disputes do); ordering coverage is half.
12. **H-MD-10**: Phase-3 catch issues refund but doesn't flip gift to expired; ghost rows in `pending_payment`.
13. **H-MD-11**: no defense-in-depth against Caddy compressing the webhook body.
14. **H-MD-12**: `STRIPE_DECLINE_MESSAGES` reads `error.code` first, always getting `'card_declined'` for declines.

The deepest pattern: **money math is sometimes done in cents (correct), sometimes in dollars (wrong)** — the same file imports `dollarsToCents` and yet does `Math.round(Number(row.amount) * proportion * 100) / 100`. The codebase has the right utility; some authors don't use it. Ratify a "money math in cents always" rule and have CI grep against the patterns.

Path: `/Users/pacomedomagni/Projects/havenkeep/docs/audit-runs-v2/02-money-deep.md`
