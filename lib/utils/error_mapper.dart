import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a raw Supabase/Postgrest/Auth exception (or its already-stringified
/// form, since most providers store `e.toString()`) into a short message a
/// user can actually act on. Never surface a raw `PostgrestException(...)` /
/// `AuthException(...)` string in a SnackBar — always pass it through this.
String friendlyErrorMessage(Object? error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error == null) return fallback;

  if (error is AuthException) {
    return _authMessage(error.message) ?? fallback;
  }

  if (error is PostgrestException) {
    return _postgrestMessage(error.code, error.message) ?? fallback;
  }

  // Most providers in this app catch as `Object e` and store `e.toString()`,
  // so by the time this reaches the UI it's often already a plain String.
  // Postgrest/Auth exceptions stringify predictably (e.g.
  // `PostgrestException(message: ..., code: 42501, ...)`), so sniff it.
  final text = error.toString();

  final codeMatch = RegExp(r'code:\s*"?([A-Za-z0-9]+)"?').firstMatch(text);
  if (text.contains('PostgrestException')) {
    return _postgrestMessage(codeMatch?.group(1), text) ?? fallback;
  }
  if (text.contains('AuthException') || text.contains('AuthApiException') || text.contains('AuthRetryableFetchException')) {
    return _authMessage(text) ?? fallback;
  }
  if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException') || text.contains('Network is unreachable')) {
    return 'No internet connection. Please check your network and try again.';
  }
  if (text.contains('StorageException')) {
    return 'We couldn\'t upload that image. Please try again.';
  }

  return fallback;
}

String? _postgrestMessage(String? code, String message) {
  final m = message.toLowerCase();
  switch (code) {
    case '42501':
      // Row-level security violation — the action was blocked by a
      // permissions rule rather than failing outright.
      if (m.contains('ratings')) return 'You can only rate orders that belong to you.';
      if (m.contains('messages')) return 'You don\'t have permission to send that message.';
      if (m.contains('orders')) return 'You don\'t have permission to update this order.';
      return 'You don\'t have permission to do that.';
    case '23505':
      if (m.contains('ratings')) return 'You\'ve already submitted feedback for this.';
      return 'This already exists.';
    case '23503':
      return 'That item is no longer available.';
    case '23514':
      return 'That value isn\'t allowed here.';
    case 'PGRST116':
      return 'We couldn\'t find what you were looking for.';
  }
  return null;
}

String? _authMessage(String message) {
  final m = message.toLowerCase();
  if (m.contains('invalid login credentials') || m.contains('invalid_credentials')) {
    return 'Incorrect email or password.';
  }
  if (m.contains('email not confirmed')) {
    return 'Please confirm your email before logging in.';
  }
  if (m.contains('user already registered') || m.contains('already registered')) {
    return 'An account with this email already exists.';
  }
  if (m.contains('password should be at least') || m.contains('password is too short')) {
    return 'Password is too short.';
  }
  if (m.contains('rate limit') || m.contains('too many requests')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (m.contains('invalid email')) {
    return 'That doesn\'t look like a valid email address.';
  }
  if (m.contains('network') || m.contains('timeout')) {
    return 'No internet connection. Please check your network and try again.';
  }
  return 'We couldn\'t sign you in. Please check your details and try again.';
}
