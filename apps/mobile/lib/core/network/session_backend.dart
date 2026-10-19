import 'package:esferaup/core/config/prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'session_backend.g.dart';

/// Remembers which API base URL issued the stored session. Tokens from one
/// backend are meaningless to another, so a debug build that now points at a
/// different environment must drop the old session instead of sending it.
class SessionBackendBinding {
  const SessionBackendBinding(this._prefs);

  static const _key = 'auth.session_backend';

  final SharedPreferences _prefs;

  /// [strict] treats a session with no recorded backend as foreign.
  bool matches(String baseUrl, {required bool strict}) {
    final bound = _prefs.getString(_key);
    if (bound == null) return !strict;
    return bound == baseUrl;
  }

  Future<void> bind(String baseUrl) => _prefs.setString(_key, baseUrl);
}

@Riverpod(keepAlive: true)
SessionBackendBinding sessionBackendBinding(Ref ref) =>
    SessionBackendBinding(ref.watch(prefsProvider));
