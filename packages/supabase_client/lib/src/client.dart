import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides the initialized Supabase client.
///
/// Supabase must be initialized in main.dart before this provider is used:
/// ```dart
/// await Supabase.initialize(url: '...', anonKey: '...');
/// ```
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Returns the current authenticated user's ID, or null if not logged in.
String? getCurrentUserId() {
  return Supabase.instance.client.auth.currentUser?.id;
}

/// Returns the current authenticated user's ID.
/// Throws [StateError] if not logged in.
String requireCurrentUserId() {
  final id = getCurrentUserId();
  if (id == null) {
    throw StateError('User is not authenticated');
  }
  return id;
}
