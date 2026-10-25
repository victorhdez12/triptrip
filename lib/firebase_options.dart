// lib/firebase_options.dart
//
// La configuración de Firebase se inyecta en tiempo de compilación con
// --dart-define-from-file=env/dart_defines.json (ver README.md).
// Nunca subas valores reales a este archivo.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const String _apiKey            = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _authDomain        = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const String _projectId         = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _storageBucket     = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String _messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _appId             = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _measurementId     = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            _apiKey,
    authDomain:        _authDomain,
    projectId:         _projectId,
    storageBucket:     _storageBucket,
    messagingSenderId: _messagingSenderId,
    appId:             _appId,
    measurementId:     _measurementId,
  );

  static const FirebaseOptions android = web;
  static const FirebaseOptions ios = web;
}
