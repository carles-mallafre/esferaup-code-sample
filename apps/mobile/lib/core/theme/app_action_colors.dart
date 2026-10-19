import 'package:flutter/material.dart';

abstract final class AppActionColors {
  // Filled red actions need a darker red than the mode-aware error icon token
  // so white labels retain at least 4.5:1 contrast in both themes.
  static const dangerBackground = Color(0xFFDC2626);
  static const dangerForeground = Colors.white;
}
