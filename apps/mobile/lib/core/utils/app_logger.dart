import 'package:flutter/foundation.dart';

/// PII-redacting logger. Hardened for Art. 9: it NEVER logs UP/observation
/// content, child names, emails, or auth tokens — even in debug. Request/
/// response bodies are not logged by the network layer on sensitive endpoints.
///
/// In release builds, `debug`/`info` are dropped; `warn`/`error` forward to the
/// Crashlytics hooks below when `main()` has wired them (decoupled from Firebase
/// so this stays a plain util that compiles + runs without a Firebase project).
abstract final class AppLogger {
  /// Wired by `main()` after a successful Firebase init (null until then).
  static void Function(String message)? crashlyticsLog;
  static void Function(Object error, StackTrace? stack, String reason)?
  crashlyticsRecord;

  /// Verbose/trace — debug-only, dropped in release. The chattiest level.
  static void verbose(String message, {String? tag}) {
    if (kReleaseMode) return;
    debugPrint('⚪️ ${_tag(tag)}$message');
  }

  static void debug(String message, {String? tag}) {
    if (kReleaseMode) return;
    debugPrint('🔵 ${_tag(tag)}$message');
  }

  static void info(String message, {String? tag}) {
    if (kReleaseMode) return;
    debugPrint('🟢 ${_tag(tag)}$message');
  }

  static void warn(String message, {String? tag}) {
    final safe = redact('${_tag(tag)}$message');
    debugPrint('🟠 $safe');
    crashlyticsLog?.call('WARN $safe');
  }

  static void error(
    String message, [
    Object? error,
    StackTrace? stack,
    String? tag,
  ]) {
    final safe = redact('${_tag(tag)}$message');
    debugPrint('🔴 $safe');
    if (kDebugMode && stack != null) debugPrintStack(stackTrace: stack);
    crashlyticsRecord?.call(error ?? safe, stack, safe);
  }

  static String _tag(String? tag) => tag == null ? '' : '[$tag] ';

  /// Best-effort scrub of emails + bearer tokens + obvious PII keys from a
  /// string before it leaves the device path. Not a substitute for not logging
  /// sensitive data in the first place.
  static String redact(String input) {
    return input
        .replaceAll(_email, '«email»')
        .replaceAll(_bearer, 'Bearer «token»')
        .replaceAll(_jwt, '«jwt»');
  }

  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._\-]+');
  static final RegExp _jwt = RegExp(r'eyJ[A-Za-z0-9._\-]{20,}');
}
