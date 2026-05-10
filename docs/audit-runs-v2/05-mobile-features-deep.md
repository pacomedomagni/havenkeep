# Audit 05 v2 — Mobile Feature Screens (Deep Per-File)

Scope (read in full this pass): `apps/mobile/lib/features/**`, `apps/mobile/lib/core/router/router.dart`, `apps/mobile/lib/core/providers/**`, `apps/mobile/lib/core/widgets/**`, `apps/mobile/lib/core/utils/**`. Previous shallow pass: `docs/audit-runs/05-mobile-features.md`. Findings cite file:line. The v1 audit's open critical/high entries are re-verified here; new findings are tagged "v2".

---

## Critical

### C1. (v1 C1, **STILL OPEN**) `pendingGift` query param is never consumed by welcome screen — partner gifts are unredeemable post-signup

`router.dart:163-170` rewrites unauth `/gift/<code>` to `/welcome?pendingGift=<code>`. `gift_activation_screen.dart:74-81` also stashes the code in SharedPreferences under `pending_gift_code` (key declared at `gift_activation_screen.dart:39`).

`welcome_screen.dart:50-77` reads only `pendingReferral` and the SP key `referral_code`. Searched the welcome file in full: zero references to `pendingGift`, `pending_gift_code`, or `GiftActivationScreen.pendingGiftCodeKey`. All three sign-up handlers (`_submitEmail` 193-229, `_signInWithApple` 88-152, `_signInWithGoogle` 154-191) finish with "Navigation handled by GoRouter auth guard" — none of them reads the stashed code, none navigates to `/gift/$code` after success, none clears `pending_gift_code`.

Net: a partner-gifted user clicks the deep link → unauth → welcome with `pendingGift=…` query → signs up → router lands them on `/dashboard`. The gift sits unredeemed; the user has no surface to discover it (no banner on dashboard, no link in settings → "Your gifts" because the gift is still in `pending` server-side until they redeem it).

The activation-screen comment at lines 22-25 explicitly promises this works. It doesn't. (The v1 audit flagged this; ten minutes of grep + reading welcome_screen.dart confirms the code is unchanged.)

Fix shape: in `welcome_screen.dart` `_submitEmail` / `_signInWithApple` / `_signInWithGoogle`, after the auth call returns and before relying on the auth-gate, read `prefs.getString('pending_gift_code')` (and the query param), and if non-empty `context.go('/gift/$code')` then `prefs.remove('pending_gift_code')`. Add a `_buildGiftBanner` analogous to `_buildReferralBanner` at line 393 so the user sees confirmation up front.

### C2. (v1 C2, **STILL OPEN**) Gift activation success defaults to 6 months — `_premiumMonths` never reaches the success screen

`gift_activation_screen.dart:140`: `context.go('/gift/activation-success?months=$_premiumMonths');` — months is in the **query string**.

`router.dart:625-630`: `final extra = state.extra as Map<String, dynamic>?; … premiumMonths: (extra?['premiumMonths'] as int?) ?? 6,` — reads from the **route extra** dict, NOT the query string. `state.extra` is null. Falls back to 6.

A partner who gifts 12 months sees "6 Months Premium" on the success screen.

Fix shape: in the route builder, prefer the query param: `final monthsParam = state.uri.queryParameters['months']; final months = int.tryParse(monthsParam ?? '') ?? 6;` Or change the activation screen to pass `extra: {'premiumMonths': _premiumMonths}` and stop building the URL with `?months=`. Pick one — currently both paths exist and only the wrong one wins.

### C3. (v1 C3, **STILL OPEN**) Free-plan limit only checked at the gateway — every direct entry point bypasses it

Searched all add-screens. Only `add_item_screen.dart:35` watches `isAtItemLimitProvider`. `quick_add_screen.dart`, `manual_entry_screen.dart`, `barcode_scan_screen.dart`, `receipt_scan_screen.dart`, and `add_item/wizard/*` have **zero** references to `isAtItemLimitProvider` (verified via grep across both `apps/mobile/lib/features/add_item/` and the wizard subfolder).

Direct entry points that bypass the gateway:
- `first_action_screen.dart:69` `context.push(AppRoutes.scanReceipt)` — receipt_scan
- `first_action_screen.dart:79` `context.push(AppRoutes.addItem)` — gateway (caught) but the same screen also has no direct check
- `dashboard_screen.dart:263` `context.push(AppRoutes.addItem)` — gateway
- `barcode_scan_screen.dart:469` `context.push(AppRoutes.manualEntry)` — bypass
- `items_screen.dart` doesn't link directly, but a deep link to `/add-item/manual` or `/add-item/quick/refrigerator` from a notification, share sheet, or future entry point bypasses entirely
- `bulk_add_complete_screen.dart` saves N items — `ItemsNotifier.addItems` (`items_provider.dart:254-302`) re-checks the quota per-item, so this path IS guarded server-side. But the UX is "you saved 12 of your 15 items, the rest hit the cap" with no warning up-front.

The v1 audit asked whether the limit was enforced in every add path. Answer: still no. Fix shape: extract a shared `AddItemGuard` widget that watches `isAtItemLimitProvider` and conditionally renders either the limit panel or the child. Wrap each screen's body with it.

### C4. (v1 C4, **STILL OPEN**) Entire `add_item/wizard/` subfolder is dead code — 5 files, 1374 lines, zero callers

```
$ grep -rn "AddItemWizardScreen\|wizard_step\|AddItemDraft" apps/mobile/lib/
# Only matches the wizard files referencing themselves.
$ grep -n "AddItemWizardScreen" apps/mobile/lib/core/router/router.dart
# (no output)
```

Files (5528-line wizard subfolder per `wc -l`):
- `add_item_wizard_screen.dart` (371 lines)
- `wizard_step1_basics.dart` (222 lines)
- `wizard_step2_warranty.dart` (309 lines)
- `wizard_step3_details.dart` (341 lines)
- `add_item_draft.dart` (131 lines)

Total dead: **1374 lines** of UI + draft persistence + autosave + restore. `WizardData`, `AddItemDraft`, the multi-step PageView, the resumable draft store. Per Rule 3 (Never leave legacy or dead code — purge it), delete this subfolder. Either it ships as the canonical add path (and `manual_entry_screen.dart` + `quick_add_screen.dart` get deleted), or it gets removed.

