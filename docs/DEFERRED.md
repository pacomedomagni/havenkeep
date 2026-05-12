# HavenKeep — Deferred / Not-Yet-Shipped

This is the parking lot for product surfaces that were once described in
[PRODUCT.md](./PRODUCT.md) as if shipped, but that the code does **not**
actually deliver — plus a few smaller scope cuts. Decisions recorded here so
the spec, marketing, and the codebase stop disagreeing.

PRODUCT.md describes only what is **actually built**. Anything in this file is
NOT in production and should not be implied by app copy, marketing, or the
partner agreement until it moves out of here.

| Status key | Meaning |
|---|---|
| `BACKLOG` | Wanted, not started, no committed date. |
| `SCOPE-CUT v1` | Built differently / smaller than the original spec wording; the spec wording was corrected to match the code. |

---

## 1. Extended-warranty marketplace + partner lifetime commission — `BACKLOG`

**What the spec used to claim:** users could quote + buy extended warranties
in-app for items whose manufacturer warranty was expiring; partners earned
"10–20% commission on every warranty their referred user buys, for the life
of the account."

**Reality in the code:** the marketplace doesn't exist. `warranty_purchases`
exists as a table and `WarrantyPurchasesService.createPurchase` accepts a
*client-supplied* `stripePaymentIntentId` (it doesn't charge anything), writes
the row with `commission_amount` / `commission_rate` left NULL, and references
a "partner-attribution job" that was never written. No `partner_commissions`
row is ever created for a warranty purchase.

**Decision:** defer the whole surface. PRODUCT.md / §4.2 / §5.2 / marketing /
the partner agreement now describe partner revenue as **commission on the
gifts a partner sends**, full stop — no "lifetime commission on warranty
sales." When the marketplace is built it needs: a real Stripe charge flow, a
warranty-provider integration, the compliance lift (selling insurance-adjacent
products), and the attribution job that links a purchase to the referring
partner and writes the commission ledger row.

**What stays in PRODUCT.md:** the gift program (3-phase flow, Connect
onboarding, payout transfers, 1099-NEC, refund clawback) — all of that is real
and shipped.

---

## 2. "Share Claim" — bundling documents into a single PDF — `SCOPE-CUT v1`

**What the spec used to claim:** the Share Claim sheet "bundles every document
attached to an item into a single PDF for forwarding to the manufacturer."

**Reality in the code:** `pdf_export_service.dart` generates a client-side PDF
with the item's details + a section that **lists the attached documents by
filename**. It does not download and embed the receipt/warranty-card images or
PDFs into the output.

**Decision:** correct the wording — the Share Claim sheet produces a *claim
summary PDF*; the user attaches their actual documents (which they can pull
from the item's Documents tab) alongside it. Embedding the binaries into one
PDF (download from MinIO → rasterise/merge) is a `BACKLOG` enhancement.

---

## 3. Maintenance per-item customization & snooze — server-side persistence — `SCOPE-CUT v1`

**What the spec implied:** "Persisted in `MaintenanceCustomization`" (reads as
server-side, syncs across devices).

**Reality in the code:** `maintenance_customization_service.dart` and
`maintenance_snooze_service.dart` persist to `SharedPreferences` only — on the
device. There is no `maintenance_customizations` table or route. A reinstall or
a second device starts from the catalog defaults.

**Decision:** ship as-is for v1; PRODUCT.md §3.4 now says per-item overrides /
snoozes are stored **on the device**. Server-side persistence (a table + CRUD
routes + a sync path) is `BACKLOG`.

---

## 4. PDF / CSV export — server-side premium gating — `SCOPE-CUT v1`

**Reality:** export is generated **client-side from the user's own item data**
(already returned by `GET /api/v1/items`), so there is no server endpoint to
gate. A determined free user could export.

**Decision:** the export *buttons* are gated client-side (premium-only UI). The
spec's "Premium unlock" framing stands, with that caveat noted. A
server-rendered export (which *could* be gated server-side) is `BACKLOG` and
not planned.

---

## 5. Multi-milestone reminder cascade (90/60/30/14/7) — `BACKLOG`

Already flagged in PRODUCT.md §3.2 — keeping it here too for completeness. The
single per-item reminder at `first_reminder_days` is shipped; the multi-stage
cascade is not. When it ships it needs per-user milestone toggles + a schema
change.

---

## 6. Platinum longer-grant differentiator — `BACKLOG`

All three partner tiers grant the same 1–12-month premium window today; the
tier difference is per-gift price + commission rate only. A Platinum-only
longer-grant option would need a validator bump + a UI option. Already noted in
PRODUCT.md §5.2.

---

## 7. Insurance-report export / policy-provider integration — `BACKLOG`

HavenKeep stores receipts + photos but does not generate insurance-specific
reports or integrate with policy providers. Roadmap candidate, not started.
Already noted in PRODUCT.md §10.

---

## 8. Audit-chain ↔ GDPR-erasure contradiction — `NEEDS DESIGN CALL`

**The problem.** `audit_logs.user_id` is `REFERENCES users(id) ON DELETE SET
NULL` (mig 004) **and** `user_id::text` is part of the hashed payload that
mig 065/101's BEFORE INSERT trigger commits to. The two facts collide when
the daily soft-delete-purge cron runs `DELETE FROM users WHERE id = $1`
(`account-purge.service.ts:128`): Postgres fires a row-level **UPDATE** on
every `audit_logs` row that referenced that user, setting `user_id` to NULL.
That update has two possible outcomes, both bad:

- **If the API role is correctly NOT a member of `audit_cleaner`** (the
  intended security configuration — the audit deep-dive's question #3):
  the `audit_logs_immutable` BEFORE UPDATE trigger raises `RAISE EXCEPTION
  'audit_logs is append-only'` → the cascade fails → the `DELETE FROM users`
  rolls back → **no user with any audit history can be hard-deleted.** The
  cron catches it per-user (`account-purge.service.ts:135`) and logs, so it
  doesn't crash, but the GDPR-erasure ledger silently never completes. The
  30-day cooling-off window expires, the user "stays deleted" in soft-delete
  state forever.
- **If the immutable trigger is bypassable for the API role** (the bad
  case): the cascade UPDATE succeeds → nulling `user_id` on each row
  changes its hashed payload → its stored `this_hash` no longer recomputes
  → `verify_audit_chain()` flags every such row → the daily verifier emails
  "INTEGRITY FAILURE — possible tampering" after every purge. Self-inflicted
  false alarms; the chain is broken in a real sense (the rows no longer
  cryptographically commit to their original content).

**Verify on staging before launch:** check `account-purge.service.ts`'s
"Soft-delete purge failed" log line over the last 30 days — if every
soft-deleted user with audit history is failing to hard-delete, that
confirms the first failure mode is live.

**Fix options** (pick one before relying on either auditability or
GDPR-erasure end-to-end):

1. **Stop hashing `user_id`.** Drop it from the payload and change the FK
   to `ON DELETE NO ACTION` (so the column stays stable forever — dangling
   IDs are fine, the denormalized `user_email_at_event` columns already
   preserve "who"). Requires a re-baselining migration that recomputes
   `this_hash` for every existing row using the new payload format. Stops
   the false-alarm path; lets purge succeed.
2. **Keep hashing `user_id`, switch the FK to `NO ACTION`.** Same as (1)
   but without the payload change — dangling IDs that hash stably. The
   audit row keeps the original `user_id` value forever (a string, not
   FK-resolvable), so a forensic query can still link by ID. Smaller
   migration; doesn't require chain re-baselining.
3. **Whitelist purge in the immutable trigger.** Have the trigger allow
   UPDATEs that *only* set `user_id` to NULL (any other column change still
   raises). Doesn't help the chain-break problem — only the purge-fails
   problem. Probably worse than (1)/(2).

(2) is the minimum viable fix and the recommendation. Until one is shipped,
the "even an admin can't tamper" claim and the "we can prove we erased the
user" GDPR claim are in conflict.
