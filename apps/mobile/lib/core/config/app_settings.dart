import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/core/config/prefs.dart';

/// Persisted app-wide presentation settings: theme mode, accessibility font
/// family/text scale, and UI locale. Locale `null` == follow the device locale.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fontFamily = AppFontFamily.lexend,
    this.textScale = 1,
    this.localeCode,
  });

  final ThemeMode themeMode;
  final AppFontFamily fontFamily;
  final double textScale;
  final String? localeCode;

  Locale? get locale => localeCode == null ? null : Locale(localeCode!);

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppFontFamily? fontFamily,
    double? textScale,
    Object? localeCode = _sentinel,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontFamily: fontFamily ?? this.fontFamily,
      textScale: textScale ?? this.textScale,
      localeCode: localeCode == _sentinel
          ? this.localeCode
          : localeCode as String?,
    );
  }

  static const Object _sentinel = Object();
}

/// Reads/writes [AppSettings] to [SharedPreferences]. Synchronous reads at
/// build time (prefs already loaded in startup); setters persist + emit.
class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _kTheme = 'settings.themeMode';
  static const _kFont = 'settings.fontFamily';
  static const _kTextScale = 'settings.textScale';
  static const _kLocale = 'settings.localeCode';

  @override
  AppSettings build() {
    final prefs = ref.watch(prefsProvider);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_kTheme),
        orElse: () => ThemeMode.system,
      ),
      fontFamily: AppFontFamily.fromId(prefs.getString(_kFont)),
      textScale: normalizeAppTextScale(
        _storedTextScale(prefs.get(_kTextScale)),
      ),
      localeCode: prefs.getString(_kLocale),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref.read(prefsProvider).setString(_kTheme, mode.name);
  }

  Future<void> setFontFamily(AppFontFamily family) async {
    state = state.copyWith(fontFamily: family);
    await ref.read(prefsProvider).setString(_kFont, family.name);
  }

  Future<void> setTextScale(double scale) async {
    final normalized = normalizeAppTextScale(scale);
    state = state.copyWith(textScale: normalized);
    await ref.read(prefsProvider).setDouble(_kTextScale, normalized);
  }

  /// Pass `null` to follow the device locale.
  Future<void> setLocale(String? code) async {
    state = state.copyWith(localeCode: code);
    final prefs = ref.read(prefsProvider);
    if (code == null) {
      await prefs.remove(_kLocale);
    } else {
      await prefs.setString(_kLocale, code);
    }
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

double? _storedTextScale(Object? value) =>
    value is num ? value.toDouble() : null;

double normalizeAppTextScale(double? scale) {
  if (scale == null || !scale.isFinite) return 1;
  return scale.clamp(1, 2);
}

/// The in-app preference is a floor over the operating-system accessibility
/// setting. Multiplying the two would turn two independent 200% choices into
/// an unusable 400% scale.
TextScaler resolveAppTextScaler(TextScaler device, double preferredScale) {
  return _FlooredTextScaler(device, normalizeAppTextScale(preferredScale));
}

/// `TextScaler.clamp(minScaleFactor:)` is not usable as the app-wide floor:
/// framework widgets (the Material date picker header, for one) later call
/// `clamp(maxScaleFactor: deviceScale)` on it, and Flutter asserts
/// `maxScale > minScale` as soon as the floor equals the device scale.
class _FlooredTextScaler extends TextScaler {
  const _FlooredTextScaler(this._device, this._floor);

  final TextScaler _device;
  final double _floor;

  @override
  double scale(double fontSize) =>
      math.max(_device.scale(fontSize), fontSize * _floor);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => math.max(_device.textScaleFactor, _floor);

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    final floor = math.max(_floor, minScaleFactor);
    if (maxScaleFactor <= floor) return TextScaler.linear(maxScaleFactor);
    return _FlooredTextScaler(
      _device.clamp(
        minScaleFactor: minScaleFactor,
        maxScaleFactor: maxScaleFactor,
      ),
      floor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _FlooredTextScaler &&
      other._device == _device &&
      other._floor == _floor;

  @override
  int get hashCode => Object.hash(_device, _floor);
}
