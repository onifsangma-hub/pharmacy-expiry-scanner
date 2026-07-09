// lib/firebase_options.dart

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are configured for Flutter Web only.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBSX6smhkD8vF0XPyBVkNmeYCNIclOoruo',
    appId: '1:910615809009:web:d98b89b3b66c41e9325250',
    messagingSenderId: '910615809009',
    projectId: 'pharmacy-expiry-scanner',
    authDomain: 'pharmacy-expiry-scanner.firebaseapp.com',
    storageBucket: 'pharmacy-expiry-scanner.firebasestorage.app',
    measurementId: 'G-V5NTJ97XPL',
  );
}
