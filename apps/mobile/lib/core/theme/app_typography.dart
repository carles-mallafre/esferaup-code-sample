import 'package:flutter/material.dart';

/// User-selectable font family (accessibility — Configuració → Tipografia).
/// Lexend is the default; OpenDyslexic / Atkinson Hyperlegible / Nunito are
/// alternatives. The `.family` strings resolve once the `.ttf` assets are
/// bundled (spec §5.2); until then Flutter falls back to the platform font.
enum AppFontFamily {
  lexend('Lexend'),
  openDyslexic('OpenDyslexic'),
  atkinson('Atkinson Hyperlegible'),
  nunito('Nunito');

  const AppFontFamily(this.family);
  final String family;

  static AppFontFamily fromId(String? id) => AppFontFamily.values.firstWhere(
    (f) => f.name == id,
    orElse: () => AppFontFamily.lexend,
  );
}

/// Builds the EsferaUp type ramp for [family]. Colors are applied by [AppTheme]
/// via `textTheme.apply(...)`, so sizes/weights/heights live here only.
///
/// Every text style reflows under the OS `textScaler` + the in-app font-size
/// slider (no fixed line clipping) — 200% scaling is a hard requirement.
abstract final class AppTypography {
  static TextTheme build(AppFontFamily family) {
    final f = family.family;
    TextStyle s(double size, FontWeight weight, double height) => TextStyle(
      fontFamily: f,
      fontSize: size,
      fontWeight: weight,
      height: height,
    );

    return TextTheme(
      displayLarge: s(32, FontWeight.w700, 1.20),
      displayMedium: s(28, FontWeight.w700, 1.22),
      displaySmall: s(26, FontWeight.w700, 1.24),
      headlineLarge: s(24, FontWeight.w700, 1.26),
      headlineMedium: s(22, FontWeight.w600, 1.28),
      headlineSmall: s(20, FontWeight.w600, 1.30),
      titleLarge: s(18, FontWeight.w600, 1.32),
      titleMedium: s(16, FontWeight.w600, 1.34),
      titleSmall: s(14, FontWeight.w600, 1.36),
      bodyLarge: s(16, FontWeight.w400, 1.45),
      bodyMedium: s(14, FontWeight.w400, 1.45),
      bodySmall: s(13, FontWeight.w400, 1.42),
      labelLarge: s(14, FontWeight.w600, 1.30),
      labelMedium: s(12, FontWeight.w600, 1.30),
      labelSmall: s(11, FontWeight.w600, 1.30),
    );
  }
}
