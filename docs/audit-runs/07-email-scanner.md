# Audit 07 — Email Scanner + Receipt OCR

**Scope:** OAuth code-grant pipeline (Gmail/Outlook), AES-256-GCM refresh token storage,
DKIM gate, OpenAI budget cap, trusted-retailer allowlist, auto-import,
review queue, receipt OCR, barcode lookup, mobile-side OAuth flow.

**Files audited:**
- `apps/api/src/services/email-scanner.service.ts` (1725 lines)
- `apps/api/src/routes/email-scanner.ts` (236 lines)
- `apps/api/src/utils/oauth-encryption.ts` (102 lines)
- `apps/api/src/routes/receipts.ts` (394 lines)
- `apps/api/src/routes/barcode.ts` (144 lines)
- `apps/api/src/db/migrations/{002,038,039,051,067,070,088}*.sql`
- `apps/mobile/lib/core/services/email_oauth_service.dart` (150 lines)
- `apps/mobile/lib/features/email_scanner/email_scanner_screen.dart` (1135 lines)
- `apps/mobile/lib/core/services/email_scanner_repository.dart` (277 lines)
- `apps/mobile/lib/core/providers/email_scanner_provider.dart` (182 lines)

**Note:** there is no dedicated `receipt-scan.service.ts` or `barcode-lookup.service.ts`;
both surfaces live entirely inside their route files (`receipts.ts`, `barcode.ts`).

---

## Critical findings (security / data loss / cost runaway)

