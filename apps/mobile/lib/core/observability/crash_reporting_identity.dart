import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CrashUserIdentifierSetter = Future<void> Function(String identifier);

final crashReportingIdentityProvider =
    Provider<CrashReportingIdentityController>(
      (ref) => CrashReportingIdentityController(),
    );

/// Keeps Crashlytics attribution aligned with the active secure session.
///
/// The access token is already the server-issued session authority. Decoding
/// its payload here is used only for pseudonymous crash attribution; it never
/// grants access or replaces server-side signature validation.
class CrashReportingIdentityController {
  CrashUserIdentifierSetter? _setter;
  String _desiredIdentifier = '';
  Future<void> _operationTail = Future<void>.value();

  /// Attaches the Firebase implementation and replays the latest desired ID.
  Future<bool> attach(CrashUserIdentifierSetter setter) {
    _setter = setter;
    return _publishDesired();
  }

  /// Binds the signed-in account, or clears attribution for an invalid token.
  Future<bool> bindAccessToken(String accessToken) {
    _desiredIdentifier = _userIdentifier(accessToken) ?? '';
    return _publishDesired();
  }

  /// Clears attribution before logout, rejection, or tenant replacement.
  Future<bool> clear() {
    _desiredIdentifier = '';
    return _publishDesired();
  }

  Future<bool> _publishDesired() {
    final result = Completer<bool>();
    _operationTail = _operationTail.then((_) async {
      final setter = _setter;
      if (setter == null) {
        result.complete(true);
        return;
      }
      try {
        // Read at execution time so queued work cannot restore a superseded ID.
        await setter(_desiredIdentifier);
        result.complete(true);
      } on Object {
        result.complete(false);
      }
    });
    return result.future;
  }

  static String? _userIdentifier(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload);
      if (claims is! Map ||
          claims['aud'] != 'esferaup-api' ||
          claims['type'] != 'access') {
        return null;
      }
      final subject = claims['sub'];
      if (subject is! String || !_uuid.hasMatch(subject)) return null;
      return subject.toLowerCase();
    } on Object {
      return null;
    }
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
}
