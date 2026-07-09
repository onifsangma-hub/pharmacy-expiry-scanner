// lib/services/auth_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Thin wrapper around FirebaseAuth for email/password sign-in.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Emits the current user (or null when signed out). Drives the AuthGate.
  Stream<User?> get authState => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(String email, String password) async {
    return _runAuthAction(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  Future<UserCredential> register(String email, String password) async {
    return _runAuthAction(
      () => _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  Future<void> signOut() async {
    return _runAuthAction(_auth.signOut);
  }

  Future<T> _runAuthAction<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error, stackTrace) {
      _logAuthException(error, stackTrace);
      throw AuthFailure(_displayMessage(error), code: error.code);
    } on PlatformException catch (error, stackTrace) {
      _logPlatformException(error, stackTrace);
      final normalized = _NormalizedAuthError.fromPlatformException(error);
      throw AuthFailure(
        _displayMessage(normalized),
        code: normalized.code,
      );
    } on MissingPluginException catch (error, stackTrace) {
      _logUnexpectedAuthException(error, stackTrace);
      throw AuthFailure(describeError(error));
    } catch (error, stackTrace) {
      _logUnexpectedAuthException(error, stackTrace);
      final normalized = _NormalizedAuthError.fromUnknown(error);
      throw AuthFailure(
        _displayMessage(normalized),
        code: normalized.code,
      );
    }
  }

  /// Maps FirebaseAuthException codes to short, user-friendly messages.
  static String describeError(Object error) {
    if (error is AuthFailure) return error.message;

    if (error is _NormalizedAuthError) {
      return _friendlyMessageForCode(error.code, fallback: error.message);
    }

    if (error is FirebaseAuthException) {
      return _friendlyMessageForCode(error.code, fallback: error.message);
    }

    if (error is PlatformException) {
      final normalized = _NormalizedAuthError.fromPlatformException(error);
      return _friendlyMessageForCode(normalized.code,
          fallback: normalized.message);
    }
    if (error is MissingPluginException || _containsPigeonAuthMethod(error)) {
      return 'Authentication is still loading. Please refresh the page and try again.';
    }
    return 'Authentication failed. Please try again.';
  }

  static void _logAuthException(
    FirebaseAuthException error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      'FirebaseAuthException(code: ${error.code}, message: ${error.message})',
    );
    debugPrintStack(stackTrace: stackTrace);
  }

  static void _logPlatformException(
    PlatformException error,
    StackTrace stackTrace,
  ) {
    debugPrint(
      'Firebase auth PlatformException(code: ${error.code}, '
      'message: ${error.message}, details: ${error.details})',
    );
    debugPrint('Firebase auth PlatformException raw: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  static void _logUnexpectedAuthException(
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('Unexpected Firebase auth exception: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  static String _friendlyMessageForCode(String? code, {String? fallback}) {
    switch (_normalizeCode(code)) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Please sign in instead.';
      case 'weak-password':
        return 'That password is too weak. Use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled for this Firebase project.';
      case 'channel-error':
        if (_isUsefulFirebaseMessage(fallback)) {
          return 'Firebase Auth channel error: $fallback';
        }
        return 'Firebase Auth channel error. Refresh the page to load the latest app version and try again.';
    }

    if (_isUsefulFirebaseMessage(fallback)) return fallback!;
    return 'Authentication failed. Please try again.';
  }

  static String _displayMessage(Object error) {
    final String? rawCode;
    final String? rawMessage;
    if (error is FirebaseAuthException) {
      rawCode = error.code;
      rawMessage = error.message;
    } else if (error is _NormalizedAuthError) {
      rawCode = error.code;
      rawMessage = error.message;
    } else {
      rawCode = null;
      rawMessage = error.toString();
    }

    final code = _normalizeCode(rawCode);
    final message = _friendlyMessageForCode(code, fallback: rawMessage);
    if (code == null) return message;
    return '$message ($code)';
  }

  static String? _normalizeCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final normalized = code.trim().toLowerCase().replaceAll('_', '-');
    if (normalized.startsWith('firebase-auth/')) {
      return normalized.substring('firebase-auth/'.length);
    }
    if (normalized.startsWith('auth/')) {
      return normalized.substring('auth/'.length);
    }
    return normalized;
  }

  static bool _isUsefulFirebaseMessage(String? message) {
    if (message == null || message.trim().isEmpty) return false;
    return !_containsPigeonAuthMethod(message);
  }

  static bool _containsPigeonAuthMethod(Object? value) {
    return value
            ?.toString()
            .contains('dev.flutter.pigeon.firebase_auth_platform_interface') ??
        false;
  }
}

class _NormalizedAuthError {
  const _NormalizedAuthError({this.code, this.message});

  final String? code;
  final String? message;

  factory _NormalizedAuthError.fromPlatformException(PlatformException error) {
    final details = error.details;
    if (details is Map) {
      final code = details['code']?.toString() ??
          details['error']?.toString() ??
          details['authCode']?.toString() ??
          error.code;
      final message = details['message']?.toString() ??
          details['authMessage']?.toString() ??
          details.toString();
      return _NormalizedAuthError(code: code, message: message);
    }
    if (AuthService._containsPigeonAuthMethod(error.code) ||
        AuthService._containsPigeonAuthMethod(error.message)) {
      return const _NormalizedAuthError(
        code: 'auth-plugin-not-ready',
        message: 'Authentication is still loading. Please refresh the page.',
      );
    }
    return _NormalizedAuthError(code: error.code, message: error.message);
  }

  factory _NormalizedAuthError.fromUnknown(Object error) {
    final message = error.toString();
    if (AuthService._containsPigeonAuthMethod(message)) {
      return const _NormalizedAuthError(
        code: 'auth-plugin-not-ready',
        message: 'Authentication is still loading. Please refresh the page.',
      );
    }
    return _NormalizedAuthError(message: message);
  }
}
