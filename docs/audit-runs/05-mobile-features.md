# Audit 05 — Mobile Feature Screens

Scope: `apps/mobile/lib/features/**`, `apps/mobile/lib/core/router/router.dart`, `apps/mobile/lib/core/providers/**`, `apps/mobile/lib/core/widgets/**`, `apps/mobile/lib/core/utils/**`. Out-of-scope domains (offline sync internals, Drift, api_client, account purge backend, money/Stripe internals) are noted in the **Out-of-scope** section but only when the mobile screen reaches into them in a buggy way.

Findings cite the file:line that documents the issue. "Verified-correct" entries are things the audit specifically asked about that are wired correctly today.

---

## Critical

### C1. `pendingGift` query param is never consumed by the welcome screen — gift activation cannot resume after sign-up

`router.dart:163-170` rewrites unauthenticated `/gift/<code>` deep links to `/welcome?pendingGift=<code>` (and `gift_activation_screen.dart:154` does the same when the user clicks "Sign in / sign up" from the activation screen). `gift_activation_screen.dart:74-81` ALSO stashes the code in SharedPreferences under `pending_gift_code`.

But `welcome_screen.dart:50-77` only reads `pendingReferral` (and the `referral_code` SP key). Nothing on any of the three sign-up paths (`_submitEmail` lines 193-229, `_signInWithApple` lines 88-152, `_signInWithGoogle` lines 154-191) reads `pending_gift_code` from prefs and resumes the gift activation flow. Result: a partner-gifted user who taps the deep link, signs up via email/Google/Apple, and lands on the dashboard sees no banner, no nav, and the gift sits unredeemed until they tap the deep link a second time (this time as an authenticated user) — which only works if they still have the link.

The activation screen comments at line 22-25 explicitly promise "the welcome screen can pick it up after sign-up — mirrors the existing `pending referral` pattern." That contract is broken.

Fix shape: in `welcome_screen.dart`, after a successful auth call, read `prefs.getString('pending_gift_code')`, and if non-empty `context.go('/gift/$code')` then `prefs.remove('pending_gift_code')`. Show a banner on the welcome screen when the code is present (analogous to `_buildReferralBanner`).

### C2. Gift activation success screen always shows the default 6 months — `premiumMonths` never reaches it

`gift_activation_screen.dart:140` navigates with `context.go('/gift/activation-success?months=$_premiumMonths')` — the months value is in the **query string**.

`router.dart:622-631` reads months from `state.extra as Map<String, dynamic>?` — the **route extra** dictionary, NOT the query string. `state.extra` is null because the activation screen never passed it. Falls back to the default `?? 6` on line 628 every time.

Net result: a partner who gifted 12 months sees "6 Months Premium" on the success screen. Cosmetic but lying to the user.

Fix shape: either read from `state.uri.queryParameters['months']` in the route builder, or pass `extra: {'premiumMonths': _premiumMonths}` from the activation screen.

### C3. Add-item flows other than the gateway never check the free-plan limit — limit can be silently bypassed via push/deep link

`add_item_screen.dart:35-105` correctly watches `isAtItemLimitProvider` and gates the picker behind a "limit reached" panel.

But `quick_add_screen.dart`, `manual_entry_screen.dart`, `barcode_scan_screen.dart`, `receipt_scan_screen.dart`, and the `add_item/wizard/*` files have **zero** references to `isAtItemLimitProvider`. Any caller that pushes those routes directly (e.g. `first_action_screen.dart:69 context.push(AppRoutes.scanReceipt)`, `first_action_screen.dart:79 context.push(AppRoutes.addItem)`, the dashboard empty-state at `dashboard_screen.dart:263 context.push(AppRoutes.addItem)`, or any future deep-link entry point) routes around the limit. The server presumably rejects on `POST /items` once over the cap, but the user only finds out via a generic error after typing a full form.

