import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Enables the platform's native screenshot protection while a secret is visible.
class SensitiveScreenGuard {
  const SensitiveScreenGuard();

  static const _channel = MethodChannel('esferaup/privacy_screen');

  Future<void> enable() => _setEnabled(true);

  Future<void> disable() => _setEnabled(false);

  Future<void> _setEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
  }
}