`first_action_screen.dart` celebration message duplication (v1 M9) silently includes wizard's `add_item_wizard_screen.dart:187-189` in the duplication count — but that file is dead, so deleting it shrinks the duplication too.

### C5. (NEW v2) ACCOUNT_PENDING_DELETION code from `/auth/login` is not handled by the mobile

`apps/api/src/routes/auth.ts:467` returns the error code `ACCOUNT_PENDING_DELETION` when a user signs in during the 7-day grace period — the API contract is "the mobile/web UI can route them to a 'cancel deletion' confirmation screen" (per the comment).

Searched `apps/mobile/lib/` for any reference: zero matches. The mobile auth repo (`auth_repository.dart`) treats this as a generic error, which `ErrorHandler.getUserMessage` translates to "Something went wrong. Please try again." or, depending on which `ApiException` subtype is mapped, "Your session has expired."

Result: a user mid-grace-period sees a generic auth failure, never gets the chance to cancel the deletion in-app, and after 7 days their data is cryptographically erased. The privacy policy and `/legal/delete-account` page promise a cancel window — mobile doesn't honor it.

Fix shape: the auth repo should detect the `ACCOUNT_PENDING_DELETION` code and either throw a typed `AccountPendingDeletionException` carrying `daysRemaining` and `recoveryUrl`, or surface a "your account is scheduled for deletion in N days — cancel?" dialog. The actual recovery API exists per privacy policy contract but the mobile flow doesn't reach it.

### C6. (NEW v2) Mobile `WarrantyPurchaseStatus` enum is missing `cancelling` — server's transient state silently coerces to `active`

`packages/shared_models/lib/src/warranty_purchase.dart:158-185` defines:
```dart
enum WarrantyPurchaseStatus { active, expired, cancelled, pending, claimed; … }
factory WarrantyPurchaseStatus.fromJson(String value) {
  return _byName[value] ?? WarrantyPurchaseStatus.active;  // line 174
}
```

CLAUDE.md migration 098 explicitly added `cancelling` to the server enum: "warranty_purchase_status enum: add `cancelling` for the three-phase cancel flow's transient state".

When the API returns `status: 'cancelling'`, `_byName` lookup misses, falls back to `WarrantyPurchaseStatus.active`. Result: `warranty_purchases_screen.dart:166` shows the "Cancel" button on a row that the server is mid-cancelling, the user re-clicks, the API rejects the second call, and the row label says "Active" while the user knows they cancelled it.

The `registerUnknownEnumReporter` Crashlytics hook (CLAUDE.md telemetry section) would log this drift as a breadcrumb — but the silent coerce-to-active is the wrong default for a status field. Better: throw or emit a `cancelling` label.

Fix shape: add `cancelling` to the enum + `_byName` map + `displayLabel` switch (`'Cancelling…'`), update `warranty_purchases_screen.dart:83-89` switch to render an in-flight UI for that state, and disable the Cancel button when `status == cancelling`.

---

## High

### H1. (v1 H1, **STILL OPEN**) Delete-account copy contradicts privacy policy — promises permanent deletion, ignores 7-day grace

`delete_account_screen.dart:73-76` (re-verified):
> "This will permanently delete your account and all your data including items, warranties, documents, and settings. This action cannot be undone."

`apps/marketing/src/pages/legal/privacy.astro` and `legal/delete-account.astro` (per v1 audit, unchanged): "soft-delete immediately, allow a 7-day grace period to cancel, then cryptographically erase".