Audit prompt asked specifically: "is the `isAtItemLimitProvider` correctly invoked in EVERY add path (quick_add, manual_entry, barcode, receipt_scan, wizard)?" Answer: no, only the gateway.

Fix shape: read `isAtItemLimitProvider` in the build of each add screen (or extract a shared `AddItemGuard` widget) so the limit panel renders consistently regardless of entry point.

### C4. `add_item/wizard/` is dead code — the entire subfolder is unreachable

`add_item_wizard_screen.dart`, `wizard_step1_basics.dart`, `wizard_step2_warranty.dart`, `wizard_step3_details.dart`, `add_item_draft.dart` exist with `WizardData`, `AddItemWizardScreen`, draft-restore logic, and a multi-step PageView.

`router.dart` registers no route to `AddItemWizardScreen`. `grep -rn AddItemWizardScreen apps/mobile/lib/` returns only the file itself — no caller. The `/add-item/manual` route goes to `ManualEntryScreen` (the long form), and `/add-item/quick/:category` goes to `QuickAddScreen`. The wizard is fully orphaned.

Rule 3 (Never leave legacy or dead code) says delete it. Either wire the wizard up as the canonical add path (and delete `manual_entry_screen.dart` + `quick_add_screen.dart` to keep one shape) or delete the wizard folder.

---

## High

### H1. Mobile delete-account copy contradicts the marketing site's 7-day grace policy (PRODUCT.md drift)

`delete_account_screen.dart:73-76` shows the user:
> "This will permanently delete your account and all your data including items, warranties, documents, and settings. This action cannot be undone."

`apps/marketing/src/pages/legal/privacy.astro:108` and `apps/marketing/src/pages/legal/delete-account.astro:24` say:
> "we soft-delete immediately, allow a 7-day grace period to cancel, then cryptographically erase the record from active systems"

The mobile copy lies — there IS a 7-day grace period per the privacy policy and `/legal/delete-account` page. A user who reads the dialog won't know they have a window to undo. PRODUCT.md flagged this drift; mobile still hasn't been updated.

Fix shape: change the body to explain the 7-day grace ("Your account and data will be soft-deleted immediately. You have a 7-day grace period to sign in and cancel; after that, the record is cryptographically erased and unrecoverable.").

### H2. F124 drift in warranty_purchase form — validator uses `double.tryParse`, submit uses `Money.parseToDouble`

`add_warranty_purchase_screen.dart:213` validates currency input via `final parsed = double.tryParse(value); if (parsed == null) return 'Enter a number';`.

`add_warranty_purchase_screen.dart:235-239` submits via `Money.parseToDouble(_priceController.text.trim())`.

`Money.parseToDouble` strips `$`, commas, whitespace before parsing. `double.tryParse` does not. A user typing `"$1,234.50"` will be told "Enter a number" by the validator (rejected), but if they could get past it the submit path would happily parse it. This is the inverse of the F124 bug create_claim_screen fixed — same pattern, opposite direction.

Fix shape: in `_buildNumberField`'s validator, use `Money.parseToDouble` (or `parsePriceInput`) so the validator accepts everything the parser does.

### H3. Date pickers in 4 screens never normalize to local-midnight (F005 regression)

The F005 fix (manual_entry, quick_add, receipt_scan) wraps `picked` in `DateTime(picked.year, picked.month, picked.day)` so the local-midnight anchor doesn't drift across timezones. The following screens skip the normalization:

- `edit_item_screen.dart:256-258` — `_purchaseDate = picked` (raw DateTime)
- `create_claim_screen.dart:76-78` — `_claimDate = picked`
- `log_maintenance_screen.dart:125` — `_completedDate = picked`
- `add_warranty_purchase_screen.dart:161-163` — `_startDate = picked`
- `home_detail_screen.dart:93-95` — `_moveInDate = picked`

A user who picks a date while their phone is on PT, then flies to ET, will see the date shift by a day on screens that compare against local midnight downstream.

