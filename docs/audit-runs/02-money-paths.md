# Audit Run 02 — Money Paths (Stripe / Commissions / Payouts / RevenueCat)

Date: 2026-05-10
Scope: `apps/api/src/services/partners.service.ts`, `apps/api/src/services/warranty-purchases.service.ts`, `apps/api/src/routes/webhooks.ts`, `apps/api/src/routes/partners.ts`, `apps/api/src/utils/{stripe-client,money}.ts`, mig 030a/b · 050 · 070 · 071 · 078 · 086 · 087 · 092 · 095 · 096 · 097 · 098, the auto-approve cron in `apps/api/src/index.ts`, related tests.

---

## Critical (fund-routing / lost-money / double-charge)

None confirmed. The four highest-risk flows — three-phase gift create, three-phase warranty cancel, full+partial commission clawback, self-service payout — all have appropriate Stripe/DB interleaving (Stripe outside DB tx), idempotency keys, and replay-safe terminal-state guards. The remediation arc that produced the audit log shows up clearly: every `stripe.*.create` call passes `idempotencyKey`, the legacy "Stripe-inside-BEGIN" pattern is gone, both `partner_gifts` and `partner_commissions` enforce structural CHECK constraints, and the immutable trigger on `warranty_claim_state_history` was correctly relaxed to allow CASCADE pruning while still blocking UPDATE.

The findings below are all High/Medium/Low — none of them lose money outright. Several of them are close enough to the line that I've called them out.

---

## High

### H-MP-1 — `createGift` Phase-2 catch swallows non-Stripe AppErrors and rewrites them as generic 402 declines
File: `apps/api/src/services/partners.service.ts:628-695`

The Phase-2 `try` block contains three pre-Stripe throws inside it:
- `throw new AppError('Tier amount is invalid', 500)` (line 632)
- `throw new AppError('Stripe customer was deleted; please re-add a payment method', 402)` (line 643)
- `throw new AppError('No saved payment method on file…', 402)` (line 648-651)

All three are caught by the same `catch (stripeError: any)` (line 672) which **always** rewrites the response to `STRIPE_DECLINE_MESSAGES[declineCode] || 'Payment failed. Please check your payment method and try again.'` at HTTP 402. The catch also force-runs the `UPDATE partner_gifts SET status = 'expired'` cleanup, which is fine for these specific cases — but the error message returned to the partner is wrong:

- A 500 ("Tier amount is invalid") is downgraded to a 402 ("Payment failed"), hiding a real misconfiguration.
- The "No saved payment method" actionable message is replaced with a generic decline string.
- The "Stripe customer was deleted" message — the only one that points the partner at the right fix — is replaced with the generic message.

**Fix**: re-throw `AppError` instances unmodified before entering the decline-code branch. `if (stripeError instanceof AppError) { /* still expire the row */; throw stripeError; }`.

Severity: High (UX + observability — partners chase the wrong failure mode; the 500 for invalid tier silently masquerades as a card decline in dashboards and logs).

### H-MP-2 — Self-service payout sums dollar amounts in JS floats; `paid_total` drifts at scale
File: `apps/api/src/routes/partners.ts:929-981`

Three float-math sites in the payout endpoint, all of which the centralised `money.ts` was written specifically to avoid:

1. Line 930: `const amountCents = Math.round(Number(row.amount) * 100)`
2. Line 976: `paidTotal += Number(row.amount)` (accumulates dollars)
3. Line 980: `amount: Number(row.amount)` (returned to caller)
4. Line 1131: same pattern as #1 in the admin pay endpoint.

Today the column is `DECIMAL(10,2)` so `Math.round(x*100)` recovers exactly for two-decimal inputs (e.g. `19.99 * 100 → 1998.999…` → `Math.round` → `1999`). But:

- `paidTotal` accumulates floats — the audit's own comment at `partners.service.ts:1239-1240` says "parseFloat on DECIMAL would compound float drift at the 100-row scale (100 × $0.07 → $6.999999)". Same author, same risk, opposite policy.
- `paidTotal.toFixed(2)` is then embedded in the audit-log description (`partners.ts:994`) and returned to the dashboard verbatim. A partner who runs a 200-commission sweep can see `$13.999999999999998` formatted to `13.99` when the true sum is `$14.00`.
- The same anti-pattern in `getEarningsHistory` (`partners.service.ts:1275`: `parseFloat(row.earnings) || 0`) is explicitly inconsistent with `getPartnerAnalytics`'s integer-cent path two functions up.

