// Haptic helpers moved to packages/shared_ui so widgets in the design
// system can fire haptics without importing back into the app layer.
// This file re-exports the canonical implementation so existing imports
// continue to work.
export 'package:shared_ui/shared_ui.dart' show HavenHaptics;