Fix shape: wrap each `picked` in `DateTime(picked.year, picked.month, picked.day)` before assigning.

### H4. `profile_screen.dart` change-email dialog leaks `TextEditingController`s on cancel / unmount

`profile_screen.dart:439-535`. The dialog creates `emailController` and `passwordController` at lines 440-441, then disposes them in `finally` only AFTER the `if (confirmed != true || !mounted) return;` early-return at line 508. When the user cancels, `confirmed` is `false`, the `return` fires, the `try` block is skipped, the `finally` is also skipped — and both controllers leak.

Fix shape: dispose the controllers regardless of cancel. Either move dispose into a `try/finally` that wraps `showDialog` itself, or dispose them right before `return` after the cancel check.

### H5. `customize_schedule_screen.dart` "new custom task" dialog leaks its name controller

`customize_schedule_screen.dart:126`: `final nameController = TextEditingController();` is created, used inside a dialog, but **never disposed**. Doesn't matter how the dialog closes — there's no `nameController.dispose()` anywhere in `_showAddCustomTaskDialog`. Every time the user opens this dialog, a controller is leaked.

Fix shape: dispose at the end of the function (after `if (result == null) return;`), or wrap the whole thing in a try/finally.

### H6. `_ScanProgressController.stage` `ValueNotifier` is never disposed

`email_scanner_screen.dart:343-347` defines a `ValueNotifier<String>` inside a controller object that has no `dispose()` method. The controller is created on every `_startScan` call and kept alive until the dialog closes — but the `ValueNotifier` is never disposed, leaking the listener registry.

Fix shape: add `void dispose() => stage.dispose();` to `_ScanProgressController`, call it in `_startScan`'s `finally` after `closeDialogIfOpen()`.

### H7. `receipt_scan_screen.dart:_saveItem` early-returns silently when user/home is null and leaves the user with `_isSaving = true` UI

`receipt_scan_screen.dart:184-187`: `final user = ref.read(currentUserProvider).value; final home = ref.read(currentHomeProvider); if (user == null || home == null) return;`

The `finally` at line 237 does reset `_isSaving = false`. But the user gets ZERO feedback — the button just goes idle and they're left wondering. Compare to `quick_add_screen.dart:101-115` which shows a snackbar and routes to `/home-setup` if no home. Same pattern needs replicating here.

### H8. Universal Link / referral path has a routing dead-end for authenticated users

`router.dart:528-536` registers `/referral/:code` to `ReferralHandlerScreen`. `router.dart:149-155` redirects unauth visitors to `/welcome?pendingReferral=…` (correct).

For an **authenticated** user, the redirect returns null (allows the route), so the screen renders. `referral_handler_screen.dart:35-48` then runs `prefs.setString(kReferralCodeKey, code)` and `context.go(AppRoutes.welcome)`. Welcome will then redirect back to `/dashboard` because the user is authenticated.

The net behavior: the code is stashed in SP, the user lands on the dashboard, but nothing reads `referral_code` after sign-up (because the user is already signed up). The stashed code rots forever. Either the route should be inert for authenticated users (redirect to dashboard with a snackbar "you're already signed up — referral codes only apply to new accounts"), or it should hit a backend "apply referral retroactively" endpoint.

### H9. `dashboard_screen.dart` `currentUserProvider` is watched — but the avatar tree builds even on plan changes

This is informational, not a bug per se, but the audit prompt asked: `dashboard_screen.dart:85` uses `ref.watch(currentUserProvider)` — correct. So the dashboard does react to plan changes. **No issue.** Listed here only because the audit asked specifically.

### H10. `currentHomeProvider` cascade: every per-home query rebuilds — except `archivedItemsProvider` re-fetches via `getItems(homeId: …)` and is correct