**Fix**: switch every site to `decimalToCents` / `centsToDecimalString` from `utils/money.ts`. The util exists; this is purely a "use it" issue.

Severity: High (money-rendering drift; reconcile-pain when an operator compares `paidTotal` to the per-row Stripe transfers).

### H-MP-3 — No daily retry / alert for `webhook_events.status='dead_letter'`
File: `apps/api/src/index.ts` (no callsite — it doesn't exist), `apps/api/src/routes/webhooks.ts:163-237`

The webhook-claim path correctly transitions a row to `'dead_letter'` after `attempts >= 8` and acknowledges the webhook 200 to stop the retry loop. CLAUDE.md Part 2 says: *"Webhook events table tracks delivery + retries with dead-letter at attempt 8."* The audit task mentions: *"Is there an alert for dead-letter rows? Does the daily retry actually work?"*

Searching the daily scheduler in `index.ts:171-345` and the services tree, **there is no daily cron that re-drives or alerts on dead-letter rows**. Once a Stripe `charge.refunded` or `account.updated` lands in dead-letter, it sits there silently — the only signal is the `logger.error` line emitted on the 8th attempt. There is no:
- Cron that scans `WHERE status='dead_letter'` and surfaces a metric or alert.
- Replay tooling that resets a dead-letter row to `'pending'` after the underlying bug is fixed.
- Reconciliation cron that diffs `partner_gifts.stripe_charge_id` against Stripe's API to detect "we missed a refund 8 times".

The 7-day retention sweep at `index.ts:308-322` (`DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'`) would even **delete a dead-letter row 7 days after its last attempt** if the operator never noticed — the dead-letter row never gets a `processed_at` set, so it should survive, but the comment claims daily-not-weekly retention so the row's TTL is short.

**Fix**: add a daily job that `SELECT * FROM webhook_events WHERE status='dead_letter'` and emits an ERROR-level log line per row (Loki-paged), or wires into a Slack/PagerDuty webhook. Optionally add an admin route that flips a specific event back to `'pending'` for manual re-drive.

Severity: High (silent failure of the last line of defence; a real bug in a webhook handler eats refunds for 3 days, then we never hear about it).

### H-MP-4 — Charge-refunded handler doesn't dedupe across delivery streams when amount=0
File: `apps/api/src/routes/webhooks.ts:688-740`

`fullyRefunded = charge.amount > 0 && charge.amount_refunded >= charge.amount`. If `charge.amount === 0` (Stripe sometimes sends $0 refund events on test mode and $0 invoice items), `fullyRefunded === false`, then line 724:

```ts
const proportion = amountRefunded / amount;  // 0/0 = NaN, 1/0 = Infinity
await clawbackCommissionForGift(client, gift.id, proportion);
```

A `NaN` proportion lands at `Math.round(Number(row.amount) * NaN * 100) / 100 = NaN`, and the INSERT into `partner_commissions(amount, …) VALUES (NaN, …)` will fail the `chk_partner_commissions_amount_range` CHECK (mig 070, line 80-83) with a `23514`. The webhook handler catches it, marks the event failed, and Stripe retries up to 8x → dead-letter. Combined with H-MP-3, this is a silent data-loss path on a corner-case charge shape.

**Fix**: guard before the proportion calc — `if (amount <= 0) { logger.warn(...); return; }`.

Severity: High (corner case but combines with the no-alert dead-letter to produce silent failure).

---

## Medium

### M-MP-1 — `webhook_events` retention sweep can prune dead-letter rows whose `processed_at IS NULL`
File: `apps/api/src/index.ts:308-322`

The query is `DELETE FROM webhook_events WHERE processed_at < NOW() - INTERVAL '7 days'`. A `'dead_letter'` row never gets `processed_at` set (only `markWebhookProcessed` sets it, and dead-letter never calls it). So `processed_at` stays `NULL`, and `NULL < NOW() - INTERVAL '7 days'` is `NULL` → not deleted. **OK on inspection — dead-letter rows persist.** But this is fragile: if a future change ever sets `processed_at` on dead-letter (e.g. for a "we acknowledged Stripe's retry" timestamp), the retention cron would silently start deleting forensic evidence.

**Fix**: make the retention `DELETE` explicit — `WHERE status = 'processed' AND processed_at < NOW() - INTERVAL '7 days'`. Same outcome today, semantically robust.

Severity: Medium (latent — depends on a future-author change, but cheap to harden).

### M-MP-2 — Phase-1 `cancelling` retry overwrites `prior_status` so a true-restore is impossible
File: `apps/api/src/services/warranty-purchases.service.ts:336-394`

If a partner triggers cancel, Phase 1 commits `status='cancelling'`, then Phase 2 (Stripe) fails. The `catch` at line 423-438 restores via `WHERE id = $1 AND status = 'cancelling'` `SET status = $2 = existing.prior_status` ('active'). **First retry path is correct.**

But on the next retry: Phase 1 reads `row.status === 'cancelling'`, the conditional at line 363 is a comment-only branch (no early-return), then line 393 does `existing = { ...row, prior_status: row.status }` — `prior_status` is now `'cancelling'`, NOT `'active'`. If Phase 2 fails again, the catch UPDATEs `SET status = 'cancelling' WHERE status = 'cancelling'` — a no-op. The row stays in `cancelling`. The user would have to retry again, hoping Phase 2 succeeds eventually.

There is **no recovery cron** for stuck-`cancelling` rows. A user who tries cancel, hits a transient Stripe error, gives up → row sits in `cancelling` forever. The DB CHECK on `warranty_purchase_status` (mig 098 added the enum value) accepts it, but the user's UI now says "cancelling…" and the warranty is functionally unusable (user can't cancel again — they'd have to ask support).

**Fix**: either (a) on retry of a `cancelling` row, look up the original `prior_status` from `audit_logs` or a dedicated column; or (b) add a daily reconciler cron that picks up `WHERE status='cancelling' AND updated_at < NOW() - INTERVAL '1 hour'`, queries Stripe for the refund (the idempotency key `warranty-refund-<id>` makes it deterministic), and either advances to `'cancelled'` or restores to `'active'`. The audit task explicitly asked: *"can a process crash leave a row stuck in `cancelling`? Is there a recovery mechanism?"* — Yes it can; no there isn't.

Severity: Medium (user-visible stuck state; not money-routing but a UX/operational dead end).

### M-MP-3 — Misleading comment in `cancelPurchase` — `warranty_purchase_status` IS an enum, not VARCHAR(50)
File: `apps/api/src/services/warranty-purchases.service.ts:382-385`

> "The status column on warranty_purchases is a plain VARCHAR(50) (no CHECK enum, mig 002) so 'cancelling' is accepted."

Mig 002 line 276 is `CREATE TYPE warranty_purchase_status AS ENUM ('active', 'expired', 'cancelled', 'claimed')`; mig 023 added `'pending'`; mig 098 added `'cancelling'`. The column is **a Postgres ENUM**. Without mig 098 the `'cancelling'` literal would have raised `22P02` (this is exactly what mig 098 fixed). The comment is wrong and contradicts the migration ledger. Cosmetic but confusing for the next person to touch this code.

**Fix**: replace the misleading comment with: *"`warranty_purchase_status` enum gained `'cancelling'` in mig 098."*

Severity: Medium (comment-driven confusion; a future contributor might trust the comment, write code that depends on `status` being free-form text, hit `22P02` in prod).

### M-MP-4 — Tax-form-link route + dashboard button don't gate on `stripe_account_status === 'enabled'`
File: `apps/api/src/routes/partners.ts:1025-1043`, `apps/partner-dashboard/src/app/dashboard/payouts/page.tsx:292`

The audit task explicitly asks whether the "Open tax documents" button is gated on `enabled`. The API endpoint `/me/tax-form-link` only checks `if (!partner.stripe_account_id)` → 409 (line 1033). A partner whose Stripe Connect is `restricted`, `pending`, or `disabled` (but `stripe_account_id IS NOT NULL`) successfully gets a Stripe Express login link. The Express dashboard then renders Stripe's "complete onboarding" UX — not a real bug, but the UX promise the partner clicked into ("Open tax documents") doesn't match what they get.

The dashboard button at `payouts/page.tsx:292` `disabled={taxLinkLoading || !summary?.stripe_account_status}` disables only when `status` is **falsy** (i.e. `undefined`). For any status string — `'pending'`, `'restricted'`, `'rejected'` — the button is enabled. There's no positive `=== 'enabled'` check.

**Fix**: API gates on `partner.stripe_account_status === 'enabled'` → 409 with "complete Stripe onboarding first". Dashboard button mirrors the gate.

Severity: Medium (UX defect, partner sees a misleading "Open tax documents" CTA before they can actually have a 1099).

### M-MP-5 — `requirePartner` middleware doesn't gate on `partners.status='active'`
File: `apps/api/src/middleware/auth.ts:187`, `apps/api/src/routes/partners.ts:70-75`

`requirePartner` checks `req.user.isPartner` which derives from `users.is_partner` (mig 071's enum is `partners.status`). A partner whose row was just inserted (`status='pending'`, default per mig 071) still satisfies `is_partner=true` if the registration flow set both. But a partner whose admin marked them `status='rejected'` (and presumably set `is_active=false` via the mig 092 invariant) — what happens? `is_partner` on `users` would need to be flipped too, but no code does this. The route handler doesn't read `partners.status` at all.

The marketing page (`apps/marketing/src/pages/partners.astro:171`) says: *"Once approved, we walk you through Stripe's onboarding…"* — implies an approval gate. The code allows any `is_partner=true` user to call `/api/v1/partners/gifts` regardless of `partners.status`.

**Fix**: have `requirePartner` (or `getPartner`) reject `status IN ('pending', 'rejected')`. Until then, the rejection flow is admin-cosmetic.

Severity: Medium (commission-fraud surface — a rejected partner can keep selling gifts and earning commission).

### M-MP-6 — Marketing page hardcodes tier prices + commission rates that drift if env override is set
Files: `apps/api/src/services/partners.service.ts:66-79`, `apps/marketing/src/pages/partners.astro:19-58`

`TIER_PRICE_PER_GIFT_USD` is `JSON.parse(process.env.PARTNER_TIER_PRICING || '{"basic":99,"premium":149,"platinum":249}')` — operator-overridable. `TIER_COMMISSION_RATES` is a hardcoded `Record<string, number>` — NOT env-overridable. The marketing site hardcodes both: `pricePerGift: 99/149/249`, `commission: '10%'/'15%'/'20%'`.

If an operator overrides `PARTNER_TIER_PRICING` (the only knob env-exposed), the API charges different amounts than the marketing page advertises. There is no test that asserts marketing's hardcoded tier numbers === server's `TIER_PRICE_PER_GIFT_USD` defaults. There is also no fetcher in marketing that would pull `/api/v1/partners/tiers` at build time.

**Fix**: either (a) make `TIER_COMMISSION_RATES` env-configurable too and pull both at marketing build time from `/partners/tiers`; or (b) drop the env override and treat the constants as the single source of truth (everywhere — marketing, dashboard, API). The dashboard already imports `TIER_PRICE_PER_GIFT_USD` from `partners.service.ts` (`routes/partners.ts:594`); marketing is the lone laggard.

Severity: Medium (drift surface; operator pricing change → marketing lies to next prospect).

### M-MP-7 — `commission_rate` hardcoded twice (TIER_COMMISSION_RATES + PARTNER_TIERS) with no shared source
Files: `apps/api/src/services/partners.service.ts:75-79`, `apps/api/src/routes/partners.ts:596-639`

`partners.service.ts` exports `TIER_COMMISSION_RATES = { basic: 0.1, premium: 0.15, platinum: 0.2 }`. `routes/partners.ts` hardcodes the same numbers as `commission_rate: 0.10` / `0.15` / `0.20` in `PARTNER_TIERS` (used by `GET /partners/tiers`). Imports `TIER_PRICE_PER_GIFT_USD` from the service (correctly), but reinvents the commission rates inline.

A change to one file — e.g. bumping `platinum` to 0.22 in `partners.service.ts` — would silently keep advertising 0.20 on `GET /partners/tiers` and pay out 0.22 on actual gifts. The audit comment at `partners.service.ts:73-74` explicitly calls this out — *"Locked here and in the /partners/tiers route — diverging the two would let the dashboard advertise a rate the API never pays."* — but doesn't actually share the constant.

**Fix**: import `TIER_COMMISSION_RATES` from the service alongside `TIER_PRICE_PER_GIFT_USD` (the import is already there) and reference `commission_rate: TIER_COMMISSION_RATES.basic` in the `PARTNER_TIERS` array. Single source of truth, ~4-line change.

Severity: Medium (drift trap; the comment claims a guarantee the code doesn't enforce).

### M-MP-8 — Joi cap of `premiumMonths.max(12)` contradicts DB CHECK 1..120
Files: `apps/api/src/validators/partners.validator.ts:58`, `apps/api/src/db/migrations/070_phase8_drift_constraints.sql:73-75`

`createGiftSchema.premiumMonths = Joi.number().integer().min(1).max(12).optional()`. Mig 070 line 75 sets `chk_partner_gifts_premium_months_range CHECK (premium_months BETWEEN 1 AND 120)`. So the DB allows up to 10 years, the API caps at 1 year. Same in `updatePartnerSchema.defaultPremiumMonths.max(12)`. Either the audit's CHECK is over-permissive or the validator is artificially restrictive.

If a partner sets `default_premium_months=24` in the past (some legacy path) and then calls `createGift` without a `premiumMonths` override, the service falls back to `partner.default_premium_months` (line 549), bypassing the Joi cap, and writes 24 — within the CHECK so it succeeds. The partner is charged the same tier price but the homebuyer gets 24 months of premium. **Pricing arbitrage** if the legacy pre-Joi `defaultPremiumMonths` rows still exist.

**Fix**: tighten the CHECK to `BETWEEN 1 AND 12` (or whatever the marketing-promised max is), or raise the Joi cap if 120 is intentional. Don't leave the gap.

Severity: Medium (low likelihood, but pricing-arbitrage path; ALSO: same mismatch could let an admin SQL `UPDATE partners SET default_premium_months = 60 WHERE …` and the API silently honors it).

---

## Low

### L-MP-1 — `getEarningsHistory` uses `parseFloat` despite `getPartnerAnalytics` switching to integer cents
File: `apps/api/src/services/partners.service.ts:1273-1276`

`earnings: parseFloat(row.earnings) || 0` — same author wrote line 1240 explicitly warning against this exact pattern: *"S3-A: aggregate in integer cents and only convert to a display string at the response edge. parseFloat on DECIMAL would compound float drift at the 100-row scale (100 × $0.07 → $6.999999)."* The 12-row monthly aggregate is small enough that drift won't matter in practice, but the inconsistency is a foot-gun.

**Fix**: route through `decimalToCents` + `centsToDecimalString`.

Severity: Low (12-row sum, drift bounded).

### L-MP-2 — Stripe Connect `accountLinks.create` has no `idempotencyKey`
File: `apps/api/src/routes/partners.ts:717-722`

Onboarding link creation is non-idempotent. Probably correct on purpose (each button click should mint a fresh short-lived link), but worth noting because every other Stripe mutation in the file does pass a key. Stripe charges nothing for `accountLinks.create` so duplicate calls aren't a money issue.

Severity: Low (intentional, but contrast with the sibling calls is jarring).

### L-MP-3 — `clawbackCommissionForGift` partial-refund branch can compound on multiple distinct partial events
File: `apps/api/src/routes/webhooks.ts:81-151`

The `WHERE status NOT IN ('reversed', 'cancelled')` clause de-dupes a single replay (good). But the comment at line 685-687 explicitly notes: *"a different partial after a previous partial WILL produce another reversal row. That's correct: each partial gets its own ledger entry."* This is intended. However, the `proportion` for each partial is `amount_refunded / amount` — a CUMULATIVE Stripe value. Two consecutive partial refunds (each $5 of a $99 charge) produce events where the second has `amount_refunded=$10`, and the second event would clawback `proportion=10/99 ≈ 10.1%`. The first event already clawed `proportion=5/99 ≈ 5.05%`. **Cumulative clawback after both events: ~15.15%** of the original commission, vs the expected ~10.1%. The math double-counts the first partial.

To verify: if the partner's gift cost $100 and earned $10 commission, then a $5 refund (5%) and another $5 refund (5%):
- Event 1: amount_refunded=5, proportion=0.05, reversal=-$0.50
- Event 2: amount_refunded=10, proportion=0.10, reversal=-$1.00
- Total reversal: $1.50 (correct would be $1.00 = 10% of $10)

**Fix**: store `amount_refunded` (or the per-event delta) on the reversal row, and on subsequent partial events compute `delta_proportion = (event.amount_refunded - prior_total_refunded) / event.amount`. Or simpler: cancel the prior partial reversal and re-create a single proportional one.

Severity: Low (only triggers when Stripe sends >1 partial refund event for the same charge; partner LOSES commission, doesn't lose money for the platform — but does lose partner trust).

### L-MP-4 — `getCommissions` exposes `stripe_transfer_id` to the partner
File: `apps/api/src/services/partners.service.ts:1304-1316`

`SELECT c.* FROM partner_commissions c …` returns the raw `stripe_transfer_id` to the partner. The transfer id is the partner's own transfer, so they have a need-to-know — but it's the kind of identifier (`tr_…`) that, combined with a leaked Stripe key, can be used to query Stripe for adjacent metadata. The admin route correctly masks `stripe_account_id` per audit S2-P; consistency suggests masking transfer IDs in the partner's own response too (or at least redacting in mixed-audience contexts).

Severity: Low (defensible as-is; called out for consistency with the admin S2-P pattern).

### L-MP-5 — `proratedRefundCents` uses float multiplication
File: `apps/api/src/services/warranty-purchases.service.ts:16-28`

`Math.round(priceDollars * 100 * fraction)` — `priceDollars` arrives as `Number(existing.price)` (line 403), `fraction` is a JS number division. The util in `money.ts` (`commissionCents`) does the same conceptual operation (`Math.round(amountCents * rate)`) but with cents-first input, which is the audit's preferred path. For a $99 warranty refunding 50% the math is `99*100*0.5 = 4950` cents — exact. For weird inputs like `$99.99 * 0.333…` it's `99.99 * 100 * 0.333… = ~3330.0`-ish, rounded fine. Practical drift is negligible at $100-scale.

**Fix**: route through `dollarsToCents(priceDollars)` first, then `commissionCents`. Same outcome, consistent style.

Severity: Low (cosmetic; drift bounded by warranty price scale).

---

## Verified-correct (paranoia checks that pass)

- **Three-phase gift create**: Phase 1 reserves a `pending_payment` row in its own short tx. Phase 2 calls Stripe OUTSIDE any DB tx, idempotency-keyed `gift-<id>`. Phase 3 promotes + inserts commission in a fresh tx; on Phase-3 DB failure the code issues a refund (idempotency `refund-<id>`). On Phase-2 Stripe failure the pending row is flipped to `'expired'` (cleanup). On a process crash between Phase 1 commit and Phase 2 attempt, the row sits in `pending_payment` and the daily `expireUnactivatedPartnerGifts` cron eventually expires it (gift never charged, partner notified by absence of the gift in their list). The partner is never charged for a gift that doesn't exist. (`partners.service.ts:434-782`)

- **`claimWebhookEvent` race-safety**: explicit `BEGIN` + `SELECT … FOR UPDATE` on the existing row before the `INSERT … ON CONFLICT DO UPDATE`. Two concurrent deliveries serialize correctly: first call inserts (xmax=0), second call waits on the row lock, sees committed status, evaluates `attempts+1 >= MAX` against the just-bumped value. Returns `'claimed' | 'retry' | 'processed' | 'dead_letter'`. (`webhooks.ts:165-237`)

- **Commission clawback** preserves the original audit row: paid+transferred commissions never get UPDATEd; instead a sibling `'reversed'` row with negative amount + `reversal_of_commission_id` back-pointer is inserted. The mig 030b CHECK `chk_partner_commissions_reversal_shape` enforces (status='reversed' ⇒ reversal_of_commission_id IS NOT NULL AND amount <= 0). The mig 030b CHECK `chk_partner_commissions_paid_has_transfer` enforces (status='paid' ⇒ stripe_transfer_id IS NOT NULL). (`webhooks.ts:81-151`, `mig 030b`)

- **30-day auto-approve cron** correctly excludes rows with a reversal sibling via `NOT EXISTS (SELECT 1 FROM partner_commissions r WHERE r.reversal_of_commission_id = pc.id)` (index 095 covers the predicate). It also gates on `partners.stripe_account_status='enabled'` so unverified partners don't accumulate payable balances. A refund arriving on day 31 (just after auto-approve) hits the `else` branch in `clawbackCommissionForGift` and flips the (now `approved`) row to `'cancelled'` — money math nets correctly. (`apps/api/src/index.ts:136-169`)

- **`isEventInOrder` for RC events**: per-`(source, subject_id)` high-water UPSERT with `WHERE last_event_at <= EXCLUDED.last_event_at` correctly drops a stale `EXPIRATION` arriving after a fresher `RENEWAL`. The `subject_id` is the user UUID for RC, the payment_intent for Stripe disputes. (`webhooks.ts:280-298`, `1285-1293`)

- **RC `EXPIRATION` keeps premium when an active partner gift covers the user**: webhook handler queries `partner_gifts WHERE activated_user_id=$1 AND is_activated=TRUE AND status<>'expired' AND (expires_at IS NULL OR expires_at > NOW())`. (`webhooks.ts:1382-1396`) — Test at `webhooks.test.ts:318` codifies the behavior.

- **RC `TRANSFER` source-side demotion** mirrors the same gift-keeps-premium guard (`webhooks.ts:1502-1532`). Source loses premium ONLY if no active gift is covering them.

- **Stripe webhook signature verification** uses `stripe.webhooks.constructEvent` against the raw body (`req.body` is a `Buffer` because `app.ts:136-140` wires `express.raw({type:'application/json', limit:'1mb'})` BEFORE `express.json()`). Signature is verified BEFORE any DB work. `STRIPE_MAX_AGE_SEC=300s` replay window is correctly skipped on first-time delivery (Ch03-F044 fix at `webhooks.ts:355-371`).

- **RC webhook auth** uses `crypto.timingSafeEqual` against SHA-256 hashes (constant-time). `'REVENUECAT_WEBHOOK_SECRET'` not-configured is treated as 401 (not 503), so a probe can't distinguish "wrong" from "absent". (`webhooks.ts:1099-1127`)

- **`mig 097` CASCADE-allow on `warranty_claim_state_history`** correctly drops `DELETE` from the immutable trigger, leaves `UPDATE` blocked. CASCADE prunes from a deleted parent claim now succeed; a manual UPDATE still raises. The audit's invariant ("rows cannot be silently rewritten") is preserved.

- **`mig 098` adds `'cancelling'` enum value** before the runner ever executes the three-phase warranty cancel. `ALTER TYPE ADD VALUE` cannot run in a tx; the runner auto-detects the pattern (per CLAUDE.md Part 2) and runs out of band — verified that the file matches the runner's expectation (single `ALTER TYPE` with no surrounding `BEGIN`).

- **Stripe transfer in `/me/payouts` is idempotent**: each commission row gets its own transfer with `idempotencyKey: 'commission-pay-<id>'`. Two concurrent calls land on the same key; Stripe returns the same transfer; only the first DB UPDATE flips status (the second sees `WHERE status='approved'` and matches 0 rows, logged but doesn't double-pay). Same key + same destination + same amount = Stripe replays the prior result.

- **Activation-code race**: the pre-check is non-locking, the in-tx INSERT relies on the unique index `idx_partner_gifts_activation_code_hash`. Mig 086 dropped the redundant plaintext UNIQUE so only the hash index protects. The `23505` mapping at `partners.service.ts:587-606` correctly surfaces the rare collision as 409. The activation-code wipe at terminal transitions (activate / expire) clears the plaintext from the row but keeps the hash for forensic lookup.

- **Brute-force lockout on activation**: Redis-backed `gift:activate:attempts:<id>` counter + `gift:activate:lock:<id>` TTL key. `INCR` is atomic. Failure to reach Redis fails OPEN (allowed through) but the `SELECT … FOR UPDATE` in the transactional path still prevents concurrent duplicate activation. Code-level brute-force has a separate `gift:code:attempts:<normalized>` Redis key in the verify-code route.

- **`SELECT … FOR UPDATE` in `activateGift`** + the `WHERE activated_user_id IS NULL AND is_activated = FALSE` guarded UPDATE correctly handles two concurrent activate attempts: one wins with rowCount=1, the other sees rowCount=0 and 409s. (`partners.service.ts:1028-1043`)

- **`off_session: true`** is paired with an explicit `payment_method: paymentMethodId` resolved from `customer.invoice_settings.default_payment_method`. Without the explicit PM, `confirm: true` + `off_session: true` would fail with `payment_intent_unexpected_state`. (`partners.service.ts:641-670`)

- **`stripe@21.0.1` pin** matches CLAUDE.md's note about the v22 CJS-typing regression. `apiVersion: '2026-03-25.dahlia'` matches the Stripe SDK's current default. `maxNetworkRetries: 2` + `timeout: 15_000` correctly caps Stripe round-trips so the prior "Stripe-inside-BEGIN pinned a tx for 80s" failure mode is bounded. (`stripe-client.ts`)

- **`money.ts` `decimalToCents` / `centsToDecimalString`** correctly avoid the `19.99 * 100 = 1998.999…` float trap by splitting the integer + fraction halves and re-assembling in cents. `dollarsToCents` throws on malformed input (no silent 0). `commissionCents` rejects non-finite inputs.

- **`mig 087` BIGINT** correctly promotes both `webhook_events_id_seq AS bigint` and the column type. SERIAL → BIGSERIAL fixes the H-D5 audit finding; existing primary-key values are preserved.

---

## Out-of-scope-noticed

- **Account purge** is owned by another agent, but the warranty `commission_amount` column on `warranty_purchases` is `DECIMAL(10,2)` and gets populated only via the `data.commissionAmount || null` path (`warranty-purchases.service.ts:260`). No code path currently inserts a partner-attributed commission row with `reference_type='warranty_purchase'`, so the warranty-cancel `UPDATE partner_commissions SET status='cancelled' WHERE reference_type='warranty_purchase'` (line 474-481) is permanently dead. Either flesh out warranty-attribution (the `commissionAmount` field hints at it) or delete the dead branches.

- **Mobile** is owned by another agent, but the `premiumMonths.max(12)` Joi cap means the mobile (or any client) can't request a 24-month gift, while the DB allows up to 120. If the mobile UI ever exposes a "12+ months" picker, the 422 response will be confusing.

- **Dashboard** is owned by another agent, but the dashboard's payouts page reads `summary.stripe_account_status` and renders it as a status string. The five possible values (`unknown` / `pending` / `enabled` / `restricted` / `disabled` / `rejected`) need explicit rendering (no fallback to "unknown" → opaque). I didn't audit the rendering — Agent 3 should confirm.

- **Marketing** is owned by another agent. The hardcoded $99/$149/$249 + 10/15/20% values match the API defaults today. If pricing ever changes, follow M-MP-6 above to make this drift-proof.

---

## Summary

The money-flow code shows clear signs of careful audit work: every Stripe mutation is idempotency-keyed, the 3-phase gift create + 3-phase warranty cancel correctly interleave Stripe and DB, the commission clawback ledger preserves the original earning row, the auto-approve cron gates correctly on `stripe_account_status='enabled'` and refund-clawback siblings, and `claimWebhookEvent` is explicitly tx-wrapped to handle concurrent deliveries. The remaining issues cluster into four categories: (1) **unused money-utility regressions** (H-MP-2, L-MP-1, L-MP-5 — `money.ts` exists, several call sites went rogue back to float math); (2) **operational gaps** (H-MP-3 dead-letter has no alert, M-MP-2 no recovery for stuck `cancelling` rows); (3) **error-message UX** (H-MP-1 catches and rewrites non-Stripe AppErrors); and (4) **drift / hardcoded constants** (M-MP-6, M-MP-7, M-MP-8 — three places where the same numbers are hardcoded twice). H-MP-4 (`amount=0` divide-by-zero in clawback) is the corner case most worth a unit test before it appears in prod logs. Nothing here is a smoking gun for fund routing, but H-MP-3 is the kind of silent-failure path that explodes without warning the first time a bug ships in a webhook handler.
