import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Default Firebase configuration for HavenKeep.
///
/// Loads all credentials from environment variables (.env) at runtime.
/// Firebase is optional — if no API key is configured, initialization
/// is skipped in main.dart.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions is not configured for '
          '${defaultTargetPlatform.name}.',
        );
    }
  }

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: dotenv.get('FIREBASE_ANDROID_API_KEY', fallback: ''),
    appId: dotenv.get('FIREBASE_ANDROID_APP_ID', fallback: ''),
    messagingSenderId: dotenv.get('FIREBASE_MESSAGING_SENDER_ID', fallback: ''),
    projectId: dotenv.get('FIREBASE_PROJECT_ID', fallback: ''),
    storageBucket: dotenv.get('FIREBASE_STORAGE_BUCKET', fallback: ''),
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: dotenv.get('FIREBASE_IOS_API_KEY', fallback: ''),
    appId: dotenv.get('FIREBASE_IOS_APP_ID', fallback: ''),
    messagingSenderId: dotenv.get('FIREBASE_MESSAGING_SENDER_ID', fallback: ''),
    projectId: dotenv.get('FIREBASE_PROJECT_ID', fallback: ''),
    storageBucket: dotenv.get('FIREBASE_STORAGE_BUCKET', fallback: ''),
    iosBundleId: dotenv.get('FIREBASE_IOS_BUNDLE_ID', fallback: 'com.flokou.havenkeep'),
  );
}