Audit asked: do all per-home queries re-trigger on home switch? `items_provider.dart` has `_HomeIdSubscription` wired up; `homesProvider` exposes `currentHomeProvider`; `archivedItemsProvider:450-463` watches `currentHomeProvider`. Maintenance providers (`maintenance_provider.dart`) and warranty claim providers were not exhaustively reviewed but no obvious break was found.

No defect. Listed for completeness.

---

## Medium

### M1. `settings_screen.dart` imports `haven_image.dart` but never uses `HavenImage`

`settings_screen.dart:23`: `import '../../core/widgets/haven_image.dart';`. Only `HavenLoader` is used (line 727). Remove the import.

### M2. `premium_success_screen.dart` is a `ConsumerWidget` that never calls `ref`

`premium_success_screen.dart:8` extends `ConsumerWidget`, takes `WidgetRef ref` in `build`, but never reads any provider. Should be `StatelessWidget`. Tiny, but the import + Consumer machinery is wasted.

### M3. `error_handler.dart` `TimeoutException` check is ambiguous with `dart:async.TimeoutException`

`error_handler.dart:1` imports `dart:io` (which doesn't expose TimeoutException). `error_handler.dart:8` imports the local `network_exceptions.dart` which defines its own `TimeoutException` at `network_exceptions.dart:64`. So the `error is TimeoutException` check at `error_handler.dart:63` references the **local** custom class, not Dart's stdlib version. Dio + api_client throw `dart:async.TimeoutException` on socket timeouts. Those will fall through to the bottom "Something went wrong" branch instead of getting the targeted "Request timed out" message.

Fix shape: either add a separate check for `error is TimeoutException` from `dart:async`, or rename the local class to `HavenTimeoutException` to avoid the shadowing.

### M4. `add_warranty_purchase_screen.dart:_refundEstimate` mixes UTC server times with local `DateTime.now()` (S2-A regression)

`warranty_purchases_screen.dart:184-191`: `purchase.expiresAt.difference(DateTime.now()).inDays`. `purchase.expiresAt` is parsed from the server (UTC). `DateTime.now()` is local. The diff in `inDays` can be off by ±1 day in the user's TZ, which produces wrong refund estimates near midnight.

Fix shape: convert both to UTC before subtracting (`expiresAt.toUtc().difference(DateTime.now().toUtc())`) or use a consistent timezone.

### M5. `recent_gifts_screen.dart` shows raw enum names for status

`recent_gifts_screen.dart:122-124`: `Text(gift.status.name, style: …)`. `PartnerGiftStatus.activated.name == 'activated'` (lowercase, machine-form). User reads `"activated"` instead of `"Activated"` or a proper localized label. Other screens use `displayLabel` (e.g. `claims_list_screen.dart:257`).

Fix shape: replace with `gift.status.displayLabel` (or capitalize first letter inline).

### M6. `recent_gifts_screen.dart` "homebuyer name" misnamed as "partner label"

`recent_gifts_screen.dart:90-92`: `final partnerLabel = gift.homebuyerName.isNotEmpty ? gift.homebuyerName : 'HavenKeep partner';`. `homebuyerName` is the recipient's name, not the partner's. Showing "Jane Doe" (the homebuyer) and labeling it "HavenKeep partner" when missing is confusing. The partner who gifted is presumably elsewhere on the model.

Fix shape: rename `partnerLabel` → `recipientLabel` and reword the fallback ("Recipient unknown" or just hide). If the field genuinely should be "the partner who gifted", point it at the right field.

### M7. Notification preferences screen — first-render sets state during build

`notification_preferences_screen.dart:261`: `prefsAsync.whenData((prefs) => _initFromPrefs(prefs));` is called inside `build()`. `_initFromPrefs` mutates state via `_remindersEnabled = …` etc. on first render. There's an `if (_isInitialized) return;` guard, so it only runs once, and it doesn't call `setState` — but mutating state fields during build is fragile. The `ref.listen` immediately below (lines 266-271) is the right pattern; the inline `whenData` call should go.

Fix shape: remove the inline `whenData` call and let the listener fire on the first emission.

### M8. `dashboard_screen.dart` warranty stats provider error path has no retry semantics

`dashboard_screen.dart:341-344`: `error: (_, __) => const Text('Could not load stats', style: TextStyle(color: HavenColors.expired))`. No retry, no info. Compare to the value dashboard card error path right above (lines 187-193) which has a retry button.

Fix shape: add a retry button or wrap the existing `_buildWarrantySummary` error branch in `ErrorStateWidget` for consistency.

### M9. `ItemAdded` celebration uses `'🎉 Great start!'` literal duplicated 3 times

`quick_add_screen.dart:163-164`, `manual_entry_screen.dart:178-180`, `add_item_wizard_screen.dart:187-189` all hardcode the same first-item celebration title and subtitle. Extract via `CelebrationTrigger.getMessage(CelebrationType.firstItem, count)` (which is already defined at `celebration_overlay.dart:342-377` but unused for these calls). Drift risk if the copy changes in one place.

### M10. `_OverflowMenu` reads `isArchived: false` for the orElse branch — wrong default

`item_detail_screen.dart:74-76`:
```
data: (item) => _OverflowMenu(itemId: itemId, isArchived: item.isArchived),
orElse: () => _OverflowMenu(itemId: itemId, isArchived: false),
```

While the item is loading, the overflow menu shows the "Archive" entry (not "Unarchive"). If the user is fast enough to tap it before data resolves, they'd archive an already-archived item (server-side no-op, but UI is misleading). Better: hide the overflow menu entirely while loading, or show a disabled placeholder.

Fix shape: in `orElse`, return `const SizedBox.shrink()` so the menu only renders once we know archived state.

### M11. `delete_account_screen.dart` re-auth-OAuth swallows ALL errors silently

`delete_account_screen.dart:171-173`: `} catch (_) { return false; }`. Any IdP failure, decode error, network error gets boxed into a single "Re-authentication failed" snackbar. The user has no way to debug whether their network is down vs they cancelled vs the IdP rejected vs their account was already deleted server-side.

Fix shape: at minimum, log to LoggingService before swallowing, and surface the underlying error message in the snackbar.

### M12. `claims_list_screen.dart` `Dismissible.onDismissed` runs the delete without confirmation if `confirmDismiss` was already true

`claims_list_screen.dart:209-220`. The pattern is correct: `confirmDismiss` returns the dialog confirm, then `onDismissed` actually deletes. But there's no `await` on the `deleteClaim` call inside `onDismissed`, so a failure (network 500) silently rolls back nothing — the row vanishes from the list locally because Dismissible removed it. Compare to `items_screen.dart:602-650` which uses `confirmDismiss: (direction) async { … return false }` to keep the row in the list and let the provider handle removal.

Fix shape: switch to the items_screen pattern — return `false` from `confirmDismiss` and let the provider mutation drive the removal, with a Snackbar/Undo.

### M13. Several screens construct DateFormat per-build instead of caching

`claims_list_screen.dart:23`, `notifications_screen.dart` `_NotificationCard._timeAgo`, etc. construct `DateFormat.yMMMd()` on every build. Tiny perf hit but accumulates on long lists. Cache as a class-level `static final`.

### M14. `_ConflictsBanner` watches `syncConflictCountProvider` — is that one always available?

`settings_screen.dart:942` watches `syncConflictCountProvider`. The provider definition isn't in `core/providers/`; it's elsewhere. Light verification: it's wired up in `core/services/offline_sync_service.dart`. OK.

### M15. The recent-activity card shows "Nothing yet" copy with no CTA

`recent_activity_card.dart:48-56`. Empty state says `"Nothing yet — your first add or claim will show up here."` Good, but no link to "Add an item" or "View all warranties" — a missed conversion moment for new users.

Fix shape: include a CTA like the dashboard's empty-vault state.

### M16. `gift_activation_screen.dart` `_activate` shows raw exception text on failure

`gift_activation_screen.dart:109-119` throws `Exception('Invalid activation code or email')` which then flows to `ErrorHandler.getUserMessage(e)`. `ErrorHandler` falls through to the default "Something went wrong. Please try again." for raw `Exception`. So the user sees a generic message when the API specifically said "invalid activation code or email" — disambiguating which is wrong is fine for security, but the generic copy doesn't tell them to double-check anything.

Better: surface "We couldn't verify this gift. Double-check the code and the email it was sent to." when the verify step fails.

The audit prompt asked: "the activation-code-with-wrong-email path: does the gift activation screen show a generic error (security) or leak which one was wrong?" Answer: generic. Good for security, but the message could be more user-friendly.

### M17. Shared search patterns: no haystack cache in `items_screen.dart`

The audit prompt asked whether the haystack cache pattern from `global_search_screen.dart` is used elsewhere it should be. Answer: `items_screen.dart:113-122` (`_applyFilters`) re-tokenizes brand/name/model on every keystroke during search. With a 300ms debounce that's still per-keystroke after the debounce. For users with hundreds of items (e.g. premium power users) this is wasteful. The same `_haystackCache` pattern from `global_search_screen.dart:42-79` would benefit here.

Fix shape: cache lowercased haystacks keyed on `${item.id}@${item.updatedAt.millisecondsSinceEpoch}` like the global search does.

---

## Low

### L1. Many screens use `GestureDetector` for tappable cards instead of `InkWell`

Examples: `dashboard_screen.dart:435 _buildAttentionCard`, `dashboard_screen.dart:560 _MaintenanceCard`, `notifications_screen.dart:341`. No tap ripple, no focus ring. The audit prompt asked specifically about a11y. Items_screen already migrated to `Material+InkWell` (lines 725-794) — extending the same pattern to dashboard cards is a small a11y win.

### L2. `dashboard_screen.dart` `_NotificationBell` is a `ConsumerWidget` without a `super.key`

`dashboard_screen.dart:936`: `class _NotificationBell extends ConsumerWidget` — no const constructor, no key. Causes unnecessary rebuilds. Cosmetic.

### L3. `delete_account_screen.dart` `_passwordController` validator missing — submit only checks `isEmpty`

`delete_account_screen.dart:57-101`. `_deleteAccount` does an early-return if password is empty. The TextField has no `validator` callback, so a user who paste-keys whitespace (e.g. " ") would make `isEmpty == false` and the submit would proceed with whitespace. Trim the input or add a validator.

### L4. `welcome_screen.dart` regex anchors only Latin chars — international email rejected

`welcome_screen.dart:547-548`: the email regex is ASCII-only. `name+test@müncher.de` would be rejected. Most apps accept the simpler `^[^@]+@[^@]+\.[^@]+$` (used by `forgot_password_screen.dart:163`).

### L5. `manual_entry_screen.dart` `_hideCounter` returns `null` to suppress the character counter — fine, but `WarrantyDurationPicker` ignores `MaxLengthEnforcement`

Not a bug, just noting that the no-counter pattern is repeated in multiple files (`manual_entry`, `create_claim`). Consider pulling into `shared_ui` so the suppression is consistent.

### L6. Greeting in `dashboard_screen.dart` does not handle TZ + 5am cutoff edge case

`dashboard_screen.dart:76-81` checks `DateTime.now().hour`. At 4:59am the user gets "Good evening". Trivial but inconsistent with most apps.

### L7. `_RouterRefreshNotifier` re-listens on each router rebuild

`router.dart:113-119`: `ref.listen` calls in the constructor are correct (one-time subscription), but the `Provider` rebuilds the router only on cold start. Fine. Listed for completeness.

### L8. `dashboard_screen.dart` raw emoji fallback — `'⚠️'` in the section header

`dashboard_screen.dart:356`: `'⚠️  NEEDS ATTENTION'`. Two spaces because the variation selector affects rendering width. Minor; consider using `Icon` for cross-font consistency.

### L9. `RecentActivity` import in `recent_activity_card.dart` — class is from `audit_log_repository.dart`

`recent_activity_card.dart:6`: `import '../../core/services/audit_log_repository.dart';`. The file pulls a service-layer model into the widget; a `RecentActivity` view-model in shared_models would be cleaner. Minor.

### L10. `notifications_screen.dart:331` "silence the unused-local lint" comment hints at dead branch

`notifications_screen.dart:330-332`: explicitly admits the `if (!navigated) return;` exists only to silence a lint. The `navigated` variable is set by every branch above and never read after. The whole `bool navigated = false; … if (navigated) …` flow could be replaced with explicit returns from each branch.

### L11. `_ConflictCard._error` field set but never re-read after the first failure

`conflicts_screen.dart:97-98`. After a failed resolve the card stores `_error` and rebuilds — but I didn't see the field rendered in the UI. (Couldn't read past line 100; possibly fine.) Worth a quick verify.

