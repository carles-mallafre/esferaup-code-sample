import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_radius.dart';
import 'package:esferaup/core/theme/app_typography.dart';

/// Assembles the EsferaUp [ThemeData] for each mode from the token palette +
/// the selected font family. Widgets read tokens via `context.colors.*`
/// (the [AppColors] extension is attached here).
abstract final class AppTheme {
  static ThemeData light(AppFontFamily font) =>
      _build(AppColors.light, Brightness.light, font);

  static ThemeData dark(AppFontFamily font) =>
      _build(AppColors.dark, Brightness.dark, font);

  static ThemeData _build(
    AppColors c,
    Brightness brightness,
    AppFontFamily font,
  ) {
    final textTheme = AppTypography.build(
      font,
    ).apply(bodyColor: c.textStrong, displayColor: c.textStrong);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.actionLabel,
      primaryContainer: c.primaryLight,
      onPrimaryContainer: c.primary,
      secondary: c.secondary,
      onSecondary: c.textOnLight,
      secondaryContainer: c.secondaryLight,
      onSecondaryContainer: c.secondary,
      tertiary: c.accent,
      onTertiary: c.textOnLight,
      error: c.error,
      onError: c.pureBlack,
      errorContainer: c.errorLight,
      onErrorContainer: c.errorInk,
      surface: c.surfaceCard,
      onSurface: c.textStrong,
      surfaceContainerLowest: c.surfaceCanvas,
      surfaceContainerLow: c.surfaceCard,
      surfaceContainerHighest: c.gray100,
      onSurfaceVariant: c.textMuted,
      outline: c.borderControl,
      outlineVariant: c.surfaceBorderSoft,
      shadow: c.pureBlack,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // App-wide default so inline widget TextStyles (no family) inherit it too.
      fontFamily: font.family,
      scaffoldBackgroundColor: c.surfaceCanvas,
      canvasColor: c.surfaceCanvas,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[c],
      splashFactory: InkSparkle.splashFactory,
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.textLink),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceCard,
        surfaceTintColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
      ),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        backgroundColor: c.surfaceCanvas,
        foregroundColor: c.textStrong,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: c.surfaceBorder),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: c.surfaceBorder,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textMuted),
        border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: c.borderControl),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: c.borderControl),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: c.error),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceCard,
        modalBarrierColor: Colors.black.withValues(alpha: 0.55),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.surfaceBorder,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // Inverse-surface pill: gray-900/gray-50 invert with the mode, so the
        // snackbar is dark-on-light in light mode and light-on-dark in dark mode
        // — always legible (the old gray-800 + white text was white-on-light in
        // dark mode).
        backgroundColor: c.gray900,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.gray50),
        actionTextColor: c.accent,
        insetPadding: const EdgeInsets.all(16),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
      ),
    );
  }
}