### C1. Outlook scans bypass the OpenAI per-user daily budget cap entirely
**Severity: CRITICAL (cost runaway).**
[apps/api/src/services/email-scanner.service.ts:1036](../../apps/api/src/services/email-scanner.service.ts#L1036)

`scanGmail` correctly threads `userId` into `extractReceiptData(emailData, signal, userId)`
([line 946](../../apps/api/src/services/email-scanner.service.ts#L946)) and that triggers
`recordScannerUsage` at line 1268, which writes to `openai_usage` so the daily cap reflects
the spend. `scanOutlook` does NOT pass `userId`:

```ts
const extracted = await this.extractReceiptData(emailData, signal);  // no userId
```

Inside `extractReceiptData` the recording is gated on `if (userId) { ... recordScannerUsage(...) }`
([line 1268](../../apps/api/src/services/email-scanner.service.ts#L1268)), so Outlook traffic
never touches `openai_usage`. Two consequences:

1. **`OPENAI_DAILY_CAP_MICROS` is unenforced for Outlook.** The pre-scan check at
   [line 747](../../apps/api/src/services/email-scanner.service.ts#L747) reads from
   the `openai_user_daily_cost` view, which only sees Gmail rows. An Outlook user can
   run unlimited scans/day.
2. **Cost attribution is broken** — Outlook scans are invisible to ops dashboards built
   on the same view.

Fix: pass `userId` into the Outlook call and remove the `if (userId)` gate (or assert).

### C2. Budget cap is checked only ONCE per scan, but a single scan burns up to ~500 OpenAI calls
**Severity: CRITICAL (cost runaway).**
[apps/api/src/services/email-scanner.service.ts:747](../../apps/api/src/services/email-scanner.service.ts#L747)

`withinOpenAIBudget` is called exactly once at the top of `performScan`. After that the
inner loop iterates `TRUSTED_RETAILER_DOMAINS` (10 entries) × up to 50 messages per query
= **500 OpenAI calls per scan**, none of which re-check the cap. A user who is at 99 % of
the cap when the scan starts gets a free 500-call ride.

Fix: re-check `withinOpenAIBudget` inside the per-message loop in both `scanGmail` and
`scanOutlook`. Bail out cleanly (mark scan failed with the same "budget exhausted" message)
when the cap is reached mid-scan.

### C3. Refresh-token rotation is silently dropped (Outlook breaks within ~24h)
**Severity: CRITICAL (data loss / silent breakage).**
[apps/api/src/services/email-scanner.service.ts:460-540](../../apps/api/src/services/email-scanner.service.ts#L460)

`refreshAccessTokenForIntegration` types the response as
`{ access_token?: string; expires_in?: number }`
([line 469](../../apps/api/src/services/email-scanner.service.ts#L469))
and never reads `refresh_token` from the response. Microsoft Identity Platform issues a
**rotated** `refresh_token` on every refresh-token grant
([Microsoft docs](https://learn.microsoft.com/en-us/azure/active-directory/develop/refresh-tokens))
and the old one stops working when the new one is issued (or after a short overlap window).
Google may rotate as well in some cases (e.g. when the user revokes & re-grants).

The UPDATE on [line 528](../../apps/api/src/services/email-scanner.service.ts#L528) only writes
the new `access_token_*`, leaving `refresh_token_*` stale. After the first refresh, the next
refresh attempt will fail with `invalid_grant`. The user will see the integration silently die.

Fix: read `refresh_token` from the JSON response and, when present, re-encrypt and persist
alongside the rotated access token in the same UPDATE.

### C4. Revoke does NOT call the provider's revocation endpoint
**Severity: CRITICAL (token leak after disconnect).**
[apps/api/src/services/email-scanner.service.ts:316](../../apps/api/src/services/email-scanner.service.ts#L316)

`revokeIntegration` only NULLs the access-token cache and stamps `revoked_at` locally.
It never POSTs to `https://oauth2.googleapis.com/revoke` or calls
`https://login.microsoftonline.com/.../oauth2/v2.0/logout`. Practical impact:

- A user who clicks "Disconnect Gmail" sees the integration removed from the HavenKeep UI,
  but the **OAuth grant remains active server-side at Google** and the long-lived refresh
  token (still valid for ~6 months barring inactivity) will stay redeemable until the user
  manually revokes it from `myaccount.google.com/permissions`.
- The CLAUDE.md privacy posture and the in-app "We … revoke the OAuth tokens on the server"
  microcopy at [email_scanner_screen.dart:703](../../apps/mobile/lib/features/email_scanner/email_scanner_screen.dart#L703)
  is materially false.

Fix: before clearing the row, decrypt the refresh token and POST it to the provider's
revocation endpoint. Tolerate 4xx (already revoked, expired) silently; 5xx → surface to the
user. The dashboard UI claim must match server behaviour.

### C5. Refresh token is decrypted on every refresh AND on every cache-miss read — defense-in-depth issue
**Severity: HIGH** (close to critical given how often it happens).
[apps/api/src/services/email-scanner.service.ts:463](../../apps/api/src/services/email-scanner.service.ts#L463)
+ [line 583](../../apps/api/src/services/email-scanner.service.ts#L583)

The `decryptToken` round-trip is fast, but `getAccessToken` decrypts the refresh token
into a `String` even when the access-token cache is hot (it falls through to
`refreshAccessTokenForIntegration` only when expired). Looking at the code path: the
fast path at [line 575-580](../../apps/api/src/services/email-scanner.service.ts#L575)
returns the *access* token directly without touching the refresh token, so the comment
in the audit checklist about "decrypt + cache" is satisfied here. **Verified-clean.**

### C6. Receipt-scan idempotency hash uses pre-validation mimeType corner case
**Severity: LOW** (verified-clean, kept for the record).
[apps/api/src/routes/receipts.ts:183-188](../../apps/api/src/routes/receipts.ts#L183)

The hash is `sha256(imageBuffer + mimeType)`. The `mimeType` value used is the post-magic-bytes-validation
value (line 167 may have rewritten it before the hash on line 183). This is correct for replay
semantics — a re-tap with the same bytes always hashes to the same value regardless of which
`mimeType` the client claimed.

### C7. OAuth code-grant exchange has no HTTP timeout
**Severity: HIGH (DoS / scan-worker stall).**
[apps/api/src/services/email-scanner.service.ts:368, 419, 483, 506, 642, 656](../../apps/api/src/services/email-scanner.service.ts#L368)

Six places use `fetch('https://oauth2.googleapis.com/token', ...)` /
`fetch('https://login.microsoftonline.com/.../token', ...)` /
`fetch('https://www.googleapis.com/oauth2/v3/userinfo', ...)` /
`fetch('https://graph.microsoft.com/v1.0/me', ...)` with **no AbortController and no signal**.
Node's `fetch` has no default timeout, so a hung Google/Microsoft endpoint blocks the
request handler indefinitely. The Outlook *scan* uses axios with `HTTP_TIMEOUT_MS = 30s`
(line 1004), and `extractReceiptData` does too (line 1230) — but the OAuth-token endpoints
that gate the rest of the scan do not.

Fix: wrap each of those `fetch` calls in `AbortController` + `setTimeout` (matching
`HTTP_TIMEOUT_MS = 30_000`). Pattern is already used in routes/receipts.ts:227.

### C8. Server-side state validation does not exist — it's mobile-only
**Severity: HIGH (downgrade-attack vector).**
[apps/api/src/routes/email-scanner.ts:54-68](../../apps/api/src/routes/email-scanner.ts#L54)

The OAuth `state` parameter is minted, attached, and validated entirely on the mobile client
([email_oauth_service.dart:39-43](../../apps/mobile/lib/core/services/email_oauth_service.dart#L39)).
The server's `initiateScanSchema` does not even accept a `state` field — the API trusts that
the mobile client correctly enforced state matching. Implications:

- A malicious client (rooted Android, custom rebuild, native auth flow swapped out) can skip
  state validation and send any auth code to the server. The auth code is still bound to the
  registered redirect_uri at the provider, so the blast radius is limited, but it does mean
  the server has zero CSRF defense if the mobile-side check is bypassed.
- A web client (none today, but staging.havenkeep.app/oauth-callback is in the allowlist for
  future use) could land an attacker-supplied auth code via a forged state if the future web
  flow trusted the server.

Fix: have the API mint `state` (sign-with-HMAC over user_id + timestamp), echo it in a
short-TTL Redis key, and require the client to round-trip it. The mobile-only state check
is appropriate for native apps where the in-process WebAuth flow guarantees same-process
return, but the *server* should still reject auth codes that were not paired with a
server-minted state if/when the web flow goes live.

### C9. PII leakage to OpenAI is partly mitigated, but the body is sent verbatim
**Severity: MEDIUM (privacy posture / contractual risk).**
[apps/api/src/services/email-scanner.service.ts:18-26, 1216](../../apps/api/src/services/email-scanner.service.ts#L18)

`maskPII` redacts CC numbers, SSNs, and phone numbers from the body before the OpenAI call.
That's solid. But the email body is otherwise **sent verbatim** (sliced to 4000 chars):
addresses, recipient names, order line items, etc. flow into OpenAI's prompt. Things to verify:

- The OpenAI org's data-retention setting must opt out of training (default is 30-day retention,
  no training on API traffic, but verify the org-level setting at platform.openai.com).
- The privacy policy at /legal/privacy must disclose this transmission. The
  [_PrivacyCard at email_scanner_screen.dart:388](../../apps/mobile/lib/features/email_scanner/email_scanner_screen.dart#L388)
  ("We never read personal or unrelated messages") is **misleading** — the email body
  is sent to OpenAI verbatim, and the user never sees what was sent.

Recommended: add a single line to the in-app privacy prime ("Receipt content from trusted
retailers is sent to OpenAI for parsing and not retained for training.") and make the privacy
policy match.

### C10. Authentication-Results parser is not robust to header injection
**Severity: HIGH (DKIM gate is the only auto-import guardrail beyond the trusted-domain list).**
[apps/api/src/services/email-scanner.service.ts:1101-1104](../../apps/api/src/services/email-scanner.service.ts#L1101)

```ts
private static dkimPassed(authResults: string | undefined | null): boolean {
  if (!authResults) return false;
  return /\bdkim=pass\b/i.test(authResults);
}
```

Concerns:

1. **Multiple Authentication-Results headers.** Real-world mail commonly has 2-3 (one from each
   hop). [parseGmailMessage line 1073](../../apps/api/src/services/email-scanner.service.ts#L1073)
   uses `headers.find((h) => h.name === 'Authentication-Results')`, which returns only the
   FIRST match. The first hop may not be Gmail's own — an attacker who injects an
   `Authentication-Results: foo.com; dkim=pass` header at the beginning of the message can
   defeat the gate. Gmail's own header (the only trustworthy one) is identified by
   `mx.google.com` as the authserv-id, but the parser doesn't anchor to it.
2. **Folded headers.** RFC 5322 allows headers to fold across lines with leading whitespace.
   The Gmail API decodes them already, but if the API ever switches to raw RFC 822, folding
   would break the regex.
3. **Multiple `dkim=` results in one header.** RFC 8601 allows
   `dkim=fail (alpha) header.i=@a.com; dkim=pass header.i=@b.com` — the regex will match
   the second and report "pass" even though the *signing* domain matched the wrong identity.
4. **No `header.i=` / `header.from=` cross-check.** A trusted-domain `From: amazon.com`
   plus a `dkim=pass header.i=@anyrandom.com` is currently **AUTO-IMPORTED**. The DKIM signing
   identity must align with the From-domain (DMARC alignment) or this is just security theater.
5. **No SPF / DMARC defense in depth.** Auto-import gates only on DKIM. Best practice is
   `dkim=pass AND (dmarc=pass OR spf=pass)` AND `header.from` aligns with DKIM `header.i=`.

Fix: require Gmail's own `mx.google.com` Authentication-Results, parse `dkim=pass header.i=@<domain>`
where `<domain>` matches the trusted-domain set, AND require `dmarc=pass`. Anything else
falls to the review queue.

---

## High-severity findings

### H1. The `redirectUriAllowed` check uses prefix-startsWith, which is path-traversable for HTTPS prefixes
**Severity: HIGH.**
[apps/api/src/routes/email-scanner.ts:48](../../apps/api/src/routes/email-scanner.ts#L48)

```ts
if (!OAUTH_REDIRECT_URI_PREFIXES.some((prefix) => value === prefix || value.startsWith(prefix)))
```

For prefix `https://staging.havenkeep.app/oauth-callback`:
- Allowed (correct): `https://staging.havenkeep.app/oauth-callback?next=/foo`
- **Allowed (wrong)**: `https://staging.havenkeep.app/oauth-callback.attacker.com/abc`

The custom-scheme prefix `havenkeep://oauth-callback` is similarly vulnerable in theory, though
practical exploit is gated by the provider rejecting any redirect_uri that doesn't match a
registered one. This is defense-in-depth; the provider is the primary check, but the API
should not be the second-weakest link.

Fix: parse `value` with `new URL(value)`, verify `url.protocol + '//' + url.host + url.pathname`
matches one of the allowed bases exactly (or starts with `<base>?` / `<base>#`).

### H2. Gmail/Outlook scope downgrade is checked at *exchange* time but never on subsequent scans
**Severity: HIGH (scope drift).**
[apps/api/src/services/email-scanner.service.ts:675](../../apps/api/src/services/email-scanner.service.ts#L675)

`assertGrantedScope` runs only inside `initiateScan`, against the freshly returned
`token_set.scope`. If the user later revokes the read scope at Google ("Manage third-party access")
but doesn't disconnect from HavenKeep, the next scheduled scan (via `getAccessToken` →
`refreshAccessTokenForIntegration`) will silently get an access token that 401s on the first
list call. The error path at [line 489](../../apps/api/src/services/email-scanner.service.ts#L489)
just throws a generic "Failed to refresh Google access token" — neither the user nor ops
sees that the scope was downgraded.

Fix: in `refreshAccessTokenForIntegration`, parse the response `scope` field and re-run
`assertGrantedScope` on it. On scope shortfall: stamp `revoked_at` on the integration row and
return a structured error the mobile UI can render as "re-connect Gmail to continue scanning."

### H3. The 5-minute scan timeout aborts but never UPDATEs the scan row to 'failed' on the success path
**Severity: HIGH (UI hang) — actually verified-clean, kept for the record.**
[apps/api/src/services/email-scanner.service.ts:289-306](../../apps/api/src/services/email-scanner.service.ts#L289)

`Promise.race` resolves to the success branch when `performScan` finishes; the timeout
promise rejects 5 minutes later but its rejection is swallowed by `.catch`. The `.catch` only
runs if scanPromise lost the race. **Verified-clean**: timer is cleared in `.finally`, status
flips to 'completed' inside `performScan`. Audit-comment C11 is correctly handled.

### H4. `email_scanner_review_queue` has no cleanup policy
**Severity: HIGH (unbounded growth).**
[apps/api/src/db/migrations/039_email_scanner_review_queue.sql](../../apps/api/src/db/migrations/039_email_scanner_review_queue.sql),
[apps/api/src/index.ts:342-357](../../apps/api/src/index.ts#L342)

`email_scanner_seen_messages` has a 90-day prune in the daily cleanup sweep at index.ts:347.
`email_scanner_review_queue` has **no cleanup at all**. The API at line 1636 limits the
list query to 200 rows, but the table grows unbounded. A user who never reviews lets the
table grow forever; a poisoned scan-source could grow it fast. The migration does include
`idx_email_review_user_state` so list queries stay fast, but storage and dump-size grow.

Fix: prune `state IN ('approved', 'rejected') AND reviewed_at < NOW() - INTERVAL '30 days'`
and `state = 'pending' AND created_at < NOW() - INTERVAL '180 days'` in the daily sweep.
Surface a "X items pending review for >90 days" warning in user analytics.

### H5. `cancelScan` only flips DB status — the in-process scan keeps running and burning OpenAI calls
**Severity: HIGH (cost / cancel-trust gap).**
[apps/api/src/services/email-scanner.service.ts:1530-1557](../../apps/api/src/services/email-scanner.service.ts#L1530)
+ [line 297](../../apps/api/src/services/email-scanner.service.ts#L297)

The comment on line 1525 admits this: *"The background performScan task itself can keep
running"*. The `AbortController` for the scan is held in a closure inside `initiateScan`
(line 272) and never exposed to `cancelScan`. So:

1. User taps "Cancel scan."
2. DB row flips to 'failed' with "Cancelled by user."
3. The background loop keeps fetching messages and calling OpenAI for up to 5 more minutes.
4. Each call burns budget against the *cancelled* scan id; the
   `UPDATE … WHERE id = $1 AND status != 'completed'` guard at line 297 prevents a status
   regression but does NOT prevent the OpenAI calls.

Fix: keep an in-memory map `Map<scanId, AbortController>` keyed at `initiateScan` time;
`cancelScan` looks up the entry and calls `.abort()`. The existing `signal?.aborted` checks in
`scanGmail` (line 906) and `scanOutlook` (line 1010) will then short-circuit the loop.

### H6. Outlook's `internetMessageHeaders` is not requested, so DKIM is permanently unknown for Outlook
**Severity: HIGH (Outlook auto-import is permanently dead).**
[apps/api/src/services/email-scanner.service.ts:1001](../../apps/api/src/services/email-scanner.service.ts#L1001)
+ [line 1036](../../apps/api/src/services/email-scanner.service.ts#L1036)

The `$select` clause asks for `subject,from,receivedDateTime,body`. It does NOT ask for
`internetMessageHeaders`, so the Outlook receipt flow has no Authentication-Results to
parse. The `extractReceiptData` call doesn't even thread the headers through, and
`extracted.dkimPassed` is never set on Outlook receipts. Result: every Outlook receipt
ends up in the review queue regardless of trust + confidence. If the design says "trusted
retailers + DKIM auto-import" applies to both providers, Outlook is broken.

Fix: add `internetMessageHeaders` to `$select` (or fetch with a separate
`/messages/{id}?$expand=internetMessageHeaders` call), parse the Authentication-Results
header the same way Gmail does, and surface `dkimPassed` to the auto-import gate.

### H7. `extractDomain` falls back to second-level for ANY domain including sub-domain spoofs
**Severity: HIGH (spoof-via-subdomain).**
[apps/api/src/services/email-scanner.service.ts:162-177](../../apps/api/src/services/email-scanner.service.ts#L162)

```ts
const parts = domain.split('.');
if (parts.length >= 2) {
  return parts.slice(-2).join('.');
}
```

So:
- `receipts@amazon.com` → `amazon.com` ✓
- `receipts@amazon.com.attacker.example` → `attacker.example` (correct; not in trust list, OK)
- `receipts@order.amazon.com` → `amazon.com` ✓
- `receipts@amazon.co.uk` → `co.uk` ✗ (the public suffix list says `.co.uk` is the eTLD, the registrable
  is `amazon.co.uk`). Trust list doesn't include amazon.co.uk so practically not exploitable today,
  but the heuristic is wrong.
- `receipts@amazon.co` → `amazon.co` ✓

The note at [line 170](../../apps/api/src/services/email-scanner.service.ts#L170)
("coarse heuristic — fine for retailers in TRUSTED_RETAILER_DOMAINS") is correct as long as the
allowlist stays US-only. If/when international retailers join the list (Amazon UK, Best Buy
Canada, etc.), this needs the public-suffix-list lookup.

Fix (preventive): use `psl` package or `tldts` to extract the registrable domain. Low priority
until the trust list expands beyond .com.

### H8. `extractReceiptData` swallows OpenAI errors silently when the body is malformed
**Severity: HIGH (data loss — receipt that failed extraction is lost).**
[apps/api/src/services/email-scanner.service.ts:1280-1284](../../apps/api/src/services/email-scanner.service.ts#L1280)

```ts
try {
  extracted = JSON.parse(response.data.choices[0].message.content);
} catch (parseError) {
  logger.warn({ parseError, subject: emailData.subject }, 'Failed to parse AI response as JSON');
  return null;
}
```

A `null` return drops the receipt entirely. It does NOT enqueue to the review queue with a
"parse failure — please confirm" marker. Combined with the budget burn (the OpenAI call
already cost the user 2-3 ¢) this is a silent data loss path: the user paid for the call
and got nothing.

Fix: park a low-confidence (`confidence: 0.0`) row in the review queue with the original
subject + sender + a `parse_failed: true` flag, so the user can choose to re-scan or import
manually.

---

## Medium-severity findings

### M1. `createItemFromReceipt` on the auto-create path does not set `email_subject` / receipt provenance
**Severity: MEDIUM.**
[apps/api/src/services/email-scanner.service.ts:1490-1515](../../apps/api/src/services/email-scanner.service.ts#L1490)

The `notes` column gets `Imported from email: ${receipt.emailSubject}`. Good. But there's no
column linking the item back to the source `email_scan_id` or the source-message provider id.
If the user later asks "where did this come from?", the only signal is the notes string.

Fix: add `source_scan_id UUID NULL REFERENCES email_scans(id)` (and corresponding migration)
and persist it on insert. Powers the "imported from this scan" UX in scan history.

### M2. `category` is double-evaluated — receipt.category is read, then `receipt.category || 'other'` is re-evaluated
**Severity: LOW (cosmetic).**
[apps/api/src/services/email-scanner.service.ts:1480, 1505](../../apps/api/src/services/email-scanner.service.ts#L1480)

`const category = receipt.category || 'other'` at line 1480 is used to look up
`category_defaults`, but the `INSERT` at line 1505 re-evaluates `receipt.category || 'other'`
instead of reusing `category`. Functionally identical (both branches OR with `'other'`), but
brittle if someone changes one and not the other.

Fix: use `category` consistently in the INSERT params.

### M3. The auto-create path does NOT check the per-user free-plan item cap inside the same SELECT
**Severity: MEDIUM (race window between count and insert).**
[apps/api/src/services/email-scanner.service.ts:1443-1458](../../apps/api/src/services/email-scanner.service.ts#L1443)

`SELECT plan FROM users … FOR UPDATE` then `SELECT COUNT(*) FROM items` then `INSERT INTO items`.
The `FOR UPDATE` on the user row prevents two scans from racing — good — but a separate
write path (manual add via items.ts) doesn't take the same FOR UPDATE on `users`, so a
concurrent manual add + scan auto-create can both observe count=999 and both insert.

Fix: either (a) use a partial unique index that caps `(user_id WHERE NOT is_archived)` rows
at the limit (impossible without trigger), or (b) refactor manual add to also take
`FOR UPDATE` on the users row. A trigger-based count check is the cleanest answer.

### M4. `confidence` extraction quietly clamps even when the model returns -Infinity / NaN
**Severity: LOW.**
[apps/api/src/services/email-scanner.service.ts:1290-1292](../../apps/api/src/services/email-scanner.service.ts#L1290)

`Math.max(0, Math.min(1, extracted.confidence))` works for finite numbers but
`Math.min(1, NaN) === NaN`, then `Math.max(0, NaN) === NaN`, which then passes `typeof === 'number'`
(NaN is a number). Downstream the auto-create gate `confidence >= 0.85` is `false` for NaN, so
the practical effect is the receipt goes to review — safe, but not by design.

Fix: `Number.isFinite(extracted.confidence) ? Math.max(0, Math.min(1, extracted.confidence)) : 0`.

### M5. The mobile dialog's `dialogContextCompleter` can complete twice if `showDialog` rebuilds
**Severity: LOW (verified-clean — kept for the record).**
[apps/mobile/lib/features/email_scanner/email_scanner_screen.dart:242-255](../../apps/mobile/lib/features/email_scanner/email_scanner_screen.dart#L242)

Wrapped with `if (!dialogContextCompleter.isCompleted)` so a Hot Reload-induced rebuild does not
double-complete the Completer. Verified-clean.

### M6. The Confidence threshold `0.85` is hard-coded
**Severity: LOW.**
[apps/api/src/services/email-scanner.service.ts:100](../../apps/api/src/services/email-scanner.service.ts#L100)

Not env-configurable. Tightening or relaxing requires a code change + redeploy. For an MVP
this is fine, but worth flagging for the audit ledger:
`AUTO_CREATE_CONFIDENCE_THRESHOLD = Number(process.env.EMAIL_AUTO_IMPORT_CONFIDENCE ?? 0.85)`.

### M7. The trusted retailer list is hard-coded
**Severity: LOW.**
[apps/api/src/services/email-scanner.service.ts:86-97](../../apps/api/src/services/email-scanner.service.ts#L86)

10 US retailers, hard-coded. Adding Best Buy Canada / Argos / John Lewis requires a deploy.
For an MVP this is intentional (per the comment "intentionally tight … keep additions deliberate"),
but consider promoting to `category_defaults`-style admin-managed table when international
launch happens.

### M8. `recordScannerUsage` duplicates the cost-rate constants from `routes/receipts.ts`
**Severity: LOW (drift risk).**
[apps/api/src/services/email-scanner.service.ts:1142-1143](../../apps/api/src/services/email-scanner.service.ts#L1142)
+ [apps/api/src/routes/receipts.ts:63-64](../../apps/api/src/routes/receipts.ts#L63)

The comment at line 1140 explicitly notes "Cost rates kept in sync with apps/api/src/routes/receipts.ts.
If the model price changes, update both sites." This is a known drift-risk that should be
extracted to a single shared constant (e.g. `apps/api/src/utils/openai-pricing.ts`).

Fix: extract `COST_PER_PROMPT_TOKEN_MICROS` / `COST_PER_COMPLETION_TOKEN_MICROS` to one shared
location and import it in both places. (Per Project Rule 1 — "leaves cleaner than you found it.")

### M9. The barcode `consumeBarcodeQuota` increments BEFORE the cache lookup, double-charging cache hits
**Severity: MEDIUM (UX / quota waste).**
[apps/api/src/routes/barcode.ts:53-66](../../apps/api/src/routes/barcode.ts#L53)

Quota is consumed first; only THEN does the route check Redis cache. A cache-hit still
costs a quota slot even though no upstream API call was made. Premium gets 50 lookups/day —
on an item-add screen that does multiple barcode scans per minute, the user can hit the cap
with cached lookups.

Fix: move the `consumeBarcodeQuota` call BELOW the Redis cache lookup. Cache hits are free.

### M10. Free-plan items.ts limit is checked separately for auto-create vs review-approve
**Severity: LOW (verified-clean).**
[apps/api/src/services/email-scanner.service.ts:1407-1412](../../apps/api/src/services/email-scanner.service.ts#L1407)

The two-overload `createItemFromReceipt` differentiates `targetClient` (review-approve, no
free-limit enforcement) from no-client (auto-create, free-limit enforcement). That means:
**a free user can auto-import items beyond their cap via the review-approve path.** Wait —
that's the opposite of intent.

Re-reading: line 1410 calls `createItemUsing(targetClient, …, /*enforceFreeLimit*/false)`.
That bypasses the cap on the approve path. Intent: an item that landed in review (because
trust/confidence/DKIM didn't pass) should still be approveable even at the cap. This is
debatable — premium users see no difference, but free-plan users approving review items
sneak past the cap.

Fix: enforce the free-limit on review-approve too, but with a UX-clear error code so the UI
can surface "upgrade to import this".

---

## Other findings

### O1. The OAuth client_secret is loaded from env at startup, fetched on each call
**Verified-clean.** `config.google.clientSecret` and `config.microsoft.clientSecret` use the
`readSecret()` helper at config-load time. Not refreshed per request — good (matches the
audit checklist's preference).

### O2. `email_scans.status` enum is constrained
**Verified-clean.** Migration 002 creates `email_scan_status` ENUM with 4 values, plus
the provider CHECK in mig 070.

### O3. `OPENAI_API_KEY` missing returns 503 cleanly
**Verified-clean.** [services line 725-735](../../apps/api/src/services/email-scanner.service.ts#L725)
fails the scan with `error_message = 'OpenAI API key is not configured'`, and the receipts
route returns 501 ([routes/receipts.ts:117-120](../../apps/api/src/routes/receipts.ts#L117)).

### O4. `completion_message` IS populated on success
**Verified-clean.** [line 822-833](../../apps/api/src/services/email-scanner.service.ts#L822)
writes the success-path notes.

### O5. Multiple email accounts per user
**Verified-clean.** The unique constraint is `(user_id, provider, provider_email)` —
mig 038 line 41. So a user can have Gmail account A + Gmail account B + Outlook all at once.

### O6. Outlook OAuth flow correctly omits `code_verifier`
**Verified-clean.** [exchange line 410-417](../../apps/api/src/services/email-scanner.service.ts#L410)
only sends `code, client_id, client_secret, redirect_uri, grant_type, scope`. No
`code_verifier`, no `code_challenge`. Matches the documented "Outlook flow intentionally NO
PKCE" policy in CLAUDE.md.

### O7. The mobile-side `state` is generated with `Random.secure()` and base64-url encoded
**Verified-clean.** [email_oauth_service.dart:39-43](../../apps/mobile/lib/core/services/email_oauth_service.dart#L39)
uses 32 bytes. Good.

### O8. The mobile UI consumes `query` parameters from the redirect (not fragment)
**Verified-clean.** Both Gmail and Outlook use `response_type=code` (no `response_mode=fragment`),
and Microsoft explicitly sets `response_mode: 'query'` at
[email_oauth_service.dart:117](../../apps/mobile/lib/core/services/email_oauth_service.dart#L117).
The callback parser uses `Uri.parse(result).queryParameters` for both providers.

### O9. The mobile disconnect button uses non-optimistic UI
**Verified-clean.** [email_scanner_screen.dart:724-737](../../apps/mobile/lib/features/email_scanner/email_scanner_screen.dart#L724)
awaits the API call, then `ref.invalidate(emailIntegrationsProvider)`, then snackbar. On
error: snackbar with the error message; the integrations list is not invalidated (so the
card stays). Correct.

### O10. No TODO/FIXME/HACK markers
**Verified-clean.** Grep across all in-scope files — only one comment regex in receipts.ts
that incidentally matches "XXXX" (the digit-redaction pattern).

---

## Summary

| Severity | Count |
|---|---|
| Critical | 4 (C1, C2, C3, C4) |
| High | 8 (C7, C8, C10, H1, H2, H4, H5, H6, H7, H8) |
| Medium | 5 (C9, M1, M3, M9, M10) |
| Low/cosmetic | 8 |
| Verified-clean | 10 |

**Top 3 to fix first:**
1. **C1** (Outlook bypasses budget) and **C2** (budget checked once) — both are real cost-runaway
   risks. C1 is one line; C2 is two new checkpoints in the per-message loops.
2. **C3** (refresh-token rotation lost) — Outlook integrations will silently die after the
   first refresh. This is breakage, not theoretical.
3. **C4** (revoke doesn't call provider endpoint) — material privacy claim mismatch.

Everything else can be triaged into the next phase. The crypto util itself is correct (see
audit O1+O2 in the DB-agent's report); usage in `email-scanner.service.ts` is consistent.

The state-validation gap (C8) is documented separately — it's a defense-in-depth issue, not
an exploitable vector while the only client is the native mobile app.