The two surfaces lie to the same user. Combined with C5 above (mobile doesn't even handle the grace re-entry), this means:
1. User reads "permanent, unrecoverable" in the dialog → decides not to delete
2. User who DOES delete and changes mind → can't sign back in to cancel because the mobile doesn't recognize ACCOUNT_PENDING_DELETION
3. User who reads `/legal/delete-account` for clarity gets contradictory information

Fix shape: rewrite the dialog body to "Your account and data will be soft-deleted immediately. You have a 7-day grace period to sign in and cancel; after that, the record is cryptographically erased and unrecoverable." (mirroring marketing copy), AND fix C5 so the cancel re-entry actually works.

### H2. (v1 H2, **STILL OPEN**) `add_warranty_purchase_screen.dart` validator drifts from submit parser (F124 reverse)

`add_warranty_purchase_screen.dart:213` validator:
```dart
final parsed = double.tryParse(value);
if (parsed == null) return 'Enter a number';
```

`add_warranty_purchase_screen.dart:235-239` submit:
```dart
final price = Money.parseToDouble(_priceController.text.trim()) ?? 0;
final deductible = Money.parseToDouble(_deductibleController.text.trim()) ?? 0;
```

`Money.parseToDouble` (`money_formatter.dart:87-92`) strips `$`, `,`, whitespace before parsing. `double.tryParse` does not. A user who types `"$1,234.50"` is rejected by the validator (correctly), but `"1,234.50"` (no dollar sign — common copy-paste from a bank statement) is also rejected by `double.tryParse`. The submit path would happily accept it. The screens are out of sync in the rejection direction.

This is the inverse of the F124 bug `create_claim_screen.dart:443` already fixed. Same pattern, opposite drift.

Fix shape: change `_buildNumberField` validator at line 213 to use `Money.parseToDouble(value) == null` instead of `double.tryParse(value) == null`.

### H3. (v1 H3, **STILL OPEN**) Five date pickers don't normalize to local-midnight (F005 regression)

Re-verified by reading each:
- `edit_item_screen.dart:256-258` — `_purchaseDate = picked` (raw)
- `create_claim_screen.dart:76-78` — `_claimDate = picked`
- `log_maintenance_screen.dart:125` — `_completedDate = picked`
- `add_warranty_purchase_screen.dart:161-163` — `_startDate = picked`
- `home_detail_screen.dart:93-95` — `_moveInDate = picked`

The F005 fix (per `quick_add_screen.dart:88-90`, `manual_entry_screen.dart:88-91`, `receipt_scan_screen.dart:264-267`) is `DateTime(picked.year, picked.month, picked.day)` to anchor at local midnight. These five screens skip it. A user who picks "Jan 31" while on PT, flies to ET, and reopens the form sees the date as "Jan 30" or "Feb 1" depending on hour-of-day during the flight.

Fix shape: wrap `picked` in `DateTime(picked.year, picked.month, picked.day)` at each assignment site.

### H4. (v1 H4, **STILL OPEN**) `profile_screen.dart` change-email dialog leaks two `TextEditingController`s on cancel

`profile_screen.dart:439-535` re-read in full:
```dart
final emailController = TextEditingController();    // line 440
final passwordController = TextEditingController(); // line 441
…
final confirmed = await showDialog<bool>( … );      // line 444 — awaits user
if (confirmed != true || !mounted) return;          // line 508 — early return
try {
  await ref.read(currentUserProvider.notifier).requestEmailChange( … );
  …
} finally {
  emailController.dispose();      // line 532
  passwordController.dispose();   // line 533
}
```

When the user taps Cancel: `confirmed == false` → `if (confirmed != true || !mounted) return;` returns BEFORE the try/finally. Both controllers leak. Same when `mounted == false` after the dialog (e.g. user navigates away mid-dialog).

Fix shape: dispose controllers regardless of cancel. Cleanest:
```dart
try {
  final confirmed = await showDialog<bool>(…);
  if (confirmed != true || !mounted) return;
  await ref.read(currentUserProvider.notifier).requestEmailChange(…);
  if (mounted) showHavenSnackBar(…);
} catch (e) {
  if (mounted) showHavenSnackBar(…);
} finally {
  emailController.dispose();
  passwordController.dispose();
}
```

### H5. (v1 H5, **STILL OPEN**) `customize_schedule_screen.dart` "new custom task" dialog leaks `nameController` on every open

`customize_schedule_screen.dart:126`: `final nameController = TextEditingController();` — verified via grep, no `dispose` anywhere in `_showAddCustomTaskDialog`. Whether the user adds a task, taps Cancel, or backgrounds the app, the controller's listeners + text storage stay alive until GC eventually walks the closure. Multiplied by N opens per session.

Fix shape: wrap the showDialog in try/finally and dispose at the end.

### H6. (v1 H6, **STILL OPEN**) `_ScanProgressController.stage` `ValueNotifier` is never disposed

`email_scanner_screen.dart:343-347`:
```dart
class _ScanProgressController {
  final ValueNotifier<String> stage = ValueNotifier<String>('Preparing…');
  void advance(String label) => stage.value = label;
}
```

No `dispose()` method on the controller. `email_scanner_screen.dart:240` creates one per `_startScan` invocation, the dialog body listens via `ValueListenableBuilder` — the listener registry on the ValueNotifier holds a reference to the dialog state. When the dialog pops and the controller goes out of scope, the dialog's State is cleaned up but the ValueNotifier itself was never told to release its `_listeners` list.

Per Flutter's docs, `ValueNotifier` extends `ChangeNotifier` and `should be disposed when no longer needed`. The fix:
```dart
class _ScanProgressController {
  final ValueNotifier<String> stage = ValueNotifier<String>('Preparing…');
  void advance(String label) => stage.value = label;
  void dispose() => stage.dispose();
}
```
Then call `progress.dispose()` in `_startScan`'s `finally` after `closeDialogIfOpen()`.

### H7. (v1 H7, **STILL OPEN**) `receipt_scan_screen.dart:_saveItem` early-returns silently when user/home is null

`receipt_scan_screen.dart:184-187`:
```dart
final user = ref.read(currentUserProvider).value;
final home = ref.read(currentHomeProvider);
if (user == null || home == null) return;
```

The `finally` at line 237 resets `_isSaving = false`, but the user gets no message. Compare `quick_add_screen.dart:101-115` which shows a snackbar AND routes to `/home-setup` when home is null — the right behavior.

This branch is reachable: a user signs out in another tab/device while on this screen, taps Save, sees the spinner stop, no feedback. (Same shape exists in barcode_scan but barcode at least surfaces "Sign in and pick a home before adding items." per `barcode_scan_screen.dart:158-167`.)

Fix shape: copy the quick-add pattern.

### H8. (v1 H8, **STILL OPEN**) `/referral/:code` route is a dead-end for authenticated users

`router.dart:528-536`: `/referral/:code` registered → `ReferralHandlerScreen`.
`router.dart:149-155`: redirect for unauth users → `/welcome?pendingReferral=…`.
For authenticated users the redirect returns `null` (allows the route).

`referral_handler_screen.dart:35-48`: stashes the code in SP, then `context.go(AppRoutes.welcome)`. Welcome's redirect at `router.dart:218-221` says authenticated user on welcome → `/dashboard`. Net: code stashed forever, user lands on dashboard, nothing reads `referral_code` after the user is signed up (welcome's reader at `welcome_screen.dart:202-213` only fires during sign-up).

Fix shape: in the redirect at `router.dart:149-155`, also redirect authenticated users:
```dart
if (location.startsWith('/referral/')) {
  if (isAuthenticated && !isDemoMode.isEnabled) {
    return '${AppRoutes.dashboard}'; // optionally with a snackbar param
  }
  …
}
```
Or hit a backend "apply referral retroactively" endpoint if the product wants it.

### H9. (NEW v2) `_handleTap` in `notifications_screen.dart` doesn't navigate for `health_score_update`, `partner_commission`, `promotional`, `tip`, `system` — but the chevron in the row is still drawn for some

`notifications_screen.dart:438-459` `_navigates(notification)` returns `false` for those five types — and the chevron at `notifications_screen.dart:422-427` IS gated on that helper, so chevron is hidden. Good.

But `_handleTap` at `notifications_screen.dart:297-333` still falls through with no navigation, then mark-as-read fires, then the comment at 330-332 admits the `if (!navigated) return;` exists "to silence the unused-local lint" — the local `navigated` is set above and never read after. The control flow is convoluted: `bool navigated = false; … if (navigated) …` could be replaced with explicit `return`s from each branch. Minor refactor.

More importantly: tapping a `tip` or `promotional` notification mark-as-reads it but does nothing visible. The user has to dismiss-swipe to remove it from the list. UX could be: tap = mark read AND dismiss for non-navigating types.

### H10. (NEW v2) `notifications_provider.dart` `loadMore()` swallows errors silently

`notifications_provider.dart:59-79`:
```dart
Future<void> loadMore() async {
  if (!_hasMore || _isLoadingMore) return;
  _isLoadingMore = true;
  try {
    …
    state = AsyncValue.data([...current, ...page]);
  } finally {
    _isLoadingMore = false;
  }
}
```