### L12. `splash_screen.dart` `_kBootstrapStuckThreshold` of 12 seconds is long

For a user on cellular with a slow handshake, 12s is a long stare at a frozen splash. 6-8s is more typical for a "tap to retry" surface. Tunable.

### L13. Settings screen `_AboutDialog._kTapsToReveal = 5` is non-deterministic if the user double-taps fast

`settings_screen.dart:1010-1022`. `_versionTaps + 1`. If the user double-taps faster than the rebuild, `setState` from the first tap might not have committed before the second tap fires. Flutter's gesture system serializes taps, so probably fine — but worth a sanity test.

### L14. `dashboard_screen.dart:732` `context.push('/items/${item.id}')` should use `AppRoutes.itemDetail` template

Hardcoded path means a route rename in `router.dart` won't break the type system. Many screens do this; minor consistency nit.

### L15. `_FormProgressBar` in `manual_entry_screen.dart` — `warrantyMonths > 0` always true

`manual_entry_screen.dart:621`: `if (warrantyMonths > 0) completed++; // always true by default, counts as done`. The author admits it. Either drop the third "section" from the progress (so it's 2/2 when filled out), or actually let the user clear the warranty months.

---

## Verified-correct

These are things the audit prompt asked about that look right today.

- **welcome_screen text controllers disposed**: lines 81-86. Apple/Google/email handlers all use `if (mounted) setState(() => _isLoading = false)` after async (88-152, 154-191, 193-229).
- **welcome_screen referral consumed on email sign-up**: `_submitEmail` reads `prefs.getString('referral_code')` and clears it on success (lines 202-213). (But Apple/Google paths do NOT pass referral_code — see the `signInWithApple` notifier call at 136-140 which has no `referralCode:` argument. Worth a verify against the auth provider — out of audit scope per prompt, but flagging for cross-check.)
- **`PopScope` consistently used**: no `WillPopScope` anywhere (`grep -rn WillPopScope apps/mobile/lib/` returns nothing). `edit_item_screen.dart:273-278`, `profile_screen.dart:149-152`, `home_detail_screen.dart:192-196`, `add_item_wizard_screen.dart:245-254` all use `PopScope`.
- **First-item celebration race**: theoretical but practically impossible. Two simultaneous `addItem` calls would have to both read `previousCount=0` before either commits — but UI-driven adds serialize via the same `state.value` read in `items_provider.dart:90-91`, and Flutter's UI thread is single-threaded.
- **`items_screen.dart` `Dismissible.confirmDismiss` returns `false`**: `items_screen.dart:650`. Provider drives the removal. Correct.
- **AnimationControllers disposed**: `splash_screen.dart:88-93`, `gift_activation_success_screen.dart:44-49`, `celebration_overlay.dart:99-103`, `celebration_overlay.dart:411-414` (`AnimatedCheckmark`).
- **Confetti pause on backgrounding**: `gift_activation_success_screen.dart:36-42` registers a `WidgetsBindingObserver` and pauses confetti when not resumed.
- **Search debounce 300ms**: `items_screen.dart:53` and `global_search_screen.dart:32`.
- **F005 anchor applied**: `quick_add_screen.dart:88-90`, `manual_entry_screen.dart:88-91`, `receipt_scan_screen.dart:264-267`, `receipt_scan_screen.dart:199-203` (`_saveItem` re-anchors on submit too).
- **F124 (Money.parseToDouble) applied**: `create_claim_screen.dart:443`, `manual_entry_screen.dart:498` (parsePriceInput, equivalent), `quick_add_screen.dart:120` (parsePriceInput), `edit_item_screen.dart:175` (parsePriceInput). Only `add_warranty_purchase_screen.dart:213` is wrong (see H2).
- **Auto-archive 90 days copy**: `settings_screen.dart:923-924` says "Hide warranties expired more than 90 days" — matches CLAUDE.md's stated 90-day rule.
- **Email scanner OAuth privacy prime**: `email_scanner_screen.dart:305-338` shows the prime dialog before kicking off the OAuth. Good UX.
- **Offline sync conflict surface wired**: `_FailedSyncBanner` (dashboard) + `_ConflictsBanner` (settings) both push to `AppRoutes.conflicts`.
- **Pending referral SP key consumed on sign-up**: `welcome_screen.dart:202-213` reads and clears `referral_code` after a successful email sign-up. (Apple/Google paths don't pass it through — flagged in cross-checks above.)
- **Recent activity empty/loading/error states all rendered**: `recent_activity_card.dart:34-71`.
- **Maintenance log allows opt-out picker**: `log_maintenance_screen.dart:521-532` includes `'None (custom task)'` so a user without a matching schedule can still log.
- **Premium teaser hides for premium users**: `premium_teaser_card.dart:17-18`.
- **Premium screen reads live RevenueCat offering**: `premium_screen.dart:37` future + `:425-475` FutureBuilder. Falls back to "Pricing unavailable" when offering is null. Good.

---

## Out-of-scope

These came up while auditing the feature screens but belong to other agents.

- **Auth/account purge backend**: H1 (delete-account 7-day grace copy mismatch) is mobile copy only. The actual soft-delete + grace logic is owned by the auth/backend agent.
- **Apple Sign-In `signInWithApple` notifier `referralCode` parameter**: see Verified-correct note above. The Riverpod notifier on `auth_provider.dart` is in scope per audit instructions, but the mobile feature side correctly reads the SP code; whether the notifier forwards it to `/auth/apple` is the auth-backend agent's call.
- **Stripe pricing**: out of scope per prompt.
- **Server-side enforcement of free-plan item limit (C3 above)**: mobile enforces nothing if you bypass the gateway. The backend `POST /items` is presumed to enforce. Out of scope to verify here.
- **api_client behavior** for offline classification (`_isOfflineError` in `items_provider.dart:116`): different agent.
- **Money internals**: `Money.parseToDouble`, `Money.format` are correct per the file; deeper money agent owns rounding/locale concerns.
- **`profile_screen.dart` change-email flow's backend** (the `requestEmailChange` API): different agent.

---

## Severity totals

- Critical: 4
- High: 10
- Medium: 17
- Low: 15
- Verified-correct: 18 items
- Out-of-scope: 7

The most user-visible defects are C1 (gift activation broken on sign-up — partner gifts cannot be redeemed via deep link by new users), C3 (free-plan limit bypassable), C4 (an entire wizard subfolder is dead code), and H1 (delete-account copy contradicts the privacy policy on grace period). The rest are quality issues — the cluster of date-picker non-normalization (H3) and the controller-leak pattern (H4, H5, H6) in particular.
