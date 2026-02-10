import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Default Firebase configuration for HavenKeep.
///
/// **IMPORTANT**: Replace the placeholder values below with your actual
/// Firebase project credentials from the Firebase Console:
/// https://console.firebase.google.com/
///
/// You can generate this file automatically using the FlutterFire CLI:
///   ```
///   dart pub global activate flutterfire_cli
///   flutterfire configure
///   ```
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
          '${defaultTargetPlatform.name}. '
          'Run `flutterfire configure` to generate a valid configuration.',
        );
    }
  }

  /// Android Firebase options — replace with your values.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'havenkeep-placeholder',
    storageBucket: 'havenkeep-placeholder.appspot.com',
  );

  /// iOS Firebase options — replace with your values.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'havenkeep-placeholder',
    storageBucket: 'havenkeep-placeholder.appspot.com',
    iosBundleId: 'com.havenkeep.mobile',
  );
}
