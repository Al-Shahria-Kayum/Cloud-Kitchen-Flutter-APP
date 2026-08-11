import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps a critical async call with a timeout and bounded retries, so a slow
/// or hung network call surfaces an error instead of leaving the UI stuck
/// waiting indefinitely (which otherwise forces users to manually refresh).
///
/// Does not retry [PostgrestException]s (RLS/validation failures are not
/// transient — retrying them just wastes the timeout budget).
Future<T?> runGuarded<T>(
  Future<T> Function() action, {
  Duration timeout = const Duration(seconds: 10),
  int retries = 2,
  Duration retryDelay = const Duration(milliseconds: 500),
  void Function(Object error)? onError,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt <= retries; attempt++) {
    try {
      return await action().timeout(timeout);
    } on TimeoutException catch (e) {
      lastError = e;
    } on PostgrestException catch (e) {
      lastError = e;
      break;
    } catch (e) {
      lastError = e;
    }
    if (attempt < retries) {
      await Future.delayed(retryDelay * (attempt + 1));
    }
  }
  if (lastError != null) onError?.call(lastError);
  return null;
}
