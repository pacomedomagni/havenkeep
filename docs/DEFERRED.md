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

## 1. Extended-warranty marketplace — `BACKLOG`

**What the spec used to claim:** users could quote + buy extended warranties
in-app for items whose manufacturer warranty was expiring.

**Reality in the code:** the marketplace doesn't exist. `warranty_purchases`
exists as a table and `WarrantyPurchasesService.createPurchase` accepts a
*client-supplied* `stripePaymentIntentId` (it doesn't charge anything) and
writes the row with `commission_amount` / `commission_rate` left NULL.
Mobile always passes null; the field is preserved as a nullable artefact.

**Decision:** defer the whole surface. PRODUCT.md no longer claims the
marketplace exists. When it's built it needs a real charge flow, a
warranty-provider integration, and the compliance lift (selling
insurance-adjacent products is a regulated activity).

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

## 6. Per-partner gift caps (abuse mitigation) — `BACKLOG`

The partner program is currently free with no per-account rate limits.
Re-creating a HavenKeep account to extend the gift is irrational at the
$24/yr price point (hours of data re-entry to save $24), so abuse pressure
is low — but a per-partner monthly gift cap that scales with proven
activity would shut down even the bulk-spam scenario. Not started.

---

## 7. Insurance-report export / policy-provider integration — `BACKLOG`

HavenKeep stores receipts + photos but does not generate insurance-specific
reports or integrate with policy providers. Roadmap candidate, not started.
Already noted in PRODUCT.md §10.