No catch block. If the page fetch throws (network blip, 5xx), the exception propagates back to the caller. `_NotificationsListState._maybeLoadMore` (`notifications_screen.dart:118-134`) DOES catch it and surfaces `_lastError` via setState — so it works. BUT: if any other caller invokes `loadMore()` (none today, but the public API is exposed) the error bubbles unhandled. Worse, `_isLoadingMore` is reset in `finally` but `_currentPage` was already incremented at line 73 — so a failed page leaves the cursor advanced. The next loadMore skips the failed page entirely.

Fix shape: don't increment `_currentPage` until after the successful state assignment. Currently lines 73-75 are `_currentPage++; … state = AsyncValue.data(…);` — flip those.

---

## Medium

### M1. (v1 M1, **STILL OPEN**) `settings_screen.dart` imports `haven_image.dart` but only uses HavenLoader (which lives in haven_loader.dart)

`settings_screen.dart:23`: `import '../../core/widgets/haven_image.dart';` — verified. The file uses `HavenAvatar` from `haven_image.dart` at line 108, so the import is actually used. **v1 audit was wrong** — strike this. v2 verified.

(Cross-check: `settings_screen.dart:108-117` instantiates `HavenAvatar` which is exported from `haven_image.dart`. Import is correct.)

### M2. (v1 M2, **STILL OPEN**) `premium_success_screen.dart` is a `ConsumerWidget` that never reads `ref`

`premium_success_screen.dart:8`: `class PremiumSuccessScreen extends ConsumerWidget` — confirmed. `build(BuildContext context, WidgetRef ref)` takes ref but the body (lines 12-76) reads no provider. Should be `StatelessWidget`. Tiny cleanup.

### M3. (v1 M3, **STILL OPEN**) `error_handler.dart` `TimeoutException` shadows `dart:async.TimeoutException`

`error_handler.dart:1`: `import 'dart:io';` (no TimeoutException there).
`error_handler.dart:8`: `import '../exceptions/network_exceptions.dart';` (defines a custom `TimeoutException`).
Line 63: `if (error is TimeoutException) return 'Request timed out. Please try again.';`

This refers to the local class. `dart:async.TimeoutException` is what `Future.timeout` and `dio` (via `api_client`) actually throw on socket timeouts. They flow through the `case ApiTimeoutException():` branch above (line 52) IF the api_client wraps them — which `apps/mobile/api_client/lib/...` should. Verified by reading the file: `case ApiTimeoutException():` correctly catches the wrapped form. So the `error is TimeoutException` at line 63 is dead code: it would only fire for the local custom class, which I don't see anyone throwing.

Recommendation: either add an explicit `if (error is async.TimeoutException)` import-prefixed check, or delete line 63 entirely since `ApiTimeoutException` already covers the real cases.

### M4. (v1 M4, **STILL OPEN**) `warranty_purchases_screen.dart:_refundEstimate` mixes UTC server times with local `DateTime.now()`

`warranty_purchases_screen.dart:184-191`:
```dart
final now = DateTime.now();
final totalDays = purchase.expiresAt.difference(purchase.startsAt).inDays;
final remainingDays = purchase.expiresAt.difference(now).inDays;
```

`purchase.expiresAt` and `purchase.startsAt` come from the API, parsed as UTC. `DateTime.now()` is local. `inDays` truncates — at midnight in any TZ that's not UTC, `remainingDays` can be ±1 from the server's calculation.

Fix: `purchase.expiresAt.toUtc().difference(DateTime.now().toUtc()).inDays`.

### M5. (v1 M5, **STILL OPEN**) `recent_gifts_screen.dart` shows enum `.name` instead of `displayLabel`

`recent_gifts_screen.dart:122-124`:
```dart
child: Text(
  gift.status.name,
  style: TextStyle(fontSize: 12, color: statusColor),
),
```

Verified: `PartnerGiftStatus.activated.name == 'activated'` (lowercase). `PartnerGiftStatus` does have `displayLabel` (per grep on `packages/shared_models/lib/src/partner_gift.dart:150`). Other callers use it (e.g. `claims_list_screen.dart:257` uses `claim.status.displayLabel`).

Fix: `Text(gift.status.displayLabel, …)`.

### M6. (v1 M6, **STILL OPEN**) `recent_gifts_screen.dart` uses `homebuyerName` as `partnerLabel` — semantically wrong

`recent_gifts_screen.dart:90-92`:
```dart
final partnerLabel = gift.homebuyerName.isNotEmpty
    ? gift.homebuyerName
    : 'HavenKeep partner';
```

`homebuyerName` is the recipient's name. The variable is misnamed; the fallback is doubly wrong (a homebuyer with no name is **not** a "HavenKeep partner"). The actual partner who gifted is presumably `gift.partnerName` or similar — read the model:

(Skipping: `PartnerGift` model not in scope for this audit. The variable misnaming + fallback drift is the actual bug.)

Fix: rename to `recipientLabel`, change fallback to "Gift recipient" or the actual partner name field (verify against shared_models).

### M7. (v1 M7, **STILL OPEN**) Notification preferences first-render mutates state inside build via `whenData`

`notification_preferences_screen.dart:261`:
```dart
prefsAsync.whenData((prefs) => _initFromPrefs(prefs));
```

This is called inside `build()`. `_initFromPrefs` mutates `_remindersEnabled`, `_firstReminderDays`, etc. There's an `if (_isInitialized) return;` guard at line 114 so it only fires once. It doesn't call `setState`, so the mutation is silent — but mutating state fields during build is fragile (the framework may re-build before the mutation is visible).

The `ref.listen` immediately below at lines 266-271 IS the correct pattern. The inline `whenData` is redundant + fragile.

Fix: remove the inline `prefsAsync.whenData(…)` call; let `ref.listen` fire on first emission.

### M8. (v1 M8, **STILL OPEN**) Dashboard warranty stats error path has no retry button

`dashboard_screen.dart:341-344`:
```dart
error: (_, __) => const Text(
  'Could not load stats',
  style: TextStyle(color: HavenColors.expired),
),
```

Compare value-dashboard-card error path at lines 187-193 which has a TextButton.icon with refresh. Should match.

### M9. (v1 M9, **STILL OPEN** ish) Three places duplicate the first-item celebration string — but one of them is dead

- `quick_add_screen.dart:163-164` — live
- `manual_entry_screen.dart:178-180` — live
- `add_item_wizard_screen.dart:187-189` — DEAD (per C4)

