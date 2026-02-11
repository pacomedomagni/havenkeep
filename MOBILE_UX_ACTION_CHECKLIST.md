# Mobile UX - Immediate Action Checklist

Quick reference for implementing the critical UX improvements identified in the audit.

## 🔴 CRITICAL (Before Launch)

### 1. Accessibility Implementation (2 weeks)

- [ ] **Add Semantics to ItemCard**
  ```dart
  Semantics(
    button: true,
    label: '${item.brand} ${item.name}, Warranty ${_warrantyStatus(item)}',
    hint: 'Double tap to view details',
    onTap: () => _navigateToDetail(item.id),
    child: ItemCard(...),
  )
  ```

- [ ] **Add Semantics to ValueDashboardCard**
  ```dart
  Semantics(
    label: 'Total value protected: ${_formatValue(totalValue)}. Warranty health: $healthPercentage%. ${_healthMessage()}',
    child: ValueDashboardCard(...),
  )
  ```

- [ ] **Add alt text to avatar images**
  ```dart
  Semantics(
    label: '${user.fullName} profile picture',
    child: CircleAvatar(backgroundImage: NetworkImage(user.avatarUrl)),
  )
  ```

- [ ] **Test with VoiceOver (iOS)**
  - Settings → Accessibility → VoiceOver → Enable
  - Navigate through: Dashboard, Items, Add Item, Item Detail
  - Verify all interactive elements are announced
  - Check reading order makes sense

- [ ] **Test with TalkBack (Android)**
  - Settings → Accessibility → TalkBack → Enable
  - Test same flows as iOS
  - Verify focus order and announcements

- [ ] **Validate contrast ratios**
  - Check HavenColors.textPrimary on HavenColors.surface (need 4.5:1)
  - Check HavenColors.textSecondary on HavenColors.surface
  - Check status colors (active green, expiring amber, expired red)
  - Use: https://webaim.org/resources/contrastchecker/

- [ ] **Test text scaling**
  - iOS: Settings → Accessibility → Display & Text Size → Larger Text → Max
  - Android: Settings → Display → Font size → Largest
  - Verify layouts don't break, text doesn't overflow

### 2. API Timeout Configuration (2 days)

- [ ] **Add timeouts to ApiClient**
  ```dart
  // packages/api_client/lib/src/api_client.dart

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // In _makeRequest:
  try {
    final response = await _dio.request(
      endpoint,
      options: Options(
        method: method,
        headers: headers,
        sendTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      ),
    );
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionTimeout) {
      throw TimeoutException('Connection timeout');
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      throw TimeoutException('Request timeout');
    }
    rethrow;
  }
  ```

### 3. Error Message Cleanup (3 days)

- [ ] **Create ErrorMessages class**
  ```dart
  // apps/mobile/lib/core/utils/error_messages.dart

  class ErrorMessages {
    static const network = 'Connection lost. Check your internet and try again.';
    static const timeout = 'Request took too long. Please try again.';
    static const serverError = 'Server error. Please try again later.';
    static const unauthorized = 'Session expired. Please log in again.';
    static const notFound = 'Item not found.';
    static const unknown = 'Something went wrong. Please try again.';

    static String fromException(Exception e) {
      if (e is SocketException) return network;
      if (e is TimeoutException) return timeout;
      if (e is HttpException) {
        if (e.message.contains('401')) return unauthorized;
        if (e.message.contains('404')) return notFound;
        if (e.message.contains('5')) return serverError;
      }
      return unknown;
    }
  }
  ```

- [ ] **Replace raw error strings** in:
  - `items_provider.dart` (all catch blocks)
  - `auth_provider.dart` (all catch blocks)
  - `homes_provider.dart` (all catch blocks)
  - `add_item_screen.dart` (form submission)
  - `edit_item_screen.dart` (form submission)

- [ ] **Update ErrorStateWidget**
  ```dart
  // Use ErrorMessages.fromException instead of error.toString()
  Text(
    ErrorMessages.fromException(error as Exception),
    style: TextStyle(color: HavenColors.error),
  )
  ```

### 4. Premium Flow Completion (1 week)

- [ ] **Remove mock Premium features**
  - Remove `MockSubscriptionService` stub
  - Implement real Stripe integration
  - Test subscription purchase flow
  - Test subscription cancellation
  - Test subscription restoration

- [ ] **Update PremiumBanner**
  - Link to real subscription screen
  - Show actual pricing
  - Handle payment errors

## 🟠 HIGH PRIORITY (Week 2-3)

### 5. Form Validation Improvements (2 days)

- [ ] **Strengthen email validation**
  ```dart
  // apps/mobile/lib/core/utils/validators.dart

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    );
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }
  ```

- [ ] **Add password strength indicator**
  ```dart
  // apps/mobile/lib/features/auth/widgets/password_strength_indicator.dart

  class PasswordStrengthIndicator extends StatelessWidget {
    final String password;

    PasswordStrength _calculateStrength(String pwd) {
      if (pwd.length < 8) return PasswordStrength.weak;

      int score = 0;
      if (pwd.contains(RegExp(r'[A-Z]'))) score++;
      if (pwd.contains(RegExp(r'[a-z]'))) score++;
      if (pwd.contains(RegExp(r'[0-9]'))) score++;
      if (pwd.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;
      if (pwd.length >= 12) score++;

      if (score <= 2) return PasswordStrength.weak;
      if (score == 3) return PasswordStrength.medium;
      return PasswordStrength.strong;
    }

    @override
    Widget build(BuildContext context) {
      final strength = _calculateStrength(password);
      return Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: strength.value,
              color: strength.color,
              backgroundColor: HavenColors.surface,
            ),
          ),
          SizedBox(width: HavenSpacing.sm),
          Text(strength.label, style: TextStyle(color: strength.color)),
        ],
      );
    }
  }
  ```

