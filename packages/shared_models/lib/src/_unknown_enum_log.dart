// Audit Ch08-D018: shared funnel for unknown-enum drift.
//
// The mobile app handles enum coercion deliberately — when the server emits a
// value the client's enum doesn't recognise (e.g. a new partner_type added in
// a backend deploy that the mobile binary hasn't picked up yet), we coerce to
// a safe default so the UI doesn't blow up. But the drift is a real signal
// the team should chase, so every coercion goes through this funnel.
//
// `dart:developer` `log` hits the platform's native log surface (Logcat on
// Android, OSLog on iOS, console.log on web). On the server side these enum
// drifts surface in Loki via pino. The bootstrap can also register a
// `UnknownEnumReporter` to forward to whatever transport the deploy uses
// (Firebase Crashlytics breadcrumb, custom HTTP collector, etc.) without
// `_unknown_enum_log` having to import any specific telemetry SDK.

import 'dart:developer' as developer;

typedef UnknownEnumReporter = void Function(String enumName, String unknownValue, String fallback);

UnknownEnumReporter? _externalReporter;

/// Bootstrap registers a custom reporter (e.g. Firebase Crashlytics
/// breadcrumb) here at app start.  Optional — `dart:developer.log` is the
/// always-on transport.
void registerUnknownEnumReporter(UnknownEnumReporter reporter) {
  _externalReporter = reporter;
}

void logUnknownEnumValue({
  required String enumName,
  required String unknownValue,
  required String fallback,
}) {
  developer.log(
    'Unknown $enumName value "$unknownValue" — coerced to $fallback',
    name: 'shared_models.enum',
  );
  final reporter = _externalReporter;
  if (reporter != null) {
    try {
      reporter(enumName, unknownValue, fallback);
    } catch (_) {
      // Reporter must never throw back into the model layer.
    }
  }
}

/// H56: one-liner factory helper for every fromJson(String).
///
/// Looks up [byName] for the raw server string. On hit, returns the
/// mapped enum value cleanly. On miss, fires the unknown-enum funnel
/// so the drift shows up in platform logs (and any registered
/// reporter), then returns [fallback].
///
/// Use it instead of the older `firstWhere(orElse:)` pattern — that
/// shape silently coerced unknown values with no telemetry, so a
/// server-added enum value would land on older mobile binaries and
/// nobody would know until users started reporting bugs.
T coerceEnum<T>({
  required String enumName,
  required String rawValue,
  required Map<String, T> byName,
  required T fallback,
  required String fallbackName,
}) {
  final mapped = byName[rawValue];
  if (mapped != null) return mapped;
  logUnknownEnumValue(
    enumName: enumName,
    unknownValue: rawValue,
    fallback: fallbackName,
  );
  return fallback;
}

/// H56: less-boilerplate variant for enums whose JSON encoding is
/// just `.name`. Walks the values list once instead of requiring
/// callers to maintain a static `_byName` map. Identical observable
/// behaviour to [coerceEnum] otherwise.
T coerceEnumByName<T extends Enum>({
  required String enumName,
  required String rawValue,
  required List<T> values,
  required T fallback,
}) {
  for (final v in values) {
    if (v.name == rawValue) return v;
  }
  logUnknownEnumValue(
    enumName: enumName,
    unknownValue: rawValue,
    fallback: fallback.name,
  );
  return fallback;
}