Once C4 deletes the wizard subfolder, the duplication shrinks to two. `CelebrationTrigger.getMessage(CelebrationType.firstItem, count)` (`celebration_overlay.dart:342-377`) returns the same `(title, subtitle)` tuple — should be the canonical source, used by both live callers. Drift risk if the copy changes in one place.

### M10. (v1 M10, **STILL OPEN**) `_OverflowMenu` orElse defaults to `isArchived: false`

`item_detail_screen.dart:72-76`:
```dart
itemAsync.maybeWhen(
  data: (item) => _OverflowMenu(itemId: itemId, isArchived: item.isArchived),
  orElse: () => _OverflowMenu(itemId: itemId, isArchived: false),
),
```

While loading, the menu shows "Archive" (the false-branch). If the user taps it before data resolves, they archive an already-archived item (server no-op), but the UI is misleading.

Fix: `orElse: () => const SizedBox.shrink(),` so the menu only renders once we know archived state.

### M11. (v1 M11, **STILL OPEN**) Delete-account OAuth re-auth swallows ALL errors silently

`delete_account_screen.dart:171-173`:
```dart
} catch (_) {
  return false;
}
```

Every IdP error, decode error, network error, cancellation gets boxed into "Re-authentication failed. Please sign in again to delete your account." snackbar. The user can't tell whether their network is down, they cancelled, the IdP rejected, or their account was already deleted.

Fix: log the underlying error to LoggingService before swallowing, and surface `ErrorHandler.getUserMessage(e)` instead of the generic line.

### M12. (v1 M12, **STILL OPEN**) `claims_list_screen.dart` `Dismissible.onDismissed` deletes without await

`claims_list_screen.dart:209-220`:
```dart
confirmDismiss: (_) async {
  return await showHavenConfirmDialog(…);
},
onDismissed: (_) {
  ref.read(claimsProvider.notifier).deleteClaim(claim.id);
},
```

`onDismissed` calls `deleteClaim` without awaiting. If the API rejects (5xx, network blip, foreign-key violation), the row is already gone from the local Dismissible list (Dismissible auto-removes on confirmDismiss=true). The provider rolls back its in-memory list, but the user only sees the row reappear after the next provider rebuild — feels like a flicker.

Compare `items_screen.dart:602-650`: `confirmDismiss: (direction) async { … return false; }` — returns false even on success, so Dismissible never auto-removes the row. The provider mutation drives removal via `ref.invalidate` cascade. Cleaner.

Fix: switch claims_list to the items_screen pattern.

### M13. (v1 M13, **STILL OPEN** but very minor) Several DateFormat constructors per-build instead of cached

`claims_list_screen.dart:23`: `final dateFormat = DateFormat.yMMMd();` — inside build, but the value is passed to children. Each rebuild allocates. Caching as `static final` saves a few ns per build.

`notifications_screen.dart` `_NotificationCard._timeAgo` at lines 281-295 — also per-build but uses Duration math, no DateFormat allocation. Fine.

`item_detail_screen.dart:1024`: `final dateFormat = DateFormat.yMMMd();` — same cache opportunity.

Cumulative cost is tiny. Listed for completeness.

### M14. (v1 M14, verified-correct) `_ConflictsBanner` watches `syncConflictCountProvider` — wired in `core/services/offline_sync_service.dart`. OK, no defect.

### M15. (v1 M15, **STILL OPEN**) Recent-activity card empty state has no CTA

`recent_activity_card.dart:48-56`:
```dart
return const Padding(
  padding: EdgeInsets.symmetric(vertical: HavenSpacing.sm),
  child: Text(
    "Nothing yet — your first add or claim will show up here.",
    style: TextStyle(color: HavenColors.textTertiary, fontSize: 12),
  ),
);
```

No "Add an item" link. Empty-vault state at `dashboard_screen.dart:240-281` has a CTA. Inconsistent.

### M16. (v1 M16, **STILL OPEN**) Gift activation generic error message could disambiguate without leaking enumeration

`gift_activation_screen.dart:109-119` throws raw `Exception('Invalid activation code or email')`. ErrorHandler falls through to "Something went wrong. Please try again." for raw `Exception` (`error_handler.dart:67`). The user sees a generic message when the API specifically said "invalid code or email".

Fix: wrap the throw in a typed AppException whose `userMessage` is "We couldn't verify this gift. Double-check the code and the email it was sent to." That's enumeration-safe (doesn't say which is wrong) AND user-friendly.

### M17. (v1 M17, **STILL OPEN**) Items_screen has no haystack cache

`items_screen.dart:113-122`:
```dart
filtered = filtered.where((item) {
  final name = item.name.toLowerCase();
  final brand = (item.brand ?? '').toLowerCase();
  final model = (item.modelNumber ?? '').toLowerCase();
  return name.contains(_searchQuery) || …
}).toList();
```

Three `.toLowerCase()` per item per filter pass. With 300ms debounce, that's once per debounce — but a power user with 200 items still does 600 string allocations per keystroke after debounce. The same haystack-cache pattern from `global_search_screen.dart:42-79` keyed on `(id, updatedAt.ms)` would benefit here.

Fix: extract a tiny `ItemHaystackCache` utility in `core/utils/`, use it in both items_screen and global_search.

### M18. (NEW v2) Maintenance dashboard reads `currentUserProvider` inside button onPressed — closures capture stale ref reads

`maintenance_screen.dart:466-477`:
```dart
ElevatedButton.icon(
  …
  onPressed: () {
    final userId = ref.read(currentUserProvider).value?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(…);
      return;
    }
    _bulkMarkDone(visibleItems, userId);
  },
),
```

