import 'package:esferaup/core/config/env.dart';
import 'package:esferaup/core/config/prefs.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_environment.g.dart';

/// The active API environment. Defaults to the build-time [AppEnv.current]; in
/// **debug** builds the debug env switcher can persist an override to repoint the
/// app at another backend. Release builds ignore any override (a prod build can
/// never be pointed at dev). The override is stored per build-time environment,
/// so picking another run configuration starts on that configuration's backend.
@Riverpod(keepAlive: true)
class ApiEnvironment extends _$ApiEnvironment {
  static final _key = 'debug.api_env.${AppEnv.current.name}';

  @override
  AppEnv build() {
    if (!kDebugMode) return AppEnv.current;
    final raw = ref.watch(prefsProvider).getString(_key);
    return AppEnv.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AppEnv.current,
    );
  }

  Future<void> select(AppEnv env) async {
    if (!kDebugMode || env == state) return;
    await ref.read(prefsProvider).setString(_key, env.name);
    state = env;
  }
}