### 6. Hide Disabled Features (1 day)

- [ ] **Add feature flags**
  ```dart
  // apps/mobile/lib/core/config/feature_flags.dart

  class FeatureFlags {
    static const bool receiptScanningEnabled = false; // TODO: Phase 1.3
    static const bool barcodeSearchEnabled = true;
    static const bool bulkOperationsEnabled = false;
  }
  ```

- [ ] **Update AddItemScreen**
  ```dart
  // Only show enabled options
  children: [
    _buildQuickAddTile(),
    if (FeatureFlags.receiptScanningEnabled) _buildScanReceiptTile(),
    if (FeatureFlags.barcodeSearchEnabled) _buildBarcodeTile(),
    _buildManualEntryTile(),
  ],
  ```

### 7. Retry with Exponential Backoff (1 day)

- [ ] **Create RetryHelper**
  ```dart
  // apps/mobile/lib/core/utils/retry_helper.dart

  class RetryHelper {
    static Future<T> retryWithBackoff<T>(
      Future<T> Function() operation, {
      int maxAttempts = 3,
      Duration initialDelay = const Duration(seconds: 1),
    }) async {
      int attempt = 0;

      while (attempt < maxAttempts) {
        try {
          return await operation();
        } catch (e) {
          attempt++;
          if (attempt >= maxAttempts) rethrow;

          final delay = initialDelay * pow(2, attempt - 1);
          await Future.delayed(delay);
        }
      }

      throw Exception('Max retries exceeded');
    }
  }
  ```

- [ ] **Use in critical operations**
  ```dart
  // In ItemsProvider.addItem
  final item = await RetryHelper.retryWithBackoff(
    () => _apiClient.post('/items', body: data),
    maxAttempts: 3,
  );
  ```

## 🟡 MEDIUM PRIORITY (Week 3-4)

### 8. Skeleton Loaders (1 day)

- [ ] **Create ShimmerItemCard**
  ```dart
  // apps/mobile/lib/core/widgets/shimmer_item_card.dart

  class ShimmerItemCard extends StatelessWidget {
    @override
    Widget build(BuildContext context) {
      return Shimmer.fromColors(
        baseColor: HavenColors.surface,
        highlightColor: HavenColors.elevated,
        child: Container(
          height: 100,
          margin: EdgeInsets.symmetric(
            horizontal: HavenSpacing.md,
            vertical: HavenSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.card),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Use in ItemsScreen while loading**
  ```dart
  itemsAsync.when(
    data: (items) => ItemsList(items),
    loading: () => ListView.builder(
      itemCount: 3,
      itemBuilder: (_, __) => ShimmerItemCard(),
    ),
    error: (err, st) => ErrorStateWidget(err),
  )
  ```

### 9. Sync Queue Visibility (2 days)

- [ ] **Create SyncStatusBanner**
  ```dart
  // apps/mobile/lib/core/widgets/sync_status_banner.dart

  class SyncStatusBanner extends ConsumerWidget {
    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final queueCount = ref.watch(offlineQueueCountProvider);

      if (queueCount == 0) return SizedBox.shrink();

      return Container(
        padding: EdgeInsets.all(HavenSpacing.sm),
        color: HavenColors.primary.withOpacity(0.1),
        child: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: HavenSpacing.sm),
            Text('Syncing $queueCount items...'),
          ],
        ),
      );
    }
  }
  ```

- [ ] **Add to MainScaffold**
  ```dart
  Column(
    children: [
      SyncStatusBanner(),
      Expanded(child: body),
    ],
  )
  ```

### 10. Themed Error Colors (1 day)

- [ ] **Add error colors to HavenColors**
  ```dart
  // apps/mobile/lib/core/theme/haven_colors.dart

  class HavenColors {
    // Existing colors...

    // Error colors
    static const error = Color(0xFFE57373);
    static const errorContainer = Color(0xFF93000A);
    static const onError = Color(0xFFFFFFFF);
  }
  ```

- [ ] **Update ErrorStateWidget**
  ```dart
  Container(
    decoration: BoxDecoration(
      color: HavenColors.errorContainer.withOpacity(0.1),
      borderRadius: BorderRadius.circular(HavenRadius.card),
    ),
    child: Column(
      children: [
        Icon(Icons.error_outline, color: HavenColors.error, size: 48),
        Text(message, style: TextStyle(color: HavenColors.error)),
      ],
    ),
  )
  ```

---

## Testing Checklist

Before marking complete, test:

### Accessibility
- [ ] VoiceOver navigation (iOS)
- [ ] TalkBack navigation (Android)
- [ ] Text scaling (200%)
- [ ] High contrast mode
- [ ] Voice control (iOS)

### Error Handling
- [ ] Airplane mode (offline)
- [ ] Slow network (throttle to 3G)
- [ ] Server timeout (kill API server)
- [ ] Invalid credentials (login)
- [ ] Form validation errors

### Edge Cases
- [ ] Empty states (no items, no homes)
- [ ] First-time user flow
- [ ] Premium limit reached (20 items)
- [ ] Long item names (truncation)
- [ ] Very old warranties (expired years ago)
- [ ] Future purchase dates (validation)

---

## Quick Wins (Can do today)

1. **Add timeout config** (30 min)
2. **Hide disabled features** (1 hour)
3. **Strengthen email validation** (15 min)
4. **Fix celebration card background** (5 min)
5. **Add error colors to theme** (15 min)

Total: ~2 hours for immediate visible improvements!

---

**Status:** Ready to implement
**Owner:** Mobile team
**Timeline:** 3-4 weeks for full completion
**Blocking Launch:** Items marked 🔴 CRITICAL