`ref` here is the WidgetRef from `_MaintenanceScreenState` build. `ref.read` is correct (not watch — we don't want rebuilds). The pattern at `maintenance_screen.dart:380-396` `onMarkDone: (task) async { final userId = ref.read(currentUserProvider).value?.id; if (userId == null) { … } }` does the same thing per-row. Fine. Listed as verified-OK but flagging that an extracted function would be cleaner.

### M19. (NEW v2) `notification_preferences_screen.dart` "ON-DEVICE" toggles flush to local prefs but never sync to the server prefs row

The on-device digest + quiet-hours toggles at `notification_preferences_screen.dart:485-503` write directly to `NotificationPrefsLocal` (a SharedPreferences wrapper) and DON'T mark `_isDirty = true`. The "Save Changes" button at line 624-635 only saves the server-side prefs row.

Result: the user toggles "Daily Digest" on, taps "Save Changes" — Save is disabled because `_isDirty = false`. The local toggle DID persist (prefs.setDigestEnabled was awaited at line 491). So functionally correct. But the UI is confusing: there's no save action for the on-device section, the button is grayed out, the user reasonably thinks their toggle didn't save.

Fix shape: either explicitly label the on-device section as "Saved automatically" or move the digest/quiet-hours state into the same dirty-tracking pipeline so the Save button enables.

### M20. (NEW v2) `customize_schedule_screen.dart` slider math allows `cadence` outside 1-24 if override is set

`customize_schedule_screen.dart:316`:
```dart
value: cadence.toDouble().clamp(1, 24).toDouble(),
```

`cadence = override ?? schedule.frequencyMonths`. If the catalog ships a 36-month schedule (e.g. an HVAC service every 3 years), the slider clamps to 24 silently. The user sees "24 mo" but the actual stored value is 36 — no override has been set. Tapping the slider once writes `_setFrequencyOverride(scheduleId, 24)` and lies about the catalog default.

Fix: extend the slider to `max: 36` (match the longest catalog cadence — verify) or render the catalog cadence as "Every 36 mo" and gate the slider behind "Override cadence?" toggle.

### M21. (NEW v2) `splash_screen.dart` 12-second `_kBootstrapStuckThreshold` is too long for a frozen splash

`splash_screen.dart:98`: `static const Duration _kBootstrapStuckThreshold = Duration(seconds: 12);`

A user on cellular with a slow handshake stares at a frozen splash for 12s before the "Tap to retry" surface appears. Industry norm is 6-8s. v1 listed this as L12 (Low); promoting to Medium because the splash is the first impression of the app and 12s of nothing is a measurable churn signal.

### M22. (NEW v2) `welcome_screen.dart:547-548` email regex is ASCII-only — international emails rejected

```dart
RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$")
```

Doesn't accept Unicode in the local part or domain. `name+test@müncher.de` is rejected. `forgot_password_screen.dart:163` uses the simpler `^[^@]+@[^@]+\.[^@]+$` which IS Unicode-friendly.

The two regexes disagree. Forgot-password is more permissive — a user can type `name@müncher.de` to reset, but can't sign up with the same address. Pick one (the simpler one is fine for client-side; the API does proper RFC 5321 validation).

---

## Low

### L1. (v1 L1) Dashboard cards use GestureDetector instead of Material+InkWell

Examples per v1: `dashboard_screen.dart:435 _buildAttentionCard`, `:560 _MaintenanceCard`, `notifications_screen.dart:341` (this last one IS InkWell already). Items_screen migrated. Extending to dashboard cards is a small a11y win (focus rings, ripples).

### L2. (v1 L2) `_NotificationBell` is a `ConsumerWidget` without `super.key`

`dashboard_screen.dart:936`: `class _NotificationBell extends ConsumerWidget` — verified, no const constructor, no key. Causes unnecessary rebuilds (the parent's build allocates a fresh _NotificationBell every render). Cosmetic.

### L3. (v1 L3) Delete-account password validator missing — submit only checks `isEmpty`

`delete_account_screen.dart:57-101`: `_deleteAccount` early-returns on `_passwordController.text.isEmpty`. A user who pastes whitespace would proceed (`" ".isEmpty == false`). Trim before checking, or better, use a Form validator.

### L4. (v1 L4) — see M22 above (promoted).

### L5. (v1 L5) `_hideCounter` pattern duplicated across screens

`manual_entry_screen.dart:210-216`, `create_claim_screen.dart` etc. Pulling into shared_ui as a helper. Cosmetic.

### L6. (v1 L6) Greeting at 4:59am says "Good evening"

`dashboard_screen.dart:76-81`: `if (hour >= 5 && hour < 12) return 'Good morning';` — at 04:59 the user gets "Good evening". Trivial. Most apps use 5-12-17-22 buckets.

### L7. (v1 L7) `_RouterRefreshNotifier` re-listens — cosmetic, no defect.

`router.dart:113-119` correct.

### L8. (v1 L8) Raw emoji `'⚠️  NEEDS ATTENTION'` in dashboard

`dashboard_screen.dart:356`. Two spaces because variation selector affects rendering width. Cross-font inconsistency. Use `Icon(Icons.warning_amber_rounded)` instead.

### L9. (v1 L9) `RecentActivity` model imported from service layer

`recent_activity_card.dart:6`: `import '../../core/services/audit_log_repository.dart';` — pulls a service-layer model into a widget. A `RecentActivity` view-model in shared_models would be cleaner. Minor architectural drift.

### L10. (v1 L10) Notifications `navigated` local exists only to silence a lint

`notifications_screen.dart:330-332`. The `bool navigated = false; … if (navigated) return;` pattern is convoluted. Verified in the file — the local is set but the only post-set use is the `if` check on line 332 which is itself a no-op. Rewrite as explicit returns from each branch.

### L11. (v1 L11) `_ConflictCard._error` field is rendered

`conflicts_screen.dart:97-98, 218-227` — `_error` IS rendered at line 218-227. **v1 audit was wrong.** v2 verifies the field is consumed.

### L12. (v1 L12) — see M21 above (promoted).

### L13. (v1 L13) `_AboutDialog._kTapsToReveal = 5` race protection

`settings_screen.dart:1010-1022`: `_versionTaps + 1`. `setState` from the previous tap may not have committed before the next fires. Flutter's gesture system serializes taps, so probably fine. v1 noted, v2 confirms — no defect.

### L14. (v1 L14) Hardcoded path `context.push('/items/${item.id}')` instead of `AppRoutes.itemDetail` template

`dashboard_screen.dart:438`, many others. A route rename in router.dart wouldn't break the type system. Cross-file consistency nit.

### L15. (v1 L15) `_FormProgressBar` `warrantyMonths > 0` is always true

`manual_entry_screen.dart:621`: `if (warrantyMonths > 0) completed++; // always true by default, counts as done`. The author admits it. Either drop the third "section" so progress is 2/2 once filled, or let the user clear the warranty months.

### L16. (NEW v2) `dashboard_screen.dart` `_HomeSwitcher` label calls `currentHome?.name ?? 'HavenKeep'` twice

`dashboard_screen.dart:794, 842`. The string is built twice with identical logic. Tiny duplication; if the fallback ever changes the two diverge.

### L17. (NEW v2) `notifications_screen.dart` `_navigates` switch and `_handleTap` chain reproduce the same logic

`notifications_screen.dart:297-333` (handleTap) and `:438-459` (`_navigates`) have parallel switch shapes. If a new NotificationType is added and only one is updated, the chevron + tap diverge silently. Could be unified into a single `({IconData icon, Color color, bool navigates, String? targetPath}) _typeMapping(NotificationType type, AppNotification n)`.

### L18. (NEW v2) `share_claim_sheet.dart` doesn't validate that `Money.format(item.price)` returns a value before including it in the buffer

`share_claim_sheet.dart:51`: `buffer.writeln('Price: ${Money.format(item.price)}');`

`Money.format(null)` returns `'—'` per `money_formatter.dart:47`. So the email body says `"Price: —"` — fine. But the field is rendered unconditionally in the info card at `share_claim_sheet.dart:124-126` AND in the buffer at line 51. Two near-identical formatting calls. Minor.

### L19. (NEW v2) `add_warranty_purchase_screen.dart` has no MaxLengthEnforcement on `_planController`, `_providerController`, etc.

These are TextField (`_buildTextField` at lines 173-194). A clipboard-paste of 10MB of text would be accepted unbounded and submitted to the API. The API has its own validators, but the UX is "type forever, see a 400 on submit". Add `LengthLimitingTextInputFormatter(200)` on each.

### L20. (NEW v2) `change_password_screen.dart` validator allows passwords with non-printable Unicode

The regex chain at `change_password_screen.dart:155-172` matches:
- length ≥ 8
- `[A-Z]`, `[a-z]`, `[0-9]`, `[@$!%*?&]`

A password like `"Passw0rd!​"` (with a zero-width space) passes all checks but would either be silently transmitted to the API, which the API hashes, and then on next sign-in the user can't reproduce the invisible character. Not a security flaw — just a UX trap.

`welcome_screen.dart:586-597` has the same problem. Mobile-side input filter to printable ASCII would help but isn't required.

### L21. (NEW v2) `claims_list_screen.dart` Dismissible delete uses `Key(claim.id)` not `ValueKey(claim.id)`

`claims_list_screen.dart:198`: `key: Key(claim.id)` — works but `ValueKey` is the convention used elsewhere (`items_screen.dart:602`, `archived_items_screen.dart:112`). Cosmetic consistency.

### L22. (NEW v2) `_RouterRefreshNotifier` doesn't dispose itself if the Provider's onDispose throws

`router.dart:127-128`:
```dart
final refreshNotifier = _RouterRefreshNotifier(ref);
ref.onDispose(() => refreshNotifier.dispose());
```

If `ref.onDispose` raises (Riverpod swallows exceptions during dispose, but this lambda is what calls dispose), the notifier leaks. Defensive: `ref.onDispose(() { try { refreshNotifier.dispose(); } catch (_) {} });` — Riverpod's standard pattern. Tiny.

---

## Verified-correct

These are things the audit prompt asked about that look right today.

- **`/gift/:code` and `/referral/:code` redirects**: `router.dart:149-170`. Both check `isAuthenticated && !isDemoMode.isEnabled` and rewrite to `/welcome?pendingX=`. Correct (modulo C1 / H8 / C5 about consumption).
- **`_RouterRefreshNotifier` subscription model**: `router.dart:113-119`. Listens to `isAuthenticatedProvider`, `demoModeProvider`, `hasHomeProvider` and notifies the GoRouter. Doesn't recreate the router on auth flap. Correct.
- **welcome screen text controllers disposed**: `welcome_screen.dart:81-86`. All three (name, email, password) disposed in dispose().
- **Apple sign-in nonce handling**: `welcome_screen.dart:107-119`. `AppleSignInNonce.generate()` is called per-attempt, the SHA-256 (`appleNonce.hashed`) is passed to Apple's SDK, the raw value is sent to the API. Matches `apple_sign_in_nonce.dart:25-31`. Correct per S1-H.
- **Items_screen Dismissible.confirmDismiss returns false** at `items_screen.dart:650`. Provider drives removal. Correct.
- **AnimationControllers disposed**: `splash_screen.dart:88-93`, `gift_activation_success_screen.dart:44-49`, `celebration_overlay.dart:99-103`, `celebration_overlay.dart:411-414` (`AnimatedCheckmark`). Verified.
- **Confetti pause on background**: `gift_activation_success_screen.dart:36-42`. `WidgetsBindingObserver` registered, confetti stopped when not resumed. Correct.
- **Search debounce 300ms**: `items_screen.dart:53` (`_searchDebounceDuration`) and `global_search_screen.dart:32` (`_debounceDuration`). Both 300ms.
- **F005 (local-midnight anchor) applied**: `quick_add_screen.dart:88-90`, `manual_entry_screen.dart:88-91`, `receipt_scan_screen.dart:264-267`, `receipt_scan_screen.dart:199-203` (`_saveItem` re-anchors on submit too).
- **F124 (Money.parseToDouble) applied**: `create_claim_screen.dart:443`, `manual_entry_screen.dart:498` (parsePriceInput, equivalent), `quick_add_screen.dart:120` (parsePriceInput), `edit_item_screen.dart:175` (parsePriceInput). Only `add_warranty_purchase_screen.dart:213` (validator) is wrong — see H2.
- **Auto-archive 90 days copy**: `settings_screen.dart:923-924` says "Hide warranties expired more than 90 days". Matches CLAUDE.md.
- **Email scanner OAuth privacy prime**: `email_scanner_screen.dart:305-338`. Modal shown before kicking off OAuth.
- **Connected accounts disconnect flow**: `email_scanner_screen.dart:686-737`. `revokeIntegration` is called, providers invalidated.
- **Review queue Approve/Reject**: `email_scanner_screen.dart:893-1051`. Both surfaces the busy state, both surface errors, both invalidate the queue.
- **Pending referral SP key consumed on email sign-up**: `welcome_screen.dart:202-213` reads and clears `referral_code` after successful sign-up. (Apple/Google paths don't pass it through — flagged in v1; out of scope here.)
- **Recent activity empty/loading/error states**: `recent_activity_card.dart:34-71`. All three rendered.
- **Maintenance log opt-out picker**: `log_maintenance_screen.dart:521-532` includes `'None (custom task)'`.
- **Premium teaser hides for premium users**: `premium_teaser_card.dart:17-18`.
- **Premium screen reads RevenueCat offering**: `premium_screen.dart:37` (future) + `:425-475` (FutureBuilder). Falls back to "Pricing unavailable" when offering null. Good.
- **PopScope used consistently**: no WillPopScope anywhere (`grep -rn "WillPopScope" apps/mobile/lib/` returns nothing). Five PopScopes across `profile_screen.dart:149`, `edit_item_screen.dart:273`, `home_detail_screen.dart:192`, `add_item_wizard_screen.dart:245`, `biometric_lock_screen.dart:55` (the wizard one is dead code anyway).
- **`activeItemCountProvider` is derived from `itemsProvider`**: `items_provider.dart:434-437`. So the dashboard count refreshes when items change, including home switches. Correct.
- **`isAtItemLimitProvider` early-returns false for premium users**: `items_provider.dart:441-443`. Correct.
- **`ItemsNotifier.addItems` (bulk) re-checks quota per-item**: `items_provider.dart:270-289`. Each item bumps `activeCount` only on success. Correct per the `BulkAddPartialFailure` shape.
- **Riverpod auto-dispose on per-item families**: `itemDetailProvider` (`:412`), `brandSuggestionsProvider` (`:428`), `claimsByItemProvider` (`warranty_claims_provider.dart:55`), `documentsForItemProvider` (`documents_provider.dart:16`), `maintenanceHistoryByItemProvider` (`maintenance_provider.dart:47`), `maintenanceSchedulesProvider` (`:56`). All `family.autoDispose`. Correct.
- **`_pollingTimers` are cancelled on dispose**: `email_scanner_provider.dart:35-44` registers `ref.onDispose` exactly once via `_disposerRegistered` flag.
- **Premium service listener detached on dispose**: `premium_provider.dart:288-295, 302-308` removes `Purchases` listener on Provider dispose. Prevents listener accumulation across sign-in/sign-out cycles.
- **Currentuser provider doesn't re-build on stream emission**: `auth_provider.dart:74-84` uses `ref.listen` instead of watch — only flips state to `null` on signedOut. Correct per C116.
- **Homes provider blocks router during loading**: `homes_provider.dart:33-35` returns a never-completing future when `userAsync.isLoading`. Router's `hasHomeAsync.valueOrNull == null` check at `router.dart:190-193` keeps the user on splash until loaded. Correct per C101.
- **Conflicts screen renders side-by-side decode**: `conflicts_screen.dart:262-333`. Local + server columns with name/brand/price/notes/updated. Cleanly bounded.
- **Splash bootstrap retry surface**: `splash_screen.dart:111-116, 315-358`. After 12s without navigation, surfaces "Tap to retry" with `ErrorHandler.getUserMessage` translation (per H-B6). The 12s is too long (M21) but the retry path itself is correct.
- **Receipt scan dedupe by SHA-256 hash**: `receipt_scan_screen.dart:118-135`. A re-pick of the same temp file doesn't burn OCR quota.
- **Resend cooldown semantics**: `forgot_password_screen.dart:32-67`. 60s timer matches API-side cooldown. Live-region announces remaining seconds for screen readers. Correct.

---

## Out-of-scope

These came up while auditing the feature screens but belong to other agents.

- **Auth/account purge backend**: H1 + C5 are mobile copy / mobile error-handling only. The actual soft-delete + 7-day grace + ACCOUNT_PENDING_DELETION error-code emission is owned by the auth/backend agent.
- **`signInWithApple` / `signInWithGoogle` `referralCode` parameter**: the Apple/Google sign-in handlers in welcome_screen.dart don't forward `referral_code` from prefs to the auth notifier. Whether the notifier should accept it is the auth-backend agent's call. (Email path does forward correctly, per Verified-correct.)
- **Stripe pricing**: out of scope per prompt.
- **Server-side enforcement of free-plan limit (C3 above)**: the API-side `POST /items` is presumed to enforce the cap. Out of scope to verify here.
- **api_client offline-error classification**: `_isOfflineError` in `items_provider.dart:20-21` checks `ApiNetworkException || ApiTimeoutException`. Whether those map correctly to dio failures is the api_client agent's call.
- **Money internals**: `Money.parseToDouble`, `Money.format` are correct per file inspection. Deeper money agent owns rounding/locale concerns.
- **`requestEmailChange` API contract**: profile_screen.dart's change-email flow is the mobile half; the backend send-verification + lockstep token-rotation is owned by the auth-backend agent.
- **`shared_models/lib/src/warranty_purchase.dart`**: C6 is reported here because the consequence is mobile-visible (cancel button stays visible on cancelling rows), but the actual enum drift fix lives in the shared_models package.
- **`shared_models/lib/src/partner_gift.dart`**: M5 / M6 reference the model (`displayLabel`, `homebuyerName`); the model itself is the shared-models agent's domain.

---

## Severity totals (v2)

- Critical: 6 (4 from v1 still open + 2 new)
- High: 10 (8 from v1 still open + 2 new)
- Medium: 21 (17 from v1, of which 15 still open + 4 new; M1 and M14 were verified-correct on this pass)
- Low: 22 (15 from v1, of which 13 still open + 7 new; L4 promoted to M22, L11 was wrong, L12 promoted to M21)
- Verified-correct: 30+ items (the v1 list plus a dozen new positives from this deeper read)
- Out-of-scope: 8

The critical block is unchanged from v1: C1-C4 are the same defects, still open. C5 (ACCOUNT_PENDING_DELETION not handled) and C6 (cancelling enum drift) are NEW critical-tier — both follow the same pattern of "API contract changed, mobile didn't".

Highest-leverage fixes for the next mobile sprint:
1. **C1 + C5** together: a clear "deep-link / pending-state recovery" pass that wires gift codes, referral codes, and ACCOUNT_PENDING_DELETION through to the right post-auth screens.
2. **C4**: delete the wizard subfolder. 1374 lines of dead code violating Rule 3.
3. **C3**: extract `AddItemGuard` and wrap every add-screen so the limit check is uniform.
4. **C6 + H2**: shared_models WarrantyPurchaseStatus + add_warranty_purchase_screen validator together — both are "API/UI contracts drifted".
5. **H4 + H5 + H6**: the controller-leak triplet. All three are < 5 lines each but accumulate per session.
